import AppKit
import SwiftUI

/// The state of each macOS permission, with a button to ask and a button to open System Settings.
/// The tab reads the states again every 2 s, so a change in System Settings shows here.
struct PermissionsTab: View {
    @State private var states: [Permission: PermissionState] = [:]

    var body: some View {
        Form {
            ForEach(Permission.allCases) { p in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title)
                        Text(p.reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    let s = states[p] ?? .notAsked
                    Text(s.text).foregroundStyle(s == .granted ? .green : .orange)
                    if s != .granted {
                        Button("Ask") { Permissions.ask(p); read() }
                            .disabled(!Permissions.canAsk(p))
                            .help(Permissions.canAsk(p) ? "" : "This build has no usage text for this permission.")
                    }
                    Button("Open Settings") { NSWorkspace.shared.open(p.settingsURL) }
                }
            }
            Text("macOS keeps a permission only while the code signature of earshot stays the same. After a rebuild with a new signature, macOS can ask again.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                read()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func read() {
        var new: [Permission: PermissionState] = [:]
        for p in Permission.allCases { new[p] = Permissions.state(p) }
        states = new
    }
}
