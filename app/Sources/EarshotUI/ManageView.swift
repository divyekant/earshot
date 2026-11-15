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
    /// Tells EarshotApp that the plugins or their approvals changed (R-PL-4). The Plugins tab calls it.
    public var pluginsChanged: (() -> Void)?
    /// Why the router does not use a plugin lead, or nil if it uses it (PluginRouter.refusal).
    public var leadRefusal: ((String) -> String?)?

    public init(test: ((String, Bool) async -> TestReport)? = nil,
                discoverApps: (() async -> [AppEntry])? = nil,
                refreshNames: ((String) async -> [NameEntry])? = nil,
                feedback: FeedbackSink? = nil,
                settingsChanged: ((EarshotSettings) -> Void)? = nil,
                pluginsChanged: (() -> Void)? = nil,
                leadRefusal: ((String) -> String?)? = nil,
                voice: VoiceHooks? = nil) {
        self.test = test; self.discoverApps = discoverApps; self.refreshNames = refreshNames
        self.feedback = feedback; self.settingsChanged = settingsChanged; self.voice = voice
        self.pluginsChanged = pluginsChanged; self.leadRefusal = leadRefusal
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

/// The pages of the management window (dk, 2026-11-15, prototype B). Daily use is in the menu bar panel, so the
/// window has few pages, as text links at the top.
public enum ManagePage: String, CaseIterable, Hashable, Sendable {
    case settings, activity, plugins, advanced

    public var title: String {
        switch self {
        case .settings: return "Settings"
        case .activity: return "Activity"
        case .plugins: return "Plugins"
        case .advanced: return "Advanced"
        }
    }
}

/// A link at the top of the window: the pages of a plugin, or one of the fixed pages.
enum ManageLink: Hashable {
    case plugin(PluginPages)
    case page(ManagePage)

    /// The plugin pages first, then the fixed pages.
    static func all(plugins: [PluginPages]) -> [(page: ManageLink, title: String)] {
        plugins.map { (ManageLink.plugin($0), $0.name) } + ManagePage.allCases.map { (ManageLink.page($0), $0.title) }
    }
}

/// The parts of the Advanced page: the app table, the names, the permissions and the test of a typed command.
enum AdvancedPart: String, CaseIterable, Hashable {
    case apps = "Apps", names = "Names", permissions = "Permissions", test = "Test"
}

/// The management window: white text on black, text links at the top, one page at a time.
public struct ManageView: View {
    @Binding var settings: EarshotSettings
    let store: Store
    let hooks: ManageHooks
    @State private var page: ManageLink = .page(.settings)
    @State private var plugins: [PluginPages] = []
    /// Counts the times the owner opens a plugin link, so its page view reads the file again.
    @State private var opened = 0
    @State private var part: AdvancedPart = .apps

    public init(settings: Binding<EarshotSettings>, store: Store = Store(), hooks: ManageHooks = ManageHooks()) {
        _settings = settings
        self.store = store
        self.hooks = hooks
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    EarshotMark(tile: false, glyph: Brand.ear).frame(width: 18, height: 18)
                    Text("earshot").font(.system(size: 15, weight: .bold))
                }
                Spacer()
                TopLinks(pages: ManageLink.all(plugins: plugins), selection: $page)
                Spacer()
                Text(Brand.version.map { "v\($0)" } ?? "").font(.system(size: 12)).foregroundStyle(Quiet.dim)
                    .frame(minWidth: 80, alignment: .trailing)
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 6)
            content
        }
        .background(Quiet.background)
        .foregroundStyle(Quiet.text)
        .preferredColorScheme(.dark)
        .tint(Brand.accent)
        .background(WindowReader().frame(width: 0, height: 0))
        .onAppear(perform: findPlugins)
        .onChange(of: page) { _, new in
            if case .plugin = new { opened += 1 }
            // An approval in the Plugins page can add or remove a link.
            findPlugins()
        }
        .onChange(of: settings) { _, new in
            try? store.save(new, "settings.json")
            hooks.settingsChanged?(new)
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .plugin(let p):
            PluginPageView(pages: p, reload: opened)
        case .page(let fixed):
            fixedPage(fixed)
        }
    }

    /// Reads the plugins with pages again, for example after an approval in the Plugins page.
    private func findPlugins() {
        plugins = PluginPages.find(store: store)
        if case .plugin(let p) = page, !plugins.contains(p) { page = .page(.settings) }
    }

    @ViewBuilder private func fixedPage(_ fixed: ManagePage) -> some View {
        switch fixed {
        case .settings:
            GeneralTab(settings: $settings, hooks: hooks)
        case .activity:
            ActivityTab(store: store).padding(24)
        case .plugins:
            PluginsTab(store: store, hooks: hooks)
        case .advanced:
            VStack(alignment: .leading, spacing: 12) {
                Picker("Part", selection: $part) {
                    ForEach(AdvancedPart.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
                switch part {
                case .apps: AppsTab(store: store, hooks: hooks)
                case .names: NamesTab(store: store, hooks: hooks)
                case .permissions: PermissionsTab()
                case .test: TestTab(store: store, hooks: hooks)
                }
            }
            .padding(24)
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
