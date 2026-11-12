import Foundation

// The command line of earshot (R-CT-1 to R-CT-4, docs/CONTROL.md). The same program as the app: when the first word
// is a control word, earshot runs one command and stops, and no window opens.
// This file has the parts with no AppKit: the settings edit, the words of the command line and the messages to the
// running app. The socket and the peer checks are in EarshotApp (ControlSocket.swift).

/// One request to the running app. One JSON line over the control socket.
public struct ControlRequest: Codable, Equatable, Sendable {
    /// "status", "reload", "restart-plugin" or "run".
    public var cmd: String
    /// For "run": the typed command, as the Test tab takes it.
    public var text: String?
    /// For "run": true runs the actions, as "Run actions" in the Test tab. False is a dry run.
    public var actions: Bool?
    /// For "restart-plugin": the plugin id.
    public var plugin: String?
    /// For "run": the longest wait in seconds for the answers of a plugin, after a hand-off.
    public var wait: Double?

    public init(cmd: String, text: String? = nil, actions: Bool? = nil, plugin: String? = nil, wait: Double? = nil) {
        self.cmd = cmd; self.text = text; self.actions = actions; self.plugin = plugin; self.wait = wait
    }
}

/// The answer of the running app. One JSON line.
public struct ControlReply: Codable, Equatable, Sendable {
    public var ok: Bool
    /// Lines to show, in order.
    public var lines: [String]

    public init(ok: Bool, lines: [String]) { self.ok = ok; self.lines = lines }
}

/// Reads and changes the settings in settings.json by name (R-CT-1).
public enum ControlSettings {
    /// The values of the settings that have a fixed list.
    public static let choices: [String: [String]] = [
        "mode": InputMode.allCases.map(\.rawValue),
        "engine": EngineChoice.allCases.map(\.rawValue),
        "tier2": Tier2.allCases.map(\.rawValue),
    ]

    /// The settings that send data to the cloud (R-MD-1, D-9, D-10). Only the owner turns them on. The command line
    /// turns one on only with `--owner-ok`, and only when the owner said so.
    public static let ownerOnly: Set<String> = ["tier2", "jevSeesScreen"]

    public struct Problem: Error, Equatable, CustomStringConvertible {
        public let description: String
        public init(_ text: String) { description = text }
    }

    /// Each setting name and its value as JSON text, sorted by name.
    public static func list(_ settings: EarshotSettings) -> [(key: String, value: String)] {
        let dict = (try? object(settings)) ?? [:]
        return dict.keys.sorted().map { ($0, text(dict[$0]!)) }
    }

    /// The value of one setting as JSON text.
    public static func get(_ settings: EarshotSettings, _ key: String) throws -> String {
        let dict = try object(settings)
        guard let value = dict[key] else { throw unknown(key, dict) }
        return text(value)
    }

    /// The settings with one value changed. `raw` is the value as the owner types it: true or false, a number,
    /// or words. The result is checked: a value that the settings cannot take gives a problem, never a silent default.
    public static func set(_ settings: EarshotSettings, _ key: String, _ raw: String, ownerOK: Bool) throws -> EarshotSettings {
        var dict = try object(settings)
        guard let old = dict[key] else { throw unknown(key, dict) }
        let value = try parse(raw, like: old, key: key)
        if ownerOnly.contains(key), !ownerOK, !isDefault(key, value) {
            throw Problem("\(key) sends data to the cloud. Only the owner turns it on. Add --owner-ok only if the owner said so.")
        }
        dict[key] = value
        let data = try JSONSerialization.data(withJSONObject: dict)
        let new = try JSONDecoder().decode(EarshotSettings.self, from: data)
        // The decoder keeps the old value for a value that it cannot read. So compare.
        guard let got = try object(new)[key] as? NSObject, got.isEqual(value) else {
            let allowed = choices[key].map { ". Use one of: " + $0.joined(separator: ", ") } ?? ""
            throw Problem("\(key) cannot be \(raw)\(allowed)")
        }
        return new
    }

