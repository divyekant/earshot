import EarshotCore
import SwiftUI

/// The settings of a plugin as a form: one line and one choice for each setting (docs/PLUGINS.md 3.2).
/// earshot writes each change to the settings file of the plugin at once. The plugin reads the file again.
struct PluginSettingsForm: View {
    let pages: PluginPages
    @State private var values: [String: String] = [:]
    @State private var error = ""

    private var file: PluginSettingsFile { PluginSettingsFile(url: pages.settingsFile) }

    /// The settings in their groups, in the order of plugin.json.
    private var groups: [(name: String, items: [PluginSetting])] {
        var out: [(String, [PluginSetting])] = []
        for s in pages.settings {
            let g = s.group ?? ""
            if let i = out.firstIndex(where: { $0.0 == g }) { out[i].1.append(s) } else { out.append((g, [s])) }
        }
        return out
    }

    var body: some View {
        Form {
            ForEach(groups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.items) { s in
                        Picker(s.label, selection: binding(s)) {
                            ForEach(s.choices, id: \.self) { Text(Self.title($0)).tag($0) }
                        }
                    }
                }
            }
            if !error.isEmpty { Text(error).foregroundStyle(Quiet.late) }
            Text("\(pages.name) reads these values from its settings file. A change works at once.")
                .font(.caption).foregroundStyle(Quiet.dim)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Quiet.background)
        .onAppear(perform: load)
    }

    /// "alert" shows as "Alert".
    static func title(_ choice: String) -> String {
        guard let f = choice.first else { return choice }
        return f.uppercased() + choice.dropFirst()
    }

    private func load() {
        var v: [String: String] = [:]
        for s in pages.settings { v[s.key] = file.value(s) }
        values = v
    }

    private func binding(_ s: PluginSetting) -> Binding<String> {
        Binding(get: { values[s.key] ?? s.default }, set: { new in
            do {
                try file.set(s, to: new)
                values[s.key] = new
                error = ""
            } catch {
                self.error = "Could not save \"\(s.label)\": \(error.localizedDescription)"
            }
        })
    }
}
