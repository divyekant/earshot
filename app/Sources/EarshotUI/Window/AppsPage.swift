import AppKit
import EarshotCore
import SwiftUI

// The apps (design canvas "Window: Apps"). earshot acts only in the apps that the owner allows (R-MT-1, R-MT-2).
// New apps wait at the top in amber. A row opens the page of one app, with its spoken names and the people and
// channels that earshot read from it. The names have no page of their own.

/// Which rows the Apps page shows.
public enum AppScope: String, CaseIterable, Identifiable, Sendable {
    case all, needsApproval, approved, chat, off
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: return "All"
        case .needsApproval: return "New"
        case .approved: return "Allowed"
        case .chat: return "With chats"
        case .off: return "Off"
        }
    }

    /// The tabs at the top of the page.
    static let tabs: [AppScope] = [.all, .needsApproval, .chat, .off]
}

/// The words of the Apps page, as pure functions for the tests.
public enum AppWords {
    /// “slack”, “slack” or “work chat”, “a”, “b” or “c”.
    public static func say(_ names: [String], limit: Int = 3) -> String {
        let quoted = names.prefix(limit).map { "“\($0)”" }
        switch quoted.count {
        case 0: return ""
        case 1: return quoted[0]
        default: return quoted.dropLast().joined(separator: ", ") + " or " + quoted.last!
        }
    }

    /// The line under the name of an app in the list.
    public static func detail(_ app: AppEntry, names: Int) -> String {
        if !app.approved {
            var parts = ["New"]
            if app.isChat { parts.append("has chats") }
            if app.electron { parts.append("reads the full screen tree") }
            if parts.count == 1 { parts.append(app.bundleID) }
            return parts.joined(separator: " · ")
        }
        if !app.enabled { return "Off · earshot does nothing in this app" }
        var parts: [String] = []
        if app.isChat {
            parts.append("Chats")
            if names > 0 { parts.append("\(names) \(names == 1 ? "person or channel" : "people and channels")") }
        }
        if !app.aliases.isEmpty { parts.append("say " + say(app.aliases)) }
        return parts.isEmpty ? app.bundleID : parts.joined(separator: " · ")
    }

    /// What the owner says for a name: its spoken names, or the name in lower case.
    public static func spoken(_ n: NameEntry) -> String {
        n.aliases.isEmpty ? say([n.name.lowercased()]) : say(n.aliases, limit: 2)
    }

    /// Where a name came from, in one short word.
    public static func source(_ s: NameSource) -> String {
        switch s {
        case .manual: return "added by you"
        case .sidebar: return "sidebar"
        case .search: return "search"
        case .contacts: return "contacts"
        }
    }

