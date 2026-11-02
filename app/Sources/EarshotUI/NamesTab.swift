import EarshotCore
import SwiftUI

/// Chats and people that earshot knows, by app. Names come from the app sidebars, the app search and Contacts.
/// The owner can add a name, mark the own chat, and remove a name. There is no hand-written list in the code (R-MT-1).
struct NamesTab: View {
    let store: Store
    let hooks: ManageHooks
    @State private var names: [NameEntry] = []
    @State private var apps: [AppEntry] = []
    @State private var appID = ""
    @State private var newName = ""
    @State private var filter = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("App", selection: $appID) {
                    ForEach(appIDs, id: \.self) { Text(appName($0)).tag($0) }
                }
                .frame(maxWidth: 260)
                TextField("Filter", text: $filter).frame(maxWidth: 200)
                Spacer()
                Button(busy ? "Reading…" : "Read names again") { refresh() }
                    .disabled(hooks.refreshNames == nil || appID.isEmpty || busy)
            }
            if hooks.refreshNames == nil { NotConnected(what: "Name discovery") }
            Table(shown) {
                TableColumn("Name") { n in Text(n.name) }
                TableColumn("Spoken names") { n in Text(n.aliases.joined(separator: ", ")).foregroundStyle(.secondary) }
                TableColumn("From") { n in Text(n.source.rawValue).foregroundStyle(.secondary) }.width(70)
                TableColumn("Own chat") { n in
                    Toggle("", isOn: selfBinding(n)).labelsHidden()
                }.width(70)
                TableColumn("") { n in
                    Button("Remove") { names.removeAll { $0 == n.entry } }.buttonStyle(.borderless)
                }.width(70)
            }
            HStack {
                TextField("Add a name", text: $newName).onSubmit(add)
                Button("Add", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || appID.isEmpty)
            }
        }
        .onAppear {
            names = store.names
            apps = store.apps
            if appID.isEmpty { appID = appIDs.first ?? "" }
        }
        .onChange(of: names) { _, new in try? store.save(new, "names.json") }
    }

    /// Apps with chats, and apps that already have names.
    private var appIDs: [String] {
        let ids = apps.filter(\.isChat).map(\.id) + names.map(\.appID)
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func appName(_ id: String) -> String { apps.first { $0.id == id }?.name ?? id }

    private var shown: [NameRow] {
        let f = SafetyPolicy.normalize(filter)
        return names.filter { $0.appID == appID }
            .filter { f.isEmpty || SafetyPolicy.normalize($0.name + " " + $0.aliases.joined(separator: " ")).contains(f) }
            .map(NameRow.init)
    }

    private func selfBinding(_ row: NameRow) -> Binding<Bool> {
        Binding(get: { row.entry.isSelf }, set: { value in
            if let i = names.firstIndex(of: row.entry) { names[i].isSelf = value }
        })
    }

    private func add() {
        names = CatalogueEdit.addManual(names, appID: appID, name: newName)
        newName = ""
    }

    private func refresh() {
        guard let read = hooks.refreshNames else { return }
        busy = true
        let id = appID
        Task { @MainActor in
            let found = await read(id)
            names = CatalogueEdit.replaceNames(names, appID: id, with: found)
            busy = false
        }
    }
}

/// A table row. NameEntry has no id, so the row uses the entry itself.
struct NameRow: Identifiable {
    var entry: NameEntry
    var id: NameEntry { entry }
    var name: String { entry.name }
    var aliases: [String] { entry.aliases }
    var source: NameSource { entry.source }
    init(_ entry: NameEntry) { self.entry = entry }
}
