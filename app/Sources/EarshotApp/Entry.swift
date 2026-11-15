import AppKit
import ApplicationServices
import EarshotCore
import EarshotUI
import Foundation

// The start of the program. A control word as the first word runs the command line (docs/CONTROL.md) and stops.
// No window opens and no module starts. Any other start opens the menu-bar app.

@main
enum Entry {
    @MainActor static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.count == 2, args[0] == "snapshot" {
            exit(SnapshotRun.run(to: URL(fileURLWithPath: args[1])))
        }
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

/// `earshot snapshot <folder>`: pictures of each screen for the design check. It copies the files that the screens
/// read to a temporary folder first, so the views change no file of the owner. It starts no module.
enum SnapshotRun {
    @MainActor static func run(to folder: URL) -> Int32 {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let real = Store().folder
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("earshot-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: temp) }
        do {
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            for name in ["settings.json", "apps.json", "names.json", "activity.jsonl", PluginContract.approvalsFile,
                         PluginContract.offFile, PluginContract.folderName] {
                let from = real.appendingPathComponent(name)
                if fm.fileExists(atPath: from.path) { try fm.copyItem(at: from, to: temp.appendingPathComponent(name)) }
            }
            // Of the data of each plugin, only its pages and its settings: the screens read nothing else.
            let data = real.appendingPathComponent("plugin-data", isDirectory: true)
            for id in (try? fm.contentsOfDirectory(atPath: data.path)) ?? [] {
                let to = temp.appendingPathComponent("plugin-data/\(id)", isDirectory: true)
                try fm.createDirectory(at: to, withIntermediateDirectories: true)
                for part in ["pages", "settings.json"] {
                    let from = data.appendingPathComponent("\(id)/\(part)")
                    if fm.fileExists(atPath: from.path) { try fm.copyItem(at: from, to: to.appendingPathComponent(part)) }
                }
            }
        } catch {
            FileHandle.standardError.write(Data("earshot snapshot: \(error.localizedDescription)\n".utf8))
            return 1
        }
        let names = UISnapshots.write(to: folder, store: Store(folder: temp))
        FileHandle.standardOutput.write(Data((names.joined(separator: "\n") + "\n").utf8))
        return names.isEmpty ? 1 : 0
    }
}