    /// The names of one app: the own chat first, then the names that the owner added, then by name.
    public static func sorted(_ names: [NameEntry], appID: String) -> [NameEntry] {
        names.filter { $0.appID == appID }.sorted { a, b in
            if a.isSelf != b.isSelf { return a.isSelf }
            if (a.source == .manual) != (b.source == .manual) { return a.source == .manual }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

struct AppsPage: View {
    let store: Store
    let hooks: ManageHooks
    @State private var apps: [AppEntry] = []
    @State private var names: [NameEntry] = []
    @State private var loaded = false
    @State private var query = ""
    @State private var scope: AppScope = .all
    @State private var openID: String?
    @State private var scanning = false
    @State private var scanStart = Date()
    @State private var lastScan = ""
    @State private var allNew = false
    /// The number of new rows that the list shows before "Show all".
    private static let newRows = 5

    var body: some View {
        Group {
            if scanning && apps.isEmpty {
                ReadingApps(start: scanStart)
            } else if let id = openID, let i = apps.firstIndex(where: { $0.id == id }) {
                AppPage(app: appBinding(i), names: namesBinding, hooks: hooks) { withAnimation(Motion.control) { openID = nil } }
                    .transition(.opacity)
            } else if loaded && apps.isEmpty {
                CenterState(glyph: .window, title: "No apps yet",
                            detail: "earshot learns each app from the names in its menus. It writes nothing and clicks nothing.") {
                    Button("Read my apps", action: discover).buttonStyle(KeyStyle(.ink)).disabled(hooks.discoverApps == nil)
                }
            } else {
                list
            }
        }
        .onAppear {
            guard !loaded else { return }
            apps = store.apps
            names = store.names
            loaded = true
        }
    }

    // MARK: Changes

    /// Each change writes the file at once. Opening the page writes nothing.
    private func setApps(_ new: [AppEntry]) {
        guard new != apps else { return }
        apps = new
        try? store.save(new, "apps.json")
    }

    private func appBinding(_ i: Int) -> Binding<AppEntry> {
        Binding(get: { apps.indices.contains(i) ? apps[i] : AppEntry(id: "", name: "", bundleID: "") },
                set: { new in
                    guard apps.indices.contains(i) else { return }
                    var all = apps
                    all[i] = new
                    setApps(all)
                })
    }

    private var namesBinding: Binding<[NameEntry]> {
        Binding(get: { names }, set: { new in
            guard new != names else { return }
            names = new
            try? store.save(new, "names.json")
        })
    }

    // MARK: List

    private var list: some View {
        let shown = CatalogueEdit.filter(apps, query: query, scope: scope)
        let waiting = shown.filter { !$0.approved }
        let allowed = shown.filter(\.approved)
        return PageFrame(top: 26) {
            HStack {
                PageTabs(selection: $scope, tabs: AppScope.tabs.map { ($0, $0.title) })
                Spacer()
                SearchField(text: $query, prompt: "Search apps", width: 200)
            }
            PageTitle(title: "Apps", sub: "earshot acts only in the apps that you allow. It learns each app from its menus.")
                .padding(.top, 22)
            if !waiting.isEmpty {
                groupHead("New, waiting for you", count: waiting.count, amber: true) {
                    if waiting.count > 1 {
                        Button("Allow all \(waiting.count)") { allow(Set(waiting.map(\.id))) }
                            .buttonStyle(KeyStyle(.ink, small: true))
                    }
                }
                ForEach(Array(waiting.prefix(allNew ? waiting.count : Self.newRows))) { app in
                    AppListRow(app: app, detail: AppWords.detail(app, names: nameCount(app)), open: { open(app) }) {
                        Button("Allow") { allow([app.id]) }.buttonStyle(KeyStyle(.line, small: true))
                    }
                }
                if waiting.count > Self.newRows && !allNew {
                    Button("Show all \(waiting.count)") { withAnimation(Motion.control) { allNew = true } }
                        .buttonStyle(QuietStyle()).padding(.top, 6)
                }
            }
            if !allowed.isEmpty || waiting.isEmpty {
                groupHead(scope == .off ? "Off" : "Allowed", count: allowed.count, amber: false) { scan }
                ForEach(allowed) { app in
                    AppListRow(app: app, detail: AppWords.detail(app, names: nameCount(app)), open: { open(app) }) {
                        Toggle("", isOn: enabled(app.id)).toggleStyle(SwitchStyle()).labelsHidden()
                            .accessibilityLabel("\(app.name) on")
                    }
                }
            }
            if shown.isEmpty {
                Text(query.isEmpty ? "No app here." : "No app matches “\(query)”.").textStyle(.body, Palette.ink3).padding(.top, 8)
            }
            if hooks.discoverApps == nil { NotConnected(what: "Discovery").padding(.top, 16) }
        }
    }

    /// "Read the apps again", the time of a read that runs, or the result of the last read.
    @ViewBuilder private var scan: some View {
        if scanning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Reading the menus · \(Int(context.date.timeIntervalSince(scanStart))) s").textStyle(.small, Palette.ink3)
            }
        } else {
            HStack(spacing: 12) {
                if !lastScan.isEmpty { Text(lastScan).textStyle(.small, Palette.ink3) }
                Button("Read the apps again", action: discover).buttonStyle(QuietStyle()).disabled(hooks.discoverApps == nil)
            }
        }
    }

    private func groupHead<T: View>(_ title: String, count: Int, amber: Bool, @ViewBuilder trailing: () -> T) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title).textStyle(TextStyle(12, 16, 600), amber ? Palette.amber : Palette.ink2)
            Text("\(count)").textStyle(.mono, Palette.ink3)
            Spacer()
            trailing()
        }
        .frame(minHeight: 28)
        .padding(.top, 24).padding(.bottom, 4)
    }

    private func nameCount(_ app: AppEntry) -> Int { names.filter { $0.appID == app.id }.count }

    private func open(_ app: AppEntry) { withAnimation(Motion.control) { openID = app.id } }

    private func allow(_ ids: Set<String>) {
        withAnimation(Motion.control) {
            setApps(CatalogueEdit.set(\.enabled, true, ids: ids, in: CatalogueEdit.set(\.approved, true, ids: ids, in: apps)))
        }
    }

    private func enabled(_ id: String) -> Binding<Bool> {
        Binding(get: { apps.first { $0.id == id }?.enabled ?? false },
                set: { on in setApps(CatalogueEdit.set(\.enabled, on, ids: [id], in: apps)) })
    }

    private func discover() {
        guard let find = hooks.discoverApps, !scanning else { return }
        scanning = true
        scanStart = Date()
        lastScan = ""
        let before = Set(apps.map(\.id))
        Task { @MainActor in
            let found = await find()
            let merged = CatalogueEdit.merge(saved: apps, discovered: found)
            let added = merged.filter { !before.contains($0.id) }.count
            let seconds = Int(Date().timeIntervalSince(scanStart).rounded())
            withAnimation(Motion.control) {
                setApps(merged)
                lastScan = added == 0 ? "No new app · \(seconds) s" : "\(added) new · \(seconds) s"
                scanning = false
            }
        }
    }
}

