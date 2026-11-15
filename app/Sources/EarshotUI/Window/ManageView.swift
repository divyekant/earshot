import AppKit
import EarshotCore
import SwiftUI

// T6 owns this module: the management window, the menu bar panel and the feedback note (R-FB-1).
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
    /// The state of one plugin process (PluginHost.status).
    public var pluginRun: ((String) -> PluginRun)?
    /// Stops one plugin and starts it again. Nil if it runs, else the reason (PluginHost.restart).
    public var restartPlugin: ((String) -> String?)?

    public init(test: ((String, Bool) async -> TestReport)? = nil,
                discoverApps: (() async -> [AppEntry])? = nil,
                refreshNames: ((String) async -> [NameEntry])? = nil,
                feedback: FeedbackSink? = nil,
                settingsChanged: ((EarshotSettings) -> Void)? = nil,
                pluginsChanged: (() -> Void)? = nil,
                leadRefusal: ((String) -> String?)? = nil,
                voice: VoiceHooks? = nil,
                pluginRun: ((String) -> PluginRun)? = nil,
                restartPlugin: ((String) -> String?)? = nil) {
        self.test = test; self.discoverApps = discoverApps; self.refreshNames = refreshNames
        self.feedback = feedback; self.settingsChanged = settingsChanged; self.voice = voice
        self.pluginsChanged = pluginsChanged; self.leadRefusal = leadRefusal
        self.pluginRun = pluginRun; self.restartPlugin = restartPlugin
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

/// The fixed pages of the window (dk, 2026-11-15, design canvas). Daily use is in the menu bar panel. The pages of a
/// plugin come first, then these. "Advanced" is gone: the names live in the page of each app, the permissions and the
/// typed test in System.
public enum ManagePage: String, CaseIterable, Hashable, Sendable {
    case activity, settings, apps, plugins, system

    public var title: String {
        switch self {
        case .activity: return "Activity"
        case .settings: return "Settings"
        case .apps: return "Apps"
        case .plugins: return "Plugins"
        case .system: return "System"
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

/// The management window: a top bar with the links and the state, and one page at a time.
public struct ManageView: View {
    @Binding var settings: EarshotSettings
    let store: Store
    let hooks: ManageHooks
    let live: LiveState
    @ObservedObject private var nav = WindowNav.shared
    @State private var page: ManageLink = .page(.activity)
    @State private var plugins: [PluginPages] = []
    /// Counts the times the owner opens a plugin link, so its page reads the files again.
    @State private var opened = 0
    /// The tab that a plugin page opens at, when the Plugins page asks for one.
    @State private var pluginTab: String?
    /// True if macOS turned off the microphone for earshot. The window reads it every 2 s.
    @State private var micOff = false
    @Namespace private var underline

    public init(settings: Binding<EarshotSettings>, store: Store = Store(), hooks: ManageHooks = ManageHooks(),
                live: LiveState = LiveState()) {
        _settings = settings
        self.store = store
        self.hooks = hooks
        self.live = live
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Rule()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.dark)
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowChrome().frame(width: 0, height: 0))
        .onAppear {
            findPlugins()
            if let r = nav.request { go(r) }
        }
        .onChange(of: nav.request) { _, r in if let r { go(r) } }
        .task {
            while !Task.isCancelled {
                let off = Permissions.state(.microphone) == .denied
                if off != micOff { withAnimation(Motion.control) { micOff = off } }
                try? await Task.sleep(for: .seconds(2))
            }
        }
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

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 76)
            HStack(spacing: 7) {
                Glyph(.ear, size: 16).foregroundStyle(Palette.ink)
                Text("earshot").textStyle(TextStyle(15, 20, 700, tracking: -0.02), Palette.ink)
            }
            .frame(width: 150, alignment: .leading)
            .allowsHitTesting(false)
            Spacer(minLength: 12)
            links
            Spacer(minLength: 12)
            let chip = live.chip
            StateChip(dot: chip.dot, state: chip.state, rest: chip.rest, key: chip.key)
                .frame(width: 226, alignment: .trailing)
                .help(live.header.title)
        }
        .padding(.trailing, 18)
        .frame(height: WindowChrome.barHeight)
        .background(WindowDragArea())
    }

    private var links: some View {
        HStack(spacing: 26) {
            ForEach(ManageLink.all(plugins: plugins), id: \.page) { item in
                let on = item.page == page
                Button { withAnimation(Motion.control) { pluginTab = nil; page = item.page } } label: {
                    Text(item.title)
                        .textStyle(TextStyle(13.5, 18, on ? 600 : 500), on ? Palette.ink : Palette.ink2)
                        .fixedSize()
                        .frame(height: WindowChrome.barHeight)
                        .overlay(alignment: .bottom) {
                            if on {
                                Capsule().fill(Palette.ink).frame(height: 1.5)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                                    .padding(.bottom, 12)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    // MARK: Pages

    @ViewBuilder private var content: some View {
        switch page {
        case .plugin(let p):
            BoardPage(pages: p, reload: opened, start: pluginTab)
        case .page(.activity):
            if micOff {
                CenterState(glyph: .micOff, tone: .amber, title: "earshot cannot hear you",
                            detail: "macOS turned off the microphone for earshot. Turn it on in Privacy settings, then come back. "
                            + "earshot sees the change at once.") {
                    Button("Open Privacy settings") { NSWorkspace.shared.open(Permission.microphone.settingsURL) }
                        .buttonStyle(KeyStyle(.ink))
                }
            } else {
                ActivityPage(store: store, wakePhrase: settings.wakePhrase, holdKey: HoldKeys.capText(of: settings),
                             alwaysOn: settings.mode == .alwaysOn)
            }
        case .page(.settings):
            SettingsPage(settings: $settings, hooks: hooks)
        case .page(.apps):
            AppsPage(store: store, hooks: hooks)
        case .page(.plugins):
            PluginsPage(store: store, hooks: hooks, open: { id, tab in
                findPlugins()
                guard let p = plugins.first(where: { $0.id == id }) else { return }
                pluginTab = tab
                withAnimation(Motion.control) { page = .plugin(p) }
            })
        case .page(.system):
            SystemPage(store: store, hooks: hooks, speech: settings.engine)
        }
    }

    private func go(_ request: WindowPage) {
        findPlugins()
        switch request {
        case .plugin(let id):
            pluginTab = nil
            if let p = plugins.first(where: { $0.id == id }) { page = .plugin(p) } else { page = .page(.plugins) }
        case .activity: page = .page(.activity)
        case .settings: page = .page(.settings)
        case .apps: page = .page(.apps)
        case .plugins: page = .page(.plugins)
        case .system: page = .page(.system)
        }
        opened += 1
        nav.request = nil
    }

    /// Reads the plugins with pages again, for example after an approval in the Plugins page.
    private func findPlugins() {
        plugins = PluginPages.find(store: store)
        if case .plugin(let p) = page, !plugins.contains(p) { page = .page(.activity) }
    }
}

/// The frame of a window page: 720 pt wide in the middle, and a scroll view.
struct PageFrame<Content: View>: View {
    var top: CGFloat = 30
    var width: CGFloat = 720
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: width, alignment: .leading)
                .padding(.top, top).padding(.bottom, 40).padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
    }
}

/// The title of a page, with one optional line under it.
struct PageTitle: View {
    let title: String
    var sub: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).textStyle(.display, Palette.ink)
            if let sub { Text(sub).textStyle(TextStyle(14, 20), Palette.ink2).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small tabs on a page: the selected tab sits on a raised chip.
struct PageTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let tabs: [(value: Value, title: String)]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.value) { tab in
                let on = tab.value == selection
                Text(tab.title)
                    .textStyle(TextStyle(13, 18, 500), on ? Palette.ink : Palette.ink2)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Palette.raise : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? Palette.rule : .clear, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(Motion.control) { selection = tab.value } }
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// A short line that tells the owner that a function is not connected yet.
struct NotConnected: View {
    let what: String
    var body: some View {
        Text("\(what) is not connected in this build.").textStyle(.small, Palette.ink3)
    }
}