    /// The settings with one value back to its default.
    public static func reset(_ settings: EarshotSettings, _ key: String) throws -> EarshotSettings {
        var dict = try object(settings)
        let defaults = try object(EarshotSettings())
        guard let value = defaults[key] else { throw unknown(key, dict) }
        dict[key] = value
        return try JSONDecoder().decode(EarshotSettings.self, from: JSONSerialization.data(withJSONObject: dict))
    }

    static func isDefault(_ key: String, _ value: Any) -> Bool {
        guard let def = (try? object(EarshotSettings()))?[key] as? NSObject else { return false }
        return def.isEqual(value)
    }

    static func object(_ settings: EarshotSettings) throws -> [String: Any] {
        let data = try JSONEncoder().encode(settings)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Problem("settings are not an object") }
        return dict
    }

    static func unknown(_ key: String, _ dict: [String: Any]) -> Problem {
        Problem("There is no setting \"\(key)\". The settings: " + dict.keys.sorted().joined(separator: ", "))
    }

    /// The value in the type of the old value. A JSON true or false is a boolean number in Foundation.
    static func parse(_ raw: String, like old: Any, key: String) throws -> Any {
        if let n = old as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                switch raw.lowercased() {
                case "true", "on", "yes", "1": return true
                case "false", "off", "no", "0": return false
                default: throw Problem("\(key) is true or false, not \(raw)")
                }
            }
            if let i = Int(raw) { return i }
            if let d = Double(raw) { return d }
            throw Problem("\(key) is a number, not \(raw)")
        }
        return raw
    }

    static func text(_ value: Any) -> String {
        if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
        if let s = value as? String {
            let data = (try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])) ?? Data()
            let array = String(decoding: data, as: UTF8.self)
            return String(array.dropFirst().dropLast())
        }
        return "\(value)"
    }
}

/// The words of the command line. The app entry gives the parts that need the running app or AppKit.
public struct ControlTool {
    /// The first words that start the command line. Any other start opens the app as usual. (macOS can give the app
    /// words such as "-psn_..." or "-NSDocumentRevisionsDebugMode": they start with "-", so they never match.)
    public static let words: Set<String> = ["settings", "plugins", "run", "status", "reload", "help"]

    public static func isControl(_ args: [String]) -> Bool {
        guard let first = args.first else { return false }
        return words.contains(first)
    }

    public let store: Store
    /// Sends one request to the running app. Nil if the app does not run or does not answer.
    public var send: (ControlRequest) -> ControlReply?
    /// True if the program that started this command has the Accessibility permission. "run --actions" needs it,
    /// so that the command line never gives the earshot permission to a program that does not have it (R-CT-3).
    public var callerTrusted: () -> Bool

    public init(store: Store, send: @escaping (ControlRequest) -> ControlReply?, callerTrusted: @escaping () -> Bool) {
        self.store = store; self.send = send; self.callerTrusted = callerTrusted
    }

    public struct Output: Equatable {
        public var lines: [String]
        public var code: Int32
    }

    static let notRunning = "earshot does not run, or did not answer. It reads the files at its next start."

    public static let usage = """
    Usage: earshot <command>

      settings                         List each setting and its value.
      settings get <name>              Show one setting.
      settings set <name> <value>      Change one setting. The running app uses it at once.
      settings reset <name>            Set one setting back to its default.
      plugins                          List the plugins, with approval and problems.
      plugins reload                   Read the plugins folder and the approvals again ("Read again").
      plugins restart <id>             Stop one plugin and start it again.
      run <words> [--actions] [--wait <s>]
                                       Route typed words as the Test tab does. A dry run unless --actions.
                                       --wait: the longest wait for plugin answers (default 3 s, at most 20 s).
      status                           Show the version, the mode and the running plugins.
      reload                           Make the running app read settings.json and the plugins again.

    The command line cannot approve a plugin. The owner approves each plugin in Manage > Plugins (R-PL-4).
    The cloud settings (tier2, jevSeesScreen) need --owner-ok to turn on, and only when the owner said so.
    """

