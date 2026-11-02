import AppKit
import ApplicationServices
import EarshotCore
import SwiftUI

// The menu-bar helper and the management window. T6 fills the tabs; T7 connects the modules.

@main
struct EarshotApp: App {
    @State private var settings = Store().settings

    var body: some Scene {
        MenuBarExtra("earshot", systemImage: "ear") {
            Text(settings.mode == .hold ? "Hold key: on" : "Always on")
            Divider()
            OpenManageButton()
            Button("Quit earshot") { NSApplication.shared.terminate(nil) }
        }
        Window("earshot", id: "manage") {
            ManageView(settings: $settings)
                .frame(minWidth: 640, minHeight: 420)
        }
    }
}

private struct OpenManageButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Manage…") {
            NSApplication.shared.activate()
            openWindow(id: "manage")
        }
    }
}

struct ManageView: View {
    @Binding var settings: EarshotSettings

    var body: some View {
        TabView {
            GeneralTab(settings: $settings).tabItem { Text("General") }
            Placeholder(title: "Apps", text: "The app catalogue. Discovered rows to approve, edit or turn off.").tabItem { Text("Apps") }
            Placeholder(title: "Names", text: "Chats and people that earshot knows, by app.").tabItem { Text("Names") }
            ActivityTab().tabItem { Text("Activity") }
            PermissionsTab().tabItem { Text("Permissions") }
        }
        .padding()
    }
}

struct GeneralTab: View {
    @Binding var settings: EarshotSettings

    var body: some View {
        Form {
            Picker("Mode", selection: $settings.mode) {
                Text("Hold key").tag(InputMode.hold)
                Text("Always on").tag(InputMode.alwaysOn)
            }
            Picker("Speech engine", selection: $settings.engine) {
                Text("Apple").tag("apple")
                Text("Parakeet").tag("parakeet")
            }
            Picker("When the rules are unsure", selection: $settings.tier2) {
                Text("Do nothing (all on this Mac)").tag(Tier2.off)
                Text("Ask Jev").tag(Tier2.jev)
            }
            Toggle("Show the note on screen", isOn: $settings.showFeedback)
        }
        .onChange(of: settings) { _, new in try? Store().save(new, "settings.json") }
    }
}

struct ActivityTab: View {
    @State private var records: [ActivityRecord] = []

    var body: some View {
        List(records.reversed()) { r in
            HStack {
                Text(r.ok ? "✓" : "✗")
                Text(r.heard).lineLimit(1)
                Spacer()
                Text(r.intent).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .onAppear { records = ActivityLog().last(200) }
    }
}

struct PermissionsTab: View {
    var body: some View {
        Form {
            LabeledContent("Accessibility", value: AXIsProcessTrusted() ? "On" : "Off")
            Button("Open Privacy & Security settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

struct Placeholder: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title2)
            Text(text).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
