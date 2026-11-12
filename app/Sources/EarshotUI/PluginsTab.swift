import AppKit
import EarshotCore
import SwiftUI

/// The plugins that earshot found in the plugins folder, and the owner's approvals (R-PL-4, docs/PLUGINS.md).
/// A plugin is a separate program. earshot starts only an approved plugin, and gives it only the words after its
/// lead words. A changed plugin.json needs a new approval.
struct PluginsTab: View {
    let store: Store
    let hooks: ManageHooks
    @State private var plugins: [PluginEntry] = []
    @State private var error = ""

    private var catalog: PluginCatalog { PluginCatalog(store: store) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A plugin is a separate program on this Mac. earshot gives it only the words after its lead words, "
                 + "never audio. A plugin answer is a note on screen, never a command. Experimental (contract \(PluginContract.version)).")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Open the plugins folder") { openFolder() }
                Button("Read again") { reload() }
                Spacer()
            }
            if plugins.isEmpty {
                Text("No plugins. Put each plugin in its own folder, with a plugin.json file, in the plugins folder.")
                    .foregroundStyle(.secondary)
            }
            List(plugins) { p in row(p) }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
        }
        .padding()
        .onAppear(perform: reload)
    }

    @ViewBuilder private func row(_ p: PluginEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(p.manifest.name).font(.headline)
                Text("\(p.id) \(p.manifest.version)").foregroundStyle(.secondary)
                Spacer()
                Toggle("Approved", isOn: approval(p)).disabled(!p.problems.isEmpty)
            }
            ForEach(p.manifest.leads, id: \.self) { lead in
                if let why = refusal(lead) {
                    Text("“\(lead)”: not used, \(why)").foregroundStyle(.orange)
                } else {
                    Text("“\(lead)” …")
                }
            }
            Text("Network: " + (p.manifest.network.isEmpty ? "none" : p.manifest.network.joined(separator: ", "))
                 + " (the plugin says so; earshot does not check it)").foregroundStyle(.secondary)
            if !p.manifest.context.isEmpty {
                Text("Gets: the words after the lead, and " + p.manifest.context.map(PluginContract.contextText).joined(separator: ", "))
                    .foregroundStyle(p.manifest.context.contains("selection") ? .orange : .secondary)
            }
            ForEach(p.problems, id: \.self) { Text("Problem: \($0)").foregroundStyle(.red) }
        }
        .padding(.vertical, 4)
    }

    /// The router refuses a lead that starts with a core command word or an app name (R-PL-4).
    private func refusal(_ lead: String) -> String? { hooks.leadRefusal?(lead) }

    private func approval(_ p: PluginEntry) -> Binding<Bool> {
        Binding(get: { p.approved }, set: { on in
            do {
                try catalog.setApproved(p, on)
                error = ""
            } catch {
                self.error = "Could not save the approval: \(error.localizedDescription)"
            }
            reload()
            hooks.pluginsChanged?()
        })
    }

    private func reload() {
        plugins = catalog.scan()
    }

    private func openFolder() {
        try? FileManager.default.createDirectory(at: catalog.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(catalog.folder)
    }
}
