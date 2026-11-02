import AppKit

// The probe runs an AppKit run loop, because global hot keys, the
// on-screen note and app activation need one. It has no Dock icon.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let argv = Array(CommandLine.arguments.dropFirst())
Task { @MainActor in
    if let code = await Commands.run(argv) {
        exit(code)
    }
}
app.run()
