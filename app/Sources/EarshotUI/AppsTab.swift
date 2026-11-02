import EarshotCore
import SwiftUI

/// The app catalogue. The owner approves, edits or turns off the rows that the discovery found (R-MT-1, R-MT-2).
/// Search, a filter and multi-select let the owner approve many apps in one step.
struct AppsTab: View {
    let store: Store
    let hooks: ManageHooks
    @State private var apps: [AppEntry] = []
    @State private var selection = Set<String>()
    @State private var query = ""
    @State private var scope: AppScope = .all
    @State private var busy = false
    @State private var lastScan = ""

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Search apps", text: $query).textFieldStyle(.roundedBorder)
                    Picker("Show", selection: $scope) {
                        ForEach(AppScope.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                List(selection: $selection) {
                    ForEach(shown) { app in
                        AppRow(app: app).tag(app.id)
                    }
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    BulkButtons(ids: ids, apps: $apps, selection: $selection)
                }
                HStack(spacing: 8) {
                    Button("Select all (\(shown.count))") { selection = Set(shown.map(\.id)) }
                        .disabled(shown.isEmpty)
                    Button("Select none") { selection = [] }.disabled(selection.isEmpty)
                    Spacer()
                    Text("\(apps.filter(\.approved).count) of \(apps.count) approved")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button { discover() } label: {
                        if busy {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Reading menus…") }
                        } else {
                            Label("Discover apps", systemImage: "sparkle.magnifyingglass")
                        }
                    }
                    .disabled(hooks.discoverApps == nil || busy)
                    if !lastScan.isEmpty { Text(lastScan).font(.caption).foregroundStyle(.secondary) }
                }
                if hooks.discoverApps == nil { NotConnected(what: "Discovery") }
                if apps.isEmpty && !busy {
                    Text("No apps yet. Discover apps to read the menus of your apps.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 300)
            Group {
                if selection.count == 1, let id = selection.first, let i = apps.firstIndex(where: { $0.id == id }) {
                    AppDetail(app: $apps[i]).id(apps[i].id)
                } else if selection.count > 1 {
                    VStack(spacing: 12) {
                        Text("\(selection.count) apps selected").font(.title3)
                        BulkButtons(ids: selection, apps: $apps, selection: $selection)
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Select one app to edit it, or several to approve them together.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 280)
        }
        .onAppear { apps = store.apps }
        .onChange(of: apps) { _, new in try? store.save(new, "apps.json") }
        .onChange(of: shown.map(\.id)) { _, ids in selection.formIntersection(ids) }
    }

    private var shown: [AppEntry] { CatalogueEdit.filter(apps, query: query, scope: scope) }

    private func discover() {
        guard let find = hooks.discoverApps else { return }
        busy = true
        lastScan = ""
        let before = Set(apps.map(\.id))
        let start = Date()
        Task { @MainActor in
            let found = await find()
            apps = CatalogueEdit.merge(saved: apps, discovered: found)
            let added = apps.filter { !before.contains($0.id) }.count
            let seconds = Date().timeIntervalSince(start)
            lastScan = "\(found.count) apps, \(added) new, in \(String(format: "%.1f", seconds)) s"
            if added > 0 { scope = .needsApproval }
            busy = false
        }
    }
}

/// Which rows the Apps tab shows.
public enum AppScope: String, CaseIterable, Identifiable, Sendable {
    case all, needsApproval, approved, chat, off
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: return "All apps"
        case .needsApproval: return "Not approved"
        case .approved: return "Approved"
        case .chat: return "Chat apps"
        case .off: return "Turned off"
        }
    }
}

struct AppRow: View {
    let app: AppEntry
    var body: some View {
        HStack {
            Image(systemName: app.approved ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(app.approved ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).foregroundStyle(app.enabled ? .primary : .secondary)
                Text(app.bundleID).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            if app.isChat { Tag(text: "chat") }
            if !app.enabled { Tag(text: "off") }
        }
    }
}

struct Tag: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}

/// Actions on many rows at once: approve, remove approval, turn on, turn off, remove.
struct BulkButtons: View {
    let ids: Set<String>
    @Binding var apps: [AppEntry]
    @Binding var selection: Set<String>

    var body: some View {
        Button("Approve") { apps = CatalogueEdit.set(\.approved, true, ids: ids, in: apps) }
        Button("Remove approval") { apps = CatalogueEdit.set(\.approved, false, ids: ids, in: apps) }
        Button("Turn on") { apps = CatalogueEdit.set(\.enabled, true, ids: ids, in: apps) }
        Button("Turn off") { apps = CatalogueEdit.set(\.enabled, false, ids: ids, in: apps) }
        Divider()
        Button("Remove from the list", role: .destructive) {
            apps.removeAll { ids.contains($0.id) }
            selection.subtract(ids)
        }
    }
}

struct AppDetail: View {
    @Binding var app: AppEntry
    @State private var aliasText = ""

    var body: some View {
        Form {
            LabeledContent("Name", value: app.name)
            LabeledContent("Bundle ID", value: app.bundleID)
            Toggle("Approved (earshot may act in this app)", isOn: $app.approved)
            Toggle("On", isOn: $app.enabled)
            TextField("Spoken names (comma between)", text: $aliasText)
                .onSubmit { app.aliases = CatalogueEdit.parseAliases(aliasText) }
            Text("Press Return to save the spoken names.").font(.caption).foregroundStyle(.secondary)
            Toggle("Has chats", isOn: $app.isChat)
            LabeledContent("Opens a chat with", value: CatalogueEdit.describe(app.openChat))
            Toggle("Electron app (needs the full accessibility tree)", isOn: $app.electron)
        }
        .formStyle(.grouped)
        .onAppear { aliasText = app.aliases.joined(separator: ", ") }
    }
}