/// The page while earshot reads the apps for the first time.
struct ReadingApps: View {
    let start: Date
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            Text("Reading the menus of your apps").textStyle(.title, Palette.ink)
            Text("earshot reads only the menu names. It writes nothing and clicks nothing.")
                .textStyle(TextStyle(13.5, 19), Palette.ink2).multilineTextAlignment(.center)
                .frame(maxWidth: 360).padding(.top, 8)
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSince(start)
                // A bar that moves from left to right while the read runs. The read gives no count.
                let phase = (t / 1.6).truncatingRemainder(dividingBy: 1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.fill)
                        Capsule().fill(Palette.ink).frame(width: geo.size.width * 0.3)
                            .offset(x: geo.size.width * (1.3 * phase - 0.3))
                    }
                    .clipShape(Capsule())
                }
                .frame(width: 260, height: 3)
                .padding(.top, 26)
                Text("\(Int(t)) s").textStyle(.mono, Palette.ink3).padding(.top, 14)
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One app in the list: its tile, its name, one line about it, a control and a chevron. A click opens the app.
struct AppListRow<Trailing: View>: View {
    let app: AppEntry
    let detail: String
    let open: () -> Void
    let trailing: Trailing
    @State private var hover = false

    init(app: AppEntry, detail: String, open: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.app = app; self.detail = detail; self.open = open; self.trailing = trailing()
    }

    var body: some View {
        let off = app.approved && !app.enabled
        HStack(spacing: 14) {
            Tile(app.name, dim: off)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).textStyle(.body, off ? Palette.ink3 : Palette.ink).lineLimit(1)
                Text(detail).textStyle(.detail, Palette.ink3).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
            Glyph(.chevronRight, size: 14).foregroundStyle(hover ? Palette.ink2 : Palette.ink4)
        }
        .padding(.vertical, 9).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hover ? Palette.raise : .clear))
        .padding(.horizontal, -12)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.hover) { hover = h } }
        .onTapGesture(perform: open)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open \(app.name)", open)
    }
}

/// The page of one app: allowed or off, the spoken names, the people and channels, and how it opens a chat.
struct AppPage: View {
    @Binding var app: AppEntry
    @Binding var names: [NameEntry]
    let hooks: ManageHooks
    let back: () -> Void
    @State private var newAlias = ""
    @State private var newName = ""
    @State private var showAll = false
    @State private var reading = false
    @State private var readResult = ""
    /// The number of names before "Show all".
    private static let firstNames = 4

