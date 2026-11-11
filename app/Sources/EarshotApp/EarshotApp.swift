import AppKit
import EarshotActions
import EarshotCore
import EarshotDiscovery
import EarshotInput
import EarshotRouter
import EarshotSpeech
import EarshotUI
import EarshotWake
import ServiceManagement
import SwiftUI

// T7: the menu-bar helper. It connects the modules. The management window is in EarshotUI (T6).

@main
struct EarshotApp: App {
    @StateObject private var app = AppController()

    var body: some Scene {
        MenuBarExtra {
            Text(app.listenLabel)
            Text(app.status)
            Divider()
            Button(app.isPaused ? "Resume listening" : "Pause for 1 hour") {
                if app.isPaused { app.resume() } else { app.pause(seconds: AppController.pauseSeconds) }
            }
            Picker("Mode", selection: Binding(get: { app.settings.mode }, set: { app.setMode($0) })) {
                Text("Hold key").tag(InputMode.hold)
                Text("Always on").tag(InputMode.alwaysOn)
            }
            Divider()
            OpenManageButton()
            Toggle("Start at login", isOn: Binding(get: { app.startsAtLogin }, set: { app.setStartsAtLogin($0) }))
            Divider()
            Button("Quit earshot") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: ListenIcon.symbol(app.listen))
                .accessibilityLabel("earshot: " + app.listenLabel)
        }
        Window("earshot", id: "manage") {
            ManageView(settings: $app.settings, store: app.store, hooks: app.hooks)
                .frame(minWidth: 680, minHeight: 460)
        }
    }
}

private struct OpenManageButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Manage…") {
            openWindow(id: "manage")
            // T6: activate the app, move the window to this Space and bring it to the front.
            ManageWindow.bringToFront()
        }
    }
}

/// Owns the modules and the command pipeline. Runs on the main thread.
@MainActor
final class AppController: ObservableObject {
    @Published var settings: EarshotSettings
    /// The settings that the running parts use now. The Manage window binds to `settings`, so `settings` already
    /// has the new values when apply(_:) runs. apply(_:) compares the new values with this copy.
    private var applied: EarshotSettings
    @Published var status = "Starting…"
    @Published var startsAtLogin = SMAppService.mainApp.status == .enabled
    /// What earshot does with the microphone now, for the menu bar icon (gap list item 10).
    @Published var listen = ListenState.idle
    /// The facts that give `listen`. Change it only with `updateListen`.
    var listenClock = ListenClock()
    /// Reads `listen` again when a window or the pause ends.
    var listenTimer: DispatchWorkItem?

    let store = Store()
    /// The owner's last answers to ties (gap item 6), in the store folder.
    let habits = TieHabits(store: Store())
    let feedback = FeedbackNote()
    let catalogue = MenuCatalogue()
    let names: NameIndex
    let runner: EarshotActionRunner
    let pipeline: CommandPipeline
    /// The turn recorder of always-on mode (E7): numbers only, 7 days.
    let turns: TurnRecorder
    var input: InputSwitch?
    private var engineWhy = ""
    /// The wake phrase models (D-11). They load when always-on mode is on, and stay loaded.
    private var wake: WakeModels?
    private var wakeLoad: Task<Void, Never>?
    /// The state of the wake phrase models, for the management window.
    private var wakeState = "The wake phrase models load when you turn on always-on mode."
    /// The download part, 0 to 1, while the models download.
    private let wakeProgress = Counter()
    /// The microphone of the running wake listener: its voice profile is the profile of this microphone (E6).
    private var listenerMic: InputDevice?
    /// Starts always-on again with the right voice profile when the default microphone changes.
    private var micWatcher: InputDeviceWatcher?
    /// Reads the name cache at start and every 8 minutes (NameIndex.maxAge is 10 minutes). Read only.
    private var warmer: NameWarmer?
    /// The menu items of the front app. Read when an app comes to the front and after each command, never in a command.
    let menus: MenuCache
    private var menuObserver: NSObjectProtocol?
    private var keyObserver: NSObjectProtocol?
    /// The start sound, loaded once, so that it plays at once on key down or wake (dk: "as Hex does").
    private let startSound: NSSound? = {
        let s = NSSound(named: FeedbackSound.start.systemName)
        s?.volume = FeedbackSound.start.volume
        return s
    }()

    /// A silent copy of the start sound, played once at start: the first play opens the audio device (84-124 ms
    /// cold, 20-31 ms after; a quiet probe on the owner's Mac, 2026-11-02).
    private var warmUpSound: NSSound?

