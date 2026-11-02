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
            NSApplication.shared.activate()
            openWindow(id: "manage")
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

    init() {
        let store = self.store
        let settings = store.settings
        self.settings = settings
        names = NameIndex(apps: { store.apps }, store: store)
        runner = EarshotActionRunner(options: ActionOptions(settings: settings), store: store)
        let (engine, why) = SpeechEngines.make(settings)
        engineWhy = why
        let names = self.names
        pipeline = CommandPipeline(engine: engine, router: Self.router(settings), actions: runner, names: names,
                                   apps: { store.apps }, allNames: { await names.all() },
                                   frontBundleID: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier })
        pipeline.feedback = feedback
        pipeline.log = ActivityLog(store: store)
        pipeline.showFeedback = settings.showFeedback
        prepareEngine()
        startInput()
    }

    var hooks: ManageHooks {
        let pipeline = self.pipeline, catalogue = self.catalogue, store = self.store, names = self.names
        return ManageHooks(
            test: { text, run in await pipeline.test(text, runActions: run) },
            discoverApps: { (try? await catalogue.refresh(store: store)) ?? [] },
            refreshNames: { appID in await names.refresh(appIDs: [appID]) },
            feedback: feedback,
            settingsChanged: { [weak self] new in self?.apply(new) })
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
        let pipeline = self.pipeline
        input.onStart = { [weak self] in
            if let problem = pipeline.begin() { self?.feedback.show(problem, ok: false) }
        }
        input.onCancel = { _ in Task { await pipeline.cancel() } }
        input.onStop = { [weak input] in
            let mode = input?.current ?? .hold
            Task { await pipeline.finish(mode: mode) }
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
        if new.tier2 != old.tier2 || new.tier2BudgetMs != old.tier2BudgetMs { pipeline.router = Self.router(new) }
        if new.engine != old.engine || new.parakeetModelPath != old.parakeetModelPath || new.locale != old.locale {
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
