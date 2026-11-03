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
        MenuBarExtra("earshot", systemImage: "ear") {
            Text(app.status)
            Divider()
            OpenManageButton()
            Toggle("Start at login", isOn: Binding(get: { app.startsAtLogin }, set: { app.setStartsAtLogin($0) }))
            Divider()
            Button("Quit earshot") { NSApplication.shared.terminate(nil) }
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

    let store = Store()
    let feedback = FeedbackNote()
    let catalogue = MenuCatalogue()
    let names: NameIndex
    let runner: EarshotActionRunner
    let pipeline: CommandPipeline
    private var input: InputSwitch?
    private var engineWhy = ""
    /// The wake phrase models (D-11). They load when always-on mode is on, and stay loaded.
    private var wake: WakeModels?
    private var wakeLoad: Task<Void, Never>?
    /// The state of the wake phrase models, for the management window.
    private var wakeState = "The wake phrase models load when you turn on always-on mode."
    /// The download part, 0 to 1, while the models download.
    private let wakeProgress = Counter()
    /// Reads the name cache at start and every 8 minutes (NameIndex.maxAge is 10 minutes). Read only.
    private var warmer: NameWarmer?
    /// The menu items of the front app. Read when an app comes to the front and after each command, never in a command.
    let menus: MenuCache
    private var menuObserver: NSObjectProtocol?
    private var keyObserver: NSObjectProtocol?

    init() {
        let store = self.store
        let settings = store.settings
        self.settings = settings
        applied = settings
        names = NameIndex(apps: { store.apps }, store: store)
        runner = EarshotActionRunner(options: ActionOptions(settings: settings), store: store)
        let (engine, why) = SpeechEngines.make(settings)
        engineWhy = why
        let names = self.names
        let lastNotReady = Counter()
        pipeline = CommandPipeline(engine: engine, router: Self.router(settings), actions: runner, names: names,
                                   apps: { store.apps }, allNames: { await Self.chatNames(names, apps: store.apps, notReady: { lastNotReady.value = $0 }) },
                                   frontBundleID: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier })
        pipeline.namesNotReady = { lastNotReady.value }
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
        keyObserver = NotificationCenter.default.addObserver(forName: KeychainSecret.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyJev() }
        }
        pipeline.feedback = feedback
        pipeline.log = ActivityLog(store: store)
        pipeline.showFeedback = settings.showFeedback
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
        pipeline.router = Self.router(settings)
        pipeline.picker = ScreenPickerFactory.make(settings, jevKey: settings.jevSeesScreen ? KeychainSecret.jev.read() : nil)
        pipeline.jevScreenBudgetMs = settings.jevScreenBudgetMs
    }

    static func router(_ settings: EarshotSettings) -> CommandRouter {
        CommandRouter(settings: settings, jevKey: settings.tier2 == .jev ? KeychainSecret.jev.read() : nil)
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
    private func applyPhraseHints() {
        let hints = settings.mode == .alwaysOn ? [settings.wakePhrase] : []
        (pipeline.engine as? PhraseHintControl)?.setPhraseHints(hints)
    }

    private func startInput() {
        input?.stop()
        applyPhraseHints()
        let listener = makeWakeListener()
        let input = InputTriggers.make(settings, wake: listener)
        let pipeline = self.pipeline, menus = self.menus, feedback = self.feedback
        let threshold = settings.voiceThreshold
        input.onStart = { [weak self] in
            if let problem = pipeline.begin() { self?.feedback.show(problem, ok: false) }
        }
        input.onCancel = { why in
            pipeline.pendingWake = nil
            // Log the voice score of a dropped follow-up turn, for the voice threshold (no text).
            if why.hasPrefix(WakeTrigger.otherVoice) || why.hasPrefix(WakeTrigger.tooShort) { pipeline.droppedFollowUp(why) }
            Task { await pipeline.cancel() }
        }
        input.onStop = { [weak input] in
            let mode = input?.current ?? .hold
            pipeline.followUpVoiceScore = (input?.alwaysOn as? WakeTrigger)?.lastFollowUpVoiceScore
            Task { @MainActor in
                let record = await pipeline.finish(mode: mode)
                // After an always-on command, the owner's voice can give the next one with no wake phrase.
                if mode == .alwaysOn, !record.heard.isEmpty { input?.commandFinished() }
                // A command can change which items are enabled ("Copy" after "select all"). Read again for the next one.
                if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier { menus.refresh(front) }
            }
        }
        if let trigger = input.alwaysOn as? WakeTrigger {
            trigger.onWake = { [weak self] hit in
                // The speech engine must start at the phrase: the spotter fires after the phrase ends.
                // A phrase in a follow-up turn comes when the engine runs already: no new preroll.
                if hit.inTurnAfterSeconds == nil {
                    (pipeline.engine as? PrerollControl)?.setNextPreroll(seconds: hit.prerollSeconds)
                }
                pipeline.pendingWake = hit
                if self?.settings.showFeedback == true { feedback.show("Listening…", ok: true) }
            }
            trigger.onRejected = { hit in pipeline.rejectedWake(hit, threshold: threshold) }
            trigger.onNearMisses = { misses in pipeline.nearMisses(misses) }
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
        do {
            return try wake.listener(phrase: settings.wakePhrase, profile: store.voiceProfile,
                                     voiceThreshold: settings.voiceThreshold)
        } catch {
            wakeState = "The wake phrase did not start: \(error.localizedDescription)"
            status = wakeState
            return nil
        }
    }

    /// Downloads (one time, about 18 MB) and loads the wake phrase models in the background (D-11).
    private func loadWakeModels() {
        guard wake == nil, wakeLoad == nil else { return }
        let folder = store.folder, progress = wakeProgress
        let downloaded = WakeModels.isDownloaded(store: folder)
        wakeState = downloaded ? "Loading the wake phrase models…" : "Downloading the wake phrase models (about 18 MB, one time)…"
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

    /// One line for the management window: the models and the owner's voice.
    private func voiceStatus() -> String {
        var line = wakeLoad != nil && !WakeModels.isDownloaded(store: store.folder)
            ? "Downloading the wake phrase models: \(wakeProgress.value) %." : wakeState
        if let profile = store.voiceProfile {
            let date = profile.createdAt.formatted(date: .abbreviated, time: .omitted)
            line += " Your voice: taught on \(date), \(profile.samples) phrases."
            if !profile.matches(phrase: settings.wakePhrase) {
                line += " You taught it with \"\(profile.phrase)\". Teach it again with the new phrase for the best match."
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
        let enrolment = try await Task.detached(priority: .userInitiated) { try wake.enrol(phrase: phrase, clips: clips) }.value
        try store.saveVoiceProfile(enrolment.profile)
        NSLog("earshot wake: enrolment for \"%@\": spelled phrase fired in %ld of %ld, heard forms %@", phrase,
              enrolment.spelledHits, enrolment.profile.samples, "\(enrolment.heardPieces)")
        if settings.mode == .alwaysOn { startInput() }
        return enrolment.summary
    }

    private func forgetVoice() {
        try? store.saveVoiceProfile(nil)
        if settings.mode == .alwaysOn { startInput() }
    }

    /// The management window changed the settings (it saved them already).
    private func apply(_ new: EarshotSettings) {
        // Compare with the settings that the running parts use, not with `settings`: the window changed `settings`
        // already, so a comparison with it found no change, and a new wake phrase did not reach the listener.
        let restart = SettingsRestart.needed(from: applied, to: new)
        applied = new
        if settings != new { settings = new }
        pipeline.showFeedback = new.showFeedback
        pipeline.wakePhrase = new.wakePhrase
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