    /// Opens the audio device with a silent play, so that the first real start sound is fast.
    func warmUpStartSound() {
        warmUpSound = startSound?.copy() as? NSSound
        warmUpSound?.volume = 0
        warmUpSound?.play()
    }

    /// Plays the start sound, if "Play sounds" is on. It restarts the sound if it still plays.
    /// The length of a system sound in seconds, or 0 for none. The always-on detector ignores the audio for that time.
    nonisolated static func seconds(of sound: FeedbackSound?) -> Double {
        guard let sound else { return 0 }
        return NSSound(named: sound.systemName)?.duration ?? 0
    }

    func playStartSound() {
        guard settings.playSounds, let s = startSound else { return }
        if s.isPlaying { s.stop() }
        s.play()
    }

    init() {
        let store = self.store
        let habits = self.habits
        let settings = store.settings
        self.settings = settings
        applied = settings
        names = NameIndex(apps: { store.apps }, store: store)
        runner = EarshotActionRunner(options: ActionOptions(settings: settings), store: store)
        turns = TurnRecorder(store: store, settings: settings)
        let (engine, why) = SpeechEngines.make(settings)
        engineWhy = why
        let names = self.names
        let lastNotReady = Counter()
        pipeline = CommandPipeline(engine: engine, router: Self.router(settings, habits: habits), actions: runner, names: names,
                                   apps: { store.apps }, allNames: { await Self.chatNames(names, apps: store.apps, notReady: { lastNotReady.value = $0 }) },
                                   frontBundleID: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier })
        pipeline.namesNotReady = { lastNotReady.value }
        pipeline.habits = habits
        let frontTracker = FrontTracker(own: Bundle.main.bundleIdentifier)
        pipeline.ownBundleID = Bundle.main.bundleIdentifier
        pipeline.restoreFront = { await frontTracker.restore() }
        let menuIndex = MenuIndex()
        let menus = MenuCache(read: { await menuIndex.refresh(bundleID: $0) })
        self.menus = menus
        pipeline.menus = { menus.cached($0) }
        menuObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            frontTracker.activated(app)
            if let id = app.bundleIdentifier { menus.refresh(id) }
        }
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier { menus.refresh(front) }
        applyJev()
        warmUpStartSound()
        keyObserver = NotificationCenter.default.addObserver(forName: KeychainSecret.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyJev() }
        }
        pipeline.feedback = feedback
        let activityLog = ActivityLog(store: store)
        pipeline.log = activityLog
        // The log keeps 30 days (gap item 11): remove older records at start, then every 6 hours, off the main thread.
        Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? activityLog.prune()
                try? await Task.sleep(nanoseconds: 6 * 3_600 * 1_000_000_000)
            }
        }
        pipeline.showFeedback = settings.showFeedback
        pipeline.playSounds = settings.playSounds
        pipeline.playSound = { kind in DispatchQueue.main.async { NSSound(named: kind.systemName).map { $0.volume = kind.volume; $0.play() } } }
        pipeline.wakePhrase = settings.wakePhrase
        prepareEngine()
        startInput()
        let appsFile = store.folder.appendingPathComponent("apps.json")
        let warmer = NameWarmer(interval: 480, trusted: { AXIsProcessTrusted() },
                                refresh: { _ = await names.refresh() },
                                changeToken: { (try? FileManager.default.attributesOfItem(atPath: appsFile.path))?[.modificationDate] as? Date })
        self.warmer = warmer
        let catalogue = self.catalogue
        Task {
            await Self.startUp(trusted: { AXIsProcessTrusted() },
                               refreshCatalogue: { _ = try await catalogue.refresh(store: store) },
                               startNames: { warmer.start() })
        }
    }

    /// At start: read the app catalogue again (read only; T4 keeps the owner's approvals and edits, and adds the
    /// app's own aliases), then start the name cache. So the owner does not have to press "Discover apps" after an
    /// update. With Accessibility off, the scan does not run. An error goes to the system log only.
    nonisolated static func startUp(trusted: () -> Bool, refreshCatalogue: () async throws -> Void,
                                    startNames: () -> Void) async {
        if trusted() {
            do { try await refreshCatalogue() } catch { NSLog("earshot: catalogue refresh at start: \(error)") }
        }
        startNames()
    }

    var hooks: ManageHooks {
        let pipeline = self.pipeline, catalogue = self.catalogue, store = self.store, names = self.names
        return ManageHooks(
            test: { text, run in await pipeline.test(text, runActions: run) },
            discoverApps: { [feedback] in
                await Self.discover(refresh: { try await catalogue.refresh(store: store) }, current: store.apps, feedback: feedback)
            },
            refreshNames: { appID in await names.refresh(appIDs: [appID]) },
            feedback: feedback,
            settingsChanged: { [weak self] new in self?.apply(new) },
            voice: VoiceHooks(
                status: { [weak self] in self?.voiceStatus() ?? "" },
                record: { [weak self] in try await self?.recordPhrase() ?? [] },
                teach: { [weak self] phrase, clips in
                    guard let self else { throw WakeError("earshot is closing.") }
                    return try await self.teachVoice(phrase: phrase, clips: clips)
                },
                forget: { [weak self] in self?.forgetVoice() }))
    }

    /// Runs the catalogue scan. On an error, for example DiscoveryError.accessibilityOff (first live test: the scan
    /// ran before Accessibility was on, and saved rows with no chat keys), the note shows the error, and the Apps tab
    /// keeps the current rows.
    nonisolated static func discover(refresh: () async throws -> [AppEntry], current: [AppEntry],
                                     feedback: FeedbackSink?) async -> [AppEntry] {
        do { return try await refresh() } catch {
            feedback?.show("Discover apps: \(error.localizedDescription)", ok: false)
            return current
        }
    }

    /// The names of every approved, enabled chat app. NameIndex adds the owner's own chat to each app, and reads a
    /// sidebar only when its cache is old. It presses nothing. (`all()` holds only the cache, so it was empty until
    /// a manual refresh, and "me" was unknown in the first live test.)
    /// The names for a command. Each chat app reads in its own task. The command waits at most `budgetMs` in total
    /// and uses the names that are ready: a cached app answers in under 1 ms. A slow read (a sidebar under memory
    /// pressure, or a newly approved app) keeps running and fills the cache for the next command.
    /// Live test: three newly approved chat apps made the names stage 3.4 s.
    nonisolated static func chatNames(_ index: NameFinder, apps: [AppEntry], budgetMs: Double = 150,
                                      notReady: ((Int) -> Void)? = nil) async -> [NameEntry] {
        let ids = apps.filter { $0.isChat && $0.approved && $0.enabled }.map(\.id)
        notReady?(0)
        guard !ids.isEmpty else { return [] }
        let box = NameBox()
        for id in ids { Task { await box.add(await index.names(appID: id)) } }
        let clock = Stopwatch()
        while await box.count < ids.count, clock.ms < budgetMs {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        notReady?(ids.count - (await box.count))
        return await box.names
    }

    /// Makes the Jev router and the screenshot picker again: at start, after a settings change, and after a new key.
    private func applyJev() {
        pipeline.router = Self.router(settings, habits: habits)
        pipeline.picker = ScreenPickerFactory.make(settings, jevKey: settings.jevSeesScreen ? KeychainSecret.jev.read() : nil)
        pipeline.jevScreenBudgetMs = settings.jevScreenBudgetMs
    }

    static func router(_ settings: EarshotSettings, habits: TieHabits) -> CommandRouter {
        var router = CommandRouter(settings: settings, jevKey: settings.tier2 == .jev ? KeychainSecret.jev.read() : nil)
        router.habits = habits
        return router
    }

    /// Loads the speech model in the background. Parakeet takes about 15 s; commands before that get an error note.
    private func prepareEngine() {
        let engine = pipeline.engine
        applyPhraseHints()
        status = "Loading speech (\(engineWhy))…"
        Task {
            do {
                try await engine.prepare()
                status = "Ready · \(engine.id) · \(settings.mode == .hold ? "hold key" : "always on")"
            } catch {
                status = "Speech did not load: \(error)"
            }
        }
    }

    /// In always-on mode, the speech engine gets the wake phrase as context, so that Apple speech spells it right more
    /// often (D-11). In hold mode, no hints.
    /// In hold mode, the microphone is open only while the key is down (`MicIdle`).
    private func applyPhraseHints() {
        let hints = settings.mode == .alwaysOn ? [settings.wakePhrase] : []
        (pipeline.engine as? PhraseHintControl)?.setPhraseHints(hints)
        (pipeline.engine as? MicIdleControl)?.setMicIdleClose(seconds: MicIdle.seconds(for: settings.mode))
    }

    func startInput() {
        input?.stop()
        applyPhraseHints()
        // Paused: no input runs, and the microphone of the speech engine closes (gap list item 10).
        if isPaused {
            input = nil
            (pipeline.engine as? MicIdleControl)?.setMicIdleClose(seconds: MicIdle.holdSeconds)
            return
        }
        let listener = makeWakeListener()
        let input = InputTriggers.make(settings, wake: listener)
        let pipeline = self.pipeline, menus = self.menus, feedback = self.feedback, turns = self.turns
        let gate = settings.voiceGate
        input.onStart = { [weak self, weak input] in
            // Hold key: open the microphone first, then the start sound. The microphone is closed between commands
            // (`MicIdle`), and the sound set-up takes about 150 ms. So the sound now says: the microphone is live.
            // A wake plays the sound in onWake.
            let problem = pipeline.begin()
            if input?.current == .hold { self?.playStartSound() }
            self?.updateListen { $0.turnStarted() }
            if let problem { self?.feedback.show(problem, ok: false) }
        }
        input.onCancel = { [weak self] why in
            self?.updateListen { $0.turnDropped() }
            // A wake turn played the start sound: if the voice check drops it, it gets a cue (gap item 7).
            let wake = pipeline.pendingWake
            let cue = CommandPipeline.cuesDrop(why, wake: wake)
            // Log the voice score of a turn that the voice check dropped, for the limits (no text).
            let turn = turns.take()
            var activity: ActivityRecord?
            if why.hasPrefix(WakeTrigger.otherVoice) || why.hasPrefix(WakeTrigger.tooShort) {
                activity = pipeline.droppedTurn(why)
            }
            turns.write(turn, activity: activity)
            pipeline.pendingWake = nil
            pipeline.turnVoice = nil
            Task { if cue { await pipeline.dropWakeTurn(wake) } else { await pipeline.cancel() } }
        }
        input.onStop = { [weak self, weak input] in
            let mode = input?.current ?? .hold
            let turn = mode == .alwaysOn ? turns.take() : nil
            Task { @MainActor in
                let record = await pipeline.finish(mode: mode)
                turns.write(turn, activity: record)
                // After an always-on command, the owner's voice can give the next one with no wake phrase.
                // A follow-up turn that was not a command does not open the window again: it was talk, not a command.
                let window = mode == .alwaysOn && !record.heard.isEmpty && !pipeline.followUpMissed
                let sound = Self.seconds(of: pipeline.lastSound)
                if window {
                    input?.commandFinished(expectsText: pipeline.expectsText, soundSeconds: sound)
                }
                self?.updateListen {
                    $0.turnFinished(at: Date(), followUpSeconds: window ? (input?.alwaysOn as? WakeTrigger)?.config.followUpSeconds : nil,
                                    soundSeconds: sound, armedUntil: pipeline.armedUntil,
                                    expectsText: window && pipeline.expectsText)
                }
                // A command can change which items are enabled ("Copy" after "select all"). Read again for the next one.
                if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier { menus.refresh(front) }
            }
        }
        if let trigger = input.alwaysOn as? WakeTrigger {
            trigger.onWake = { [weak self, weak trigger] hit in
                self?.playStartSound()
                // The Tink must not count as the start or the end of the command after the phrase.
                if self?.settings.playSounds == true { trigger?.mute(seconds: Self.seconds(of: .start)) }
                // The speech engine must start at the phrase: the spotter fires after the phrase ends.
                // A phrase in a follow-up turn comes when the engine runs already: no new preroll.
                if hit.inTurnAfterSeconds == nil {
                    (pipeline.engine as? PrerollControl)?.setNextPreroll(seconds: hit.prerollSeconds)
                }
                pipeline.pendingWake = hit
                if self?.settings.showFeedback == true { feedback.show("Listening…", ok: true) }
            }
            trigger.onRejected = { hit in turns.write(turns.take(), activity: pipeline.rejectedWake(hit, threshold: gate)) }
            trigger.onRecord = { record in turns.hold(record) }
            trigger.onTurnVoice = { voice in pipeline.turnVoice = voice }
            trigger.onVoiceLearned = { [weak self] profile in self?.saveLearnedVoice(profile) }
            trigger.onNearMisses = { misses in pipeline.nearMisses(misses) }
            trigger.onTurnCheck = { check in pipeline.turnCheck(check) }
            trigger.onTurnEnd = { end in pipeline.turnEnd(end) }
        }
        pipeline.pauseAlwaysOn = { [weak input] paused in
            DispatchQueue.main.async { input?.setAlwaysOnPaused(paused) }
        }
        do {
            try input.start()
        } catch {
            status = "Input did not start: \(error)"
        }
        self.input = input
    }

    /// The wake phrase listener for always-on mode, or nil. If the models are not loaded yet, it starts the load,
    /// and the input starts again when they are ready. Until then, always-on mode has the hold key only.
    private func makeWakeListener() -> WakeListener? {
        guard settings.mode == .alwaysOn else { return nil }
        guard let wake else { loadWakeModels(); return nil }
        watchMicrophone()
        let mic = InputDevice.current
        listenerMic = mic
        let book = store.voiceBook
        let profile = book.profile(forMic: mic?.id)
        if let profile, let mic, !book.hasProfile(forMic: mic.id) {
            NSLog("earshot wake: no voice profile for the microphone \"%@\"; the profile of \"%@\" is used",
                  mic.name, profile.micName ?? "an unknown microphone")
        }
        do {
            // The phrase alone only has to pass the gate. The voice of the whole turn decides at its end (E6).
            // The profile learns from good wake turns only on its own microphone (an older profile has none).
            let learns = profile.map { $0.micID == nil || $0.micID == mic?.id } ?? false
            return try wake.listener(phrase: settings.wakePhrase, profile: profile, voiceThreshold: settings.voiceGate,
                                     learns: learns)
        } catch {
            wakeState = "The wake phrase did not start: \(error.localizedDescription)"
            status = wakeState
            return nil
        }
    }

    /// Downloads (one time, about 35 MB with the turn model) and loads the wake phrase models in the background (D-11).
    private func loadWakeModels() {
        guard wake == nil, wakeLoad == nil else { return }
        let folder = store.folder, progress = wakeProgress
        let downloaded = WakeModels.isDownloaded(store: folder)
        wakeState = downloaded ? "Loading the wake phrase models…" : "Downloading the wake phrase models (about 35 MB, one time)…"
        status = wakeState
        wakeLoad = Task { [weak self] in
            let result: Result<WakeModels, Error>
            do {
                result = .success(try await Task.detached(priority: .utility) {
                    try await WakeModels.load(store: folder) { part in progress.value = Int(part * 100) }
                }.value)
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            self.wakeLoad = nil
            switch result {
            case .success(let models):
                self.wake = models
                self.wakeState = String(format: "The wake phrase models are ready (load %.0f ms).", models.loadMs)
                    + (models.hasTurnModel ? " The turn model is ready." : " The turn model is not loaded: a pause alone ends a turn.")
                if self.settings.mode == .alwaysOn {
                    self.startInput()
                    self.status = "Ready · \(self.pipeline.engine.id) · always on (\"\(self.settings.wakePhrase)\")"
                }
            case .failure(let error):
                self.wakeState = "The wake phrase models did not load: \(error.localizedDescription)"
                self.status = self.wakeState
            }
        }
    }

    /// Starts the watch of the default microphone, one time.
    private func watchMicrophone() {
        guard micWatcher == nil else { return }
        micWatcher = InputDeviceWatcher { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.settings.mode == .alwaysOn, self.input != nil else { return }
                let mic = InputDevice.current
                guard mic?.id != self.listenerMic?.id else { return }
                NSLog("earshot wake: the microphone is now \"%@\": always-on starts again with its voice profile",
                      mic?.name ?? "none")
                self.startInput()
            }
        }
    }

    /// One line for the management window: the models and the owner's voice.
    /// Saves a profile that learned the voice of a good wake turn (E6, section 8.2). A teach step since then made a
    /// new profile for that microphone: then the learned one is old, and it is not saved.
    private func saveLearnedVoice(_ profile: VoiceProfile) {
        let current = store.voiceBook.profiles.contains { $0.micID == profile.micID && $0.createdAt == profile.createdAt }
        guard current else { return }
        do { try store.saveVoiceProfile(profile) } catch {
            NSLog("earshot wake: the learned voice was not saved: %@", "\(error)")
        }
    }

    private func voiceStatus() -> String {
        var line = wakeLoad != nil && !WakeModels.isDownloaded(store: store.folder)
            ? "Downloading the wake phrase models: \(wakeProgress.value) %." : wakeState
        let mic = InputDevice.current
        let book = store.voiceBook
        if let profile = book.profile(forMic: mic?.id) {
            let date = profile.createdAt.formatted(date: .abbreviated, time: .omitted)
            line += " Your voice: taught on \(date), \(profile.samples) phrases"
            line += profile.micName.map { " with \"\($0)\"" } ?? ""
            let learned = profile.learnedTurns?.count ?? 0
            line += learned > 0 ? ", and learned from \(learned) of your wake turns." : "."
            if let mic, !book.hasProfile(forMic: mic.id) {
                line += " The microphone now is \"\(mic.name)\". Teach earshot again with it: the voice check is surer"
                    + " on the microphone of the teach step."
            }
            if book.profiles.count > 1 {
                line += " earshot keeps \(book.profiles.count) voice profiles, one for each microphone."
            }
            if !profile.matches(phrase: settings.wakePhrase) {
                line += " You taught it with \"\(profile.phrase)\". Teach it again with the new phrase for the best match."
            } else if profile.templates(for: settings.wakePhrase).count < 3 {
                line += " Teach it again: earshot now finds the phrase by its sound, and it needs new phrases for that."
            }
        } else {
            line += " Your voice: not taught. Until you teach it, any voice can wake earshot."
        }
        return line
    }

    /// Records one enrolment phrase. Always-on pauses, so that the phrase does not wake earshot.
    private func recordPhrase() async throws -> [Float] {
        input?.setAlwaysOnPaused(true)
        defer { input?.setAlwaysOnPaused(false) }
        return try await PhraseRecorder.record()
    }

    /// Makes and saves the voice profile, then starts always-on again with it.
    private func teachVoice(phrase: String, clips: [[Float]]) async throws -> String {
        guard let wake else { throw WakeError("The wake phrase models are not ready yet. Turn on always-on mode and wait.") }
        let mic = InputDevice.current
        let enrolment = try await Task.detached(priority: .userInitiated) { try wake.enrol(phrase: phrase, clips: clips) }.value
        // The profile belongs to the microphone of the teach step. It replaces only the profile of that microphone.
        var profile = enrolment.profile
        profile.micID = mic?.id
        profile.micName = mic?.name
        try store.saveVoiceProfile(profile)
        let record = pipeline.voiceTaught(phrase: phrase, mic: mic?.name, takeScores: enrolment.takeScores,
                                          templatesKept: enrolment.templatesKept, selfScore: profile.selfScore,
                                          profiles: store.voiceBook.profiles.count)
        NSLog("earshot wake: %@", record.note)
        if settings.mode == .alwaysOn { startInput() }
        return enrolment.summary
    }

    private func forgetVoice() {
        try? store.saveVoiceProfile(nil)
        if settings.mode == .alwaysOn { startInput() }
    }

    /// The management window changed the settings (it saved them already).
    func apply(_ new: EarshotSettings) {
        // Compare with the settings that the running parts use, not with `settings`: the window changed `settings`
        // already, so a comparison with it found no change, and a new wake phrase did not reach the listener.
        let restart = SettingsRestart.needed(from: applied, to: new)
        applied = new
        if settings != new { settings = new }
        pipeline.showFeedback = new.showFeedback
        pipeline.playSounds = new.playSounds
        pipeline.wakePhrase = new.wakePhrase
        turns.apply(new)
        runner.options = ActionOptions(settings: new)
        if restart.contains(.jev) { applyJev() }
        if restart.contains(.engine) {
            // Close the microphone of the old engine first. The old engine then has no owner, so its deinit frees
            // the Parakeet model, and two models do not stay loaded.
            Self.shutdown(pipeline.engine)
            let (engine, why) = SpeechEngines.make(new)
            engineWhy = why
            pipeline.engine = engine
            prepareEngine()
        }
        if restart.contains(.input) { startInput() }
    }

    /// Stops an engine: the microphone closes and the timers stop (T1).
    static func shutdown(_ engine: SpeechEngine) {
        let active = (engine as? FallbackSpeechEngine)?.active ?? engine
        (active as? TurnSpeechEngine)?.shutdown()
    }

    /// Start at login: off by default. The state lives in macOS (SMAppService), not in settings.json.
    func setStartsAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            feedback.show("Start at login: \(error.localizedDescription)", ok: false)
        }
        startsAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Collects the names of the chat apps as their reads finish.
actor NameBox {
    private(set) var names: [NameEntry] = []
    private(set) var count = 0
    func add(_ more: [NameEntry]) { names += more; count += 1 }
}

/// The number of chat apps whose names were not ready in the last command (for the log).
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
