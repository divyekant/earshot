import EarshotCore
import SwiftUI

/// The app catalogue. The owner approves, edits or turns off the rows that the discovery found (R-MT-1, R-MT-2).
struct AppsTab: View {
    let store: Store
    let hooks: ManageHooks
    @State private var apps: [AppEntry] = []
    @State private var selection: String?
    @State private var busy = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                List(selection: $selection) {
                    ForEach(apps) { app in
                        HStack {
                            Image(systemName: app.approved ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(app.approved ? .green : .secondary)
                            Text(app.name).foregroundStyle(app.enabled ? .primary : .secondary)
                            Spacer()
                            if app.isChat { Text("chat").font(.caption).foregroundStyle(.secondary) }
                        }
                        .tag(app.id)
                    }
                }
                HStack {
                    Button(busy ? "Discovering…" : "Discover apps") { discover() }
                        .disabled(hooks.discoverApps == nil || busy)
                    Button("Remove") { remove() }.disabled(selection == nil)
                }
                if hooks.discoverApps == nil { NotConnected(what: "Discovery") }
                if apps.isEmpty {
                    Text("No apps yet. Discover apps to read the menus of your apps.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 220)
            Group {
                if let i = apps.firstIndex(where: { $0.id == selection }) {
                    AppDetail(app: $apps[i]).id(apps[i].id)
                } else {
                    Text("Select an app.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 300)
        }
        .onAppear { apps = store.apps }
        .onChange(of: apps) { _, new in try? store.save(new, "apps.json") }
    }

    private func discover() {
        guard let find = hooks.discoverApps else { return }
        busy = true
        Task { @MainActor in
            let found = await find()
            apps = CatalogueEdit.merge(saved: apps, discovered: found)
            busy = false
        }
    }

    private func remove() {
        apps.removeAll { $0.id == selection }
        selection = nil
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
