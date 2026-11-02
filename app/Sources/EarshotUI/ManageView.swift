import EarshotCore
import SwiftUI

// T6 owns this module: the management window and the feedback note (R-FB-1).
// The module uses EarshotCore types only. EarshotApp (T7) gives the links to the other modules as hooks.

/// The links from the management window to the other modules. EarshotApp (T7) sets them.
/// If a hook is nil, the window shows that the function is not connected.
public struct ManageHooks {
    /// Runs one typed command through the router, and optionally the actions. Used by the Test tab.
    public var test: ((String, _ runActions: Bool) async -> TestReport)?
    /// Builds catalogue rows from the running and installed apps (CatalogueBuilder).
    public var discoverApps: (() async -> [AppEntry])?
    /// Reads the names of one app again (NameFinder).
    public var refreshNames: ((_ appID: String) async -> [NameEntry])?
    /// Shows the feedback note, for the "Show a test note" button.
    public var feedback: FeedbackSink?
    /// Tells EarshotApp that the settings changed, for example to restart the input trigger.
    public var settingsChanged: ((EarshotSettings) -> Void)?
    /// The wake phrase models and the owner's voice (R-ON-3, D-11).
    public var voice: VoiceHooks?

    public init(test: ((String, Bool) async -> TestReport)? = nil,
                discoverApps: (() async -> [AppEntry])? = nil,
                refreshNames: ((String) async -> [NameEntry])? = nil,
                feedback: FeedbackSink? = nil,
                settingsChanged: ((EarshotSettings) -> Void)? = nil,
                voice: VoiceHooks? = nil) {
        self.test = test; self.discoverApps = discoverApps; self.refreshNames = refreshNames
        self.feedback = feedback; self.settingsChanged = settingsChanged; self.voice = voice
    }
}

/// The voice enrolment of always-on mode, as EarshotApp gives it to the management window (R-ON-3, D-11).
/// The audio of the phrases stays in memory. EarshotApp makes the profile from it and drops it.
public struct VoiceHooks {
    /// One line about the wake phrase models and the owner's voice.
    public var status: () async -> String
    /// Records one phrase from the microphone (16 kHz). Always-on pauses while it records.
    public var record: () async throws -> [Float]
    /// Makes and saves the voice profile from the phrases, and restarts always-on. Returns a line for the window.
    public var teach: (_ phrase: String, _ clips: [[Float]]) async throws -> String
    /// Deletes the voice profile.
    public var forget: () async -> Void

    public init(status: @escaping () async -> String, record: @escaping () async throws -> [Float],
                teach: @escaping (String, [[Float]]) async throws -> String, forget: @escaping () async -> Void) {
        self.status = status; self.record = record; self.teach = teach; self.forget = forget
    }
}

/// The result of one command in the Test tab.
public struct TestReport: Sendable {
    public var heard: String
    public var route: RouteResult
    /// Nil if the actions did not run (dry run, or confidence too low).
    public var outcome: ActionOutcome?

    public init(heard: String, route: RouteResult, outcome: ActionOutcome? = nil) {
        self.heard = heard; self.route = route; self.outcome = outcome
    }
}

/// The management window. Tabs: General, Apps, Names, Activity, Permissions, Test.
public struct ManageView: View {
    @Binding var settings: EarshotSettings
    let store: Store
    let hooks: ManageHooks

    public init(settings: Binding<EarshotSettings>, store: Store = Store(), hooks: ManageHooks = ManageHooks()) {
        _settings = settings
        self.store = store
        self.hooks = hooks
    }

    public var body: some View {
        VStack(spacing: 0) {
            BrandHeader()
            Divider()
            tabs.padding()
        }
        .tint(Brand.accent)
        .background(WindowReader().frame(width: 0, height: 0))
        .onChange(of: settings) { _, new in
            try? store.save(new, "settings.json")
            hooks.settingsChanged?(new)
        }
    }

    private var tabs: some View {
        TabView {
            GeneralTab(settings: $settings, hooks: hooks).tabItem { Text("General") }
            AppsTab(store: store, hooks: hooks).tabItem { Text("Apps") }
            NamesTab(store: store, hooks: hooks).tabItem { Text("Names") }
            ActivityTab(store: store).tabItem { Text("Activity") }
            PermissionsTab().tabItem { Text("Permissions") }
            TestTab(store: store, hooks: hooks).tabItem { Text("Test") }
        }
    }
}

/// A short line that tells the owner that a function is not connected yet.
struct NotConnected: View {
    let what: String
    var body: some View {
        Text("\(what) is not connected in this build.").font(.caption).foregroundStyle(.secondary)
    }
}