    public func run(_ args: [String]) -> Output {
        var words = args
        let ownerOK = take("--owner-ok", from: &words)
        let actions = take("--actions", from: &words)
        var wait = 3.0
        if let i = words.firstIndex(of: "--wait") {
            guard i + 1 < words.count, let s = Double(words[i + 1]) else { return fail("--wait needs a number of seconds") }
            wait = min(max(s, 0), 20)
            words.removeSubrange(i...(i + 1))
        }
        guard let first = words.first else { return Output(lines: [Self.usage], code: 0) }
        let rest = Array(words.dropFirst())
        switch first {
        case "help": return Output(lines: [Self.usage], code: 0)
        case "settings": return settings(rest, ownerOK: ownerOK)
        case "plugins": return plugins(rest)
        case "run":
            guard !rest.isEmpty else { return fail("run needs the words of a command") }
            if actions, !callerTrusted() {
                return fail("run --actions needs the Accessibility permission for the program that starts it "
                            + "(for example Terminal). Without --actions, run is a dry run.")
            }
            return remote(ControlRequest(cmd: "run", text: rest.joined(separator: " "), actions: actions, wait: wait))
        case "status": return remote(ControlRequest(cmd: "status"))
        case "reload": return remote(ControlRequest(cmd: "reload"))
        default: return fail("Unknown command \"\(first)\".\n\n" + Self.usage)
        }
    }

    private func settings(_ args: [String], ownerOK: Bool) -> Output {
        let current = store.settings
        do {
            switch (args.first ?? "list", args.count) {
            case ("list", _):
                return Output(lines: ControlSettings.list(current).map { "\($0.key) = \($0.value)" }, code: 0)
            case ("get", 2):
                return Output(lines: [try ControlSettings.get(current, args[1])], code: 0)
            case ("set", 3...):
                let value = args[2...].joined(separator: " ")
                return save(try ControlSettings.set(current, args[1], value, ownerOK: ownerOK), key: args[1])
            case ("reset", 2):
                return save(try ControlSettings.reset(current, args[1]), key: args[1])
            default:
                return fail("Use: settings, settings get <name>, settings set <name> <value>, settings reset <name>")
            }
        } catch {
            return fail("\(error)")
        }
    }

    private func save(_ new: EarshotSettings, key: String) -> Output {
        do { try store.save(new, "settings.json") } catch { return fail("Could not save settings.json: \(error)") }
        let shown = (try? ControlSettings.get(new, key)) ?? "?"
        let told = send(ControlRequest(cmd: "reload"))
        return Output(lines: ["\(key) = \(shown)", told?.ok == true ? "earshot uses the change now." : Self.notRunning], code: 0)
    }

    private func plugins(_ args: [String]) -> Output {
        switch (args.first ?? "list", args.count) {
        case ("list", _):
            let found = PluginCatalog(store: store).scan()
            if found.isEmpty { return Output(lines: ["No plugins in \(PluginCatalog(store: store).folder.path)"], code: 0) }
            return Output(lines: found.map(Self.describe), code: 0)
        case ("reload", 1):
            return remote(ControlRequest(cmd: "reload"))
        case ("restart", 2):
            return remote(ControlRequest(cmd: "restart-plugin", plugin: args[1]))
        case ("approve", _), ("revoke", _):
            return fail("The command line cannot change a plugin approval. The owner does it in Manage > Plugins (R-PL-4).")
        default:
            return fail("Use: plugins, plugins reload, plugins restart <id>")
        }
    }

    static func describe(_ p: PluginEntry) -> String {
        var line = "\(p.id) \(p.manifest.version) \"\(p.manifest.name)\": " + (p.approved ? "approved" : "not approved")
        line += ", leads: " + p.manifest.leads.map { "\"\($0)\"" }.joined(separator: ", ")
        if !p.problems.isEmpty { line += ", problems: " + p.problems.joined(separator: "; ") }
        return line
    }

    private func remote(_ request: ControlRequest) -> Output {
        guard let reply = send(request) else { return fail(Self.notRunning) }
        return Output(lines: reply.lines, code: reply.ok ? 0 : 1)
    }

    private func fail(_ text: String) -> Output { Output(lines: [text], code: 1) }

    private func take(_ flag: String, from words: inout [String]) -> Bool {
        guard let i = words.firstIndex(of: flag) else { return false }
        words.remove(at: i)
        return true
    }
}
