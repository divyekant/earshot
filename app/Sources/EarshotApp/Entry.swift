import ApplicationServices
import EarshotCore
import Foundation

// The start of the program. A control word as the first word runs the command line (docs/CONTROL.md) and stops.
// No window opens and no module starts. Any other start opens the menu-bar app.

@main
enum Entry {
    @MainActor static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard ControlTool.isControl(args) else {
            EarshotApp.main()
            return
        }
        let store = Store()
        let path = ControlServer.path(store)
        let tool = ControlTool(store: store, send: { request in
            // A run waits for the actions and for the plugin answers. Other requests answer at once.
            ControlServer.send(request, path: path, timeout: Int(request.wait ?? 0) + 15)
        }, callerTrusted: { AXIsProcessTrusted() })
        let output = tool.run(args)
        let text = output.lines.joined(separator: "\n") + "\n"
        if output.code == 0 {
            FileHandle.standardOutput.write(Data(text.utf8))
        } else {
            FileHandle.standardError.write(Data(text.utf8))
        }
        exit(output.code)
    }
}