    var body: some View {
        PageFrame(top: 22) {
            Button(action: back) {
                HStack(spacing: 3) {
                    Glyph(.back, size: 13)
                    Text("Apps")
                }
            }
            .buttonStyle(QuietStyle())
            .keyboardShortcut(.escape, modifiers: [])
            header.padding(.top, 16)
            block("What you can call it", sub: "Say one of these names to open \(app.name).") { aliases }
            if app.isChat || !mine.isEmpty { peopleBlock }
            if app.isChat { block("How earshot opens a chat") { how } }
            VStack(spacing: 0) {
                SettingRow("Has chats", detail: "earshot can open a chat in \(app.name) by name.") {
                    Toggle("", isOn: $app.isChat).toggleStyle(SwitchStyle()).labelsHidden()
                }
                SettingRow("Read the full screen tree", detail: app.electron
                           ? "\(app.name) is built on Electron. earshot must ask for the full tree to see its buttons."
                           : "Turn this on if earshot cannot see the buttons of \(app.name).", last: true) {
                    Toggle("", isOn: $app.electron).toggleStyle(SwitchStyle()).labelsHidden()
                }
            }
            .padding(.top, 26)
            if app.approved {
                Rule().padding(.top, 18)
                HStack {
                    Text("earshot acts in \(app.name) because you allowed it.").textStyle(.small, Palette.ink3)
                    Spacer()
                    Button("Take back the approval") { withAnimation(Motion.control) { app.approved = false } }
                        .buttonStyle(QuietStyle(TextStyle(12.5, 17, 500)))
                }
                .padding(.top, 14)
            }
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Tile(app.name, size: 52, dim: app.approved && !app.enabled)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).textStyle(.title, Palette.ink)
                    Text(app.bundleID).textStyle(.mono, Palette.ink3).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if app.approved {
                    Segmented(selection: $app.enabled, options: [(true, "Allowed"), (false, "Off")])
                } else {
                    Button("Allow \(app.name)") {
                        withAnimation(Motion.control) { app.approved = true; app.enabled = true }
                    }
                    .buttonStyle(KeyStyle(.ink))
                }
            }
            if !app.approved {
                HStack(spacing: 8) {
                    Dot(.amber)
                    Text("New. earshot does nothing in \(app.name) until you allow it.").textStyle(.call, Palette.amber)
                }
            } else if !app.enabled {
                Text("Off. earshot does nothing in \(app.name).").textStyle(.call, Palette.ink3)
            }
        }
    }

    private func block<C: View>(_ title: String, sub: String = "", @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).textStyle(.section, Palette.ink)
            if !sub.isEmpty {
                Text(sub).textStyle(.call, Palette.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            content().padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 30)
    }

    private var aliases: some View {
        Flow(spacing: 8, lineSpacing: 8) {
            ForEach(app.aliases, id: \.self) { alias in
                RemovableChip(alias) { withAnimation(Motion.control) { app.aliases.removeAll { $0 == alias } } }
            }
            Field(text: $newAlias, prompt: "Add a name", onCommit: addAlias).frame(width: 150)
        }
    }

    private var mine: [NameEntry] { AppWords.sorted(names, appID: app.id) }

    private var peopleBlock: some View {
        let all = mine
        let shown = showAll ? all : Array(all.prefix(Self.firstNames))
        let sample = all.first { !$0.isSelf }.map { $0.aliases.first ?? $0.name.lowercased() } ?? "ravi"
        let appWord = app.aliases.first ?? app.name.lowercased()
        let sub = all.isEmpty
            ? "earshot found no names in \(app.name) yet. Read them from its sidebar, or add one."
            : "earshot read these from \(app.name). Say “message \(sample) on \(appWord)”."
        return block("People and channels", sub: sub) {
            VStack(spacing: 0) {
                ForEach(shown, id: \.self) { n in
                    NameLine(entry: n, last: n == shown.last && all.count <= shown.count,
                             own: { setSelf(n, $0) }, remove: { remove(n) })
                }
                HStack(spacing: 12) {
                    if all.count > shown.count {
                        Text("and \(all.count - shown.count) more").textStyle(.body, Palette.ink2)
                    } else if !readResult.isEmpty {
                        Text(readResult).textStyle(.small, Palette.ink3)
                    }
                    Spacer()
                    if all.count > Self.firstNames {
                        Button(showAll ? "Show fewer" : "Show all") { withAnimation(Motion.control) { showAll.toggle() } }
                            .buttonStyle(QuietStyle())
                        Text("·").textStyle(.call, Palette.ink4)
                    }
                    Button(reading ? "Reading…" : "Read again", action: readNames)
                        .buttonStyle(QuietStyle())
                        .disabled(hooks.refreshNames == nil || reading)
                }
                .padding(.top, 10)
                HStack(spacing: 10) {
                    Field(text: $newName, prompt: "Add a person or channel", onCommit: addName).frame(width: 240)
                    Spacer()
                }
                .padding(.top, 12)
            }
        }
    }

    @ViewBuilder private var how: some View {
        switch app.openChat {
        case .switcher(let keys):
            HStack(spacing: 8) {
                Text("Press").textStyle(TextStyle(13.5, 19), Palette.ink2)
                ShortcutCaps(keys)
                Text(", type the name, pick the first result.").textStyle(TextStyle(13.5, 19), Palette.ink2)
                Text("From the \(app.name) menus.").textStyle(TextStyle(13.5, 19), Palette.ink3)
            }
        case .link(let template):
            HStack(spacing: 8) {
                Text("Opens a link:").textStyle(TextStyle(13.5, 19), Palette.ink2)
                Text(template).textStyle(.mono, Palette.ink).textSelection(.enabled)
            }
        case .none:
            Text("earshot found no way to open a chat in the \(app.name) menus.").textStyle(TextStyle(13.5, 19), Palette.ink3)
        }
    }

    // MARK: Changes

    private func addAlias() {
        let new = CatalogueEdit.parseAliases(app.aliases.joined(separator: ",") + "," + newAlias)
        if new != app.aliases { withAnimation(Motion.control) { app.aliases = new } }
        newAlias = ""
    }

    private func addName() {
        names = CatalogueEdit.addManual(names, appID: app.id, name: newName)
        newName = ""
    }

    private func setSelf(_ n: NameEntry, _ on: Bool) {
        guard let i = names.firstIndex(of: n) else { return }
        names[i].isSelf = on
    }

    private func remove(_ n: NameEntry) {
        withAnimation(Motion.control) { names.removeAll { $0 == n } }
    }

    private func readNames() {
        guard let read = hooks.refreshNames else { return }
        reading = true
        readResult = ""
        let id = app.id
        Task { @MainActor in
            let found = await read(id)
            let before = names.filter { $0.appID == id }.count
            names = CatalogueEdit.replaceNames(names, appID: id, with: found)
            let after = names.filter { $0.appID == id }.count
            readResult = "\(after) names · \(after >= before ? "\(after - before) new" : "\(before - after) fewer")"
            reading = false
        }
    }
}

/// One person or channel: the name, what to say, and where earshot found it. A menu marks the own chat or removes it.
struct NameLine: View {
    let entry: NameEntry
    let last: Bool
    let own: (Bool) -> Void
    let remove: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(entry.name).textStyle(.body, Palette.ink).lineLimit(1)
            Text("say \(AppWords.spoken(entry))").textStyle(.detail, Palette.ink3).lineLimit(1)
            Spacer(minLength: 8)
            if entry.isSelf {
                Text("Your own chat").textStyle(TextStyle(11.5, 14, 600), Palette.ink)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.lineHi, lineWidth: 1))
            } else {
                Text(AppWords.source(entry.source)).textStyle(.mono, Palette.ink3)
            }
            Menu {
                Toggle("This is my own chat", isOn: Binding(get: { entry.isSelf }, set: own))
                Divider()
                Button("Remove \(entry.name)", action: remove)
            } label: {
                Glyph(.more, size: 14).foregroundStyle(Palette.ink2).frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .opacity(hover ? 1 : 0)
            .accessibilityLabel("More for \(entry.name)")
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { if !last { Rule() } }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.hover) { hover = h } }
    }
}
