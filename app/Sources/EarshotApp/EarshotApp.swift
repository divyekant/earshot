import AppKit
import EarshotCore
import EarshotUI
import SwiftUI

// The menu-bar helper. T7 connects the modules here. The management window is in EarshotUI (T6).

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
