import AppKit
import EarshotActions
import EarshotCore
import EarshotDiscovery
import EarshotInput
import EarshotRouter
import EarshotSpeech
import EarshotUI
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
        let menuIndex = MenuIndex()
        let menus = MenuCache(read: { await menuIndex.refresh(bundleID: $0) })
        self.menus = menus
        pipeline.menus = { menus.cached($0) }
        menuObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { note in
            if let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier {
                menus.refresh(id)
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier { menus.refresh(front) }
        applyJev()
        keyObserver = NotificationCenter.default.addObserver(forName: KeychainSecret.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyJev() }
        }
        pipeline.feedback = feedback
        pipeline.log = ActivityLog(store: store)
        pipeline.showFeedback = settings.showFeedback
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
            settingsChanged: { [weak self] new in self?.apply(new) })
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

    private func startInput() {
        input?.stop()
        let input = InputTriggers.make(settings)
        let pipeline = self.pipeline, menus = self.menus
        input.onStart = { [weak self] in
            if let problem = pipeline.begin() { self?.feedback.show(problem, ok: false) }
        }
        input.onCancel = { _ in Task { await pipeline.cancel() } }
        input.onStop = { [weak input] in
            let mode = input?.current ?? .hold
            Task {
                await pipeline.finish(mode: mode)
                // A command can change which items are enabled ("Copy" after "select all"). Read again for the next one.
                if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier { menus.refresh(front) }
            }
        }
        pipeline.pauseAlwaysOn = { [weak input] paused in
            DispatchQueue.main.async { (input?.alwaysOn as? AlwaysOnTrigger)?.setPaused(paused) }
        }
        do {
            try input.start()
        } catch {
            status = "Input did not start: \(error)"
        }
        self.input = input
    }

    /// The management window changed the settings (it saved them already).
    private func apply(_ new: EarshotSettings) {
        let old = settings
        settings = new
        pipeline.showFeedback = new.showFeedback
        runner.options = ActionOptions(settings: new)
        if new.tier2 != old.tier2 || new.tier2BudgetMs != old.tier2BudgetMs || new.jevSeesScreen != old.jevSeesScreen
            || new.jevScreenBudgetMs != old.jevScreenBudgetMs { applyJev() }
        if new.engine != old.engine || new.parakeetModelPath != old.parakeetModelPath || new.locale != old.locale {
            // Close the microphone of the old engine first. The old engine then has no owner, so its deinit frees
            // the Parakeet model, and two models do not stay loaded.
            Self.shutdown(pipeline.engine)
            let (engine, why) = SpeechEngines.make(new)
            engineWhy = why
            pipeline.engine = engine
            prepareEngine()
        }
        if new.mode != old.mode || new.holdKeyCode != old.holdKeyCode || new.holdKeyIsModifierOnly != old.holdKeyIsModifierOnly
            || new.holdKeyModifiers != old.holdKeyModifiers {
            startInput()
        }
    }

    /// Stops an engine: the microphone closes and the timers stop (T1).
    static func shutdown(_ engine: SpeechEngine) {
        let active = (engine as? FallbackSpeechEngine)?.active ?? engine
        (active as? AutoSpeechEngine)?.shutdown()
        (active as? AppleSpeechEngine)?.shutdown()
        (active as? ParakeetEngine)?.shutdown()
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
