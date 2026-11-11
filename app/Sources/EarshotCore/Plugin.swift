import CryptoKit
import Foundation

// The plugin contract, version 1 (R-PL-1 to R-PL-5, docs/PLUGINS.md). Experimental until a second plugin exists.
// A plugin is a separate local program. earshot gives it text and gets back data: answers and targets.
// No plugin code runs inside earshot, and a plugin answer is never a command.

/// The contract version that this earshot speaks.
public enum PluginContract {
    public static let version = 1
    /// The folder of the plugins in the store folder: plugins/<id>/plugin.json.
    public static let folderName = "plugins"
    public static let manifestName = "plugin.json"
    /// The owner's approvals: plugin id to the SHA-256 of the approved manifest.
    public static let approvalsFile = "plugins-approved.json"
    /// The context keys that a manifest can ask for. Nothing else goes to a plugin.
    public static let contextKeys: Set<String> = ["app", "windowTitle", "url"]
    /// The most lead words in one lead.
    public static let maxLeadWords = 5
    /// The longest text of one answer on screen, in characters.
    public static let maxAnswerCharacters = 500
    /// The most items of a list answer on screen.
    public static let maxListItems = 10
    /// The longest line that earshot reads from a plugin, in bytes. A longer line is dropped.
    public static let maxLineBytes = 65_536
}

/// The plugin.json file of one plugin.
public struct PluginManifest: Codable, Hashable, Sendable {
    /// The contract version that the plugin speaks. earshot loads only `PluginContract.version`.
    public var contract: Int
    /// A short id: lower-case letters, digits and "-". The same as the folder name.
    public var id: String
    public var name: String
    public var version: String
    /// The words that start a command for this plugin, for example "remind me to".
    public var leads: [String]
    /// The context that the plugin wants with each command: "app", "windowTitle", "url".
    public var context: [String]
    /// The program and its arguments. A relative path starts at the plugin folder.
    public var run: [String]
    /// The network hosts that the plugin says it uses. Empty means none. The Plugins tab shows it for the approval.
    /// It is a statement of the plugin: earshot does not enforce it.
    public var network: [String]

    public init(contract: Int = PluginContract.version, id: String, name: String, version: String = "0.1.0",
                leads: [String], context: [String] = [], run: [String], network: [String] = []) {
        self.contract = contract; self.id = id; self.name = name; self.version = version
        self.leads = leads; self.context = context; self.run = run; self.network = network
    }

    /// Reads each field if it is in the file. A missing optional field gets its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contract = try c.decode(Int.self, forKey: .contract)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        leads = try c.decode([String].self, forKey: .leads)
        context = try c.decodeIfPresent([String].self, forKey: .context) ?? []
        run = try c.decode([String].self, forKey: .run)
        network = try c.decodeIfPresent([String].self, forKey: .network) ?? []
    }

    /// The problems that stop earshot from loading the manifest. Empty if the manifest is good.
    /// The lead words get a separate check against the core commands (PluginRouter.refusal).
    public var problems: [String] {
        var out: [String] = []
        if contract != PluginContract.version { out.append("contract \(contract) is not \(PluginContract.version)") }
        if id.isEmpty || !id.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0) }) {
            out.append("the id must use only a-z, 0-9 and \"-\"")
        }
        if leads.isEmpty { out.append("no lead words") }
        if run.first?.isEmpty ?? true { out.append("no program to run") }
        let unknown = context.filter { !PluginContract.contextKeys.contains($0) }
        if !unknown.isEmpty { out.append("unknown context: " + unknown.joined(separator: ", ")) }
        return out
    }
}

/// One plugin that earshot found on disk, with its approval state.
public struct PluginEntry: Hashable, Sendable, Identifiable {
    public var id: String { manifest.id }
    public var manifest: PluginManifest
    public var folder: URL
    /// The SHA-256 of the manifest file, as hex.
    public var hash: String
    /// True if the owner approved this manifest, with this hash (R-PL-4).
    public var approved: Bool
    /// The problems of the manifest. A plugin with a problem does not start.
    public var problems: [String]

    public init(manifest: PluginManifest, folder: URL, hash: String, approved: Bool, problems: [String]) {
        self.manifest = manifest; self.folder = folder; self.hash = hash; self.approved = approved; self.problems = problems
    }
}

/// One lead of one approved plugin, as the router sees it.
public struct PluginLead: Hashable, Sendable {
    public var pluginID: String
    public var lead: String

    public init(pluginID: String, lead: String) { self.pluginID = pluginID; self.lead = lead }
}

/// Finds the plugins in the store folder and keeps the owner's approvals.
public struct PluginCatalog: Sendable {
    public let store: Store

    public init(store: Store) { self.store = store }

    public var folder: URL { store.folder.appendingPathComponent(PluginContract.folderName, isDirectory: true) }

    /// The plugin id to the approved manifest hash.
    public var approvals: [String: String] { store.load([String: String].self, PluginContract.approvalsFile) ?? [:] }

    /// The plugins in plugins/<id>/plugin.json, sorted by id. A folder with no readable manifest is left out.
    public func scan() -> [PluginEntry] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        let approved = approvals
        var out: [PluginEntry] = []
        for dir in dirs where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(PluginContract.manifestName)) else { continue }
            let hash = Self.hash(data)
            guard let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
                let stub = PluginManifest(contract: 0, id: dir.lastPathComponent, name: dir.lastPathComponent, leads: [], run: [])
                out.append(PluginEntry(manifest: stub, folder: dir, hash: hash, approved: false, problems: ["plugin.json is not valid"]))
                continue
            }
            var problems = manifest.problems
            if manifest.id != dir.lastPathComponent { problems.append("the id is not the folder name") }
            out.append(PluginEntry(manifest: manifest, folder: dir, hash: hash, approved: approved[manifest.id] == hash,
                                   problems: problems))
        }
        return out.sorted { $0.id < $1.id }
    }

    /// Approves or removes the approval of one plugin, with the hash of its manifest now.
    public func setApproved(_ entry: PluginEntry, _ on: Bool) throws {
        var all = approvals
        all[entry.id] = on ? entry.hash : nil
        try store.save(all, PluginContract.approvalsFile)
    }

    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Messages (JSON lines)

/// One message from earshot to a plugin.
public struct PluginRequest: Codable, Equatable, Sendable {
    public var type: String
    public var contract: Int?
    public var id: String?
    public var lead: String?
    public var text: String?
    public var context: [String: String]?

    public static func hello() -> PluginRequest {
        PluginRequest(type: "hello", contract: PluginContract.version, id: nil, lead: nil, text: nil, context: nil)
    }

    public static func command(id: String, lead: String, text: String, context: [String: String]) -> PluginRequest {
        PluginRequest(type: "command", contract: nil, id: id, lead: lead, text: text, context: context)
    }
}

/// One target that a plugin gives: a to-do, a project or a document (contract part 3).
public struct PluginTarget: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var kind: String?
    /// What "open" does with the target: a file path or an http or https address. Nil if the target does not open.
    /// earshot opens it with the core verb "open". The plugin runs no action (R-PL-3).
    public var open: String?

    public init(id: String, name: String, kind: String? = nil, open: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.open = open
    }
}

/// One message from a plugin to earshot. Unknown types are dropped.
public struct PluginMessage: Codable, Equatable, Sendable {
    public var type: String
    /// The id of the command that this answer is for. Nil for an alert at a time that the plugin chose.
    public var re: String?
    /// "note", "list" or "alert".
    public var kind: String?
    public var text: String?
    public var items: [String]?
    public var targets: [PluginTarget]?

    public init(type: String, re: String? = nil, kind: String? = nil, text: String? = nil, items: [String]? = nil,
                targets: [PluginTarget]? = nil) {
        self.type = type; self.re = re; self.kind = kind; self.text = text; self.items = items; self.targets = targets
    }

    /// The text that earshot shows for an answer, cut to the limits. Nil if the message is not an answer
    /// or has nothing to show. It is only text: earshot never runs it as a command (R-PL-3).
    public var shownText: String? {
        guard type == "answer" else { return nil }
        var lines: [String] = []
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append(text) }
        if let items {
            for (i, item) in items.prefix(PluginContract.maxListItems).enumerated() { lines.append("\(i + 1). \(item)") }
            if items.count > PluginContract.maxListItems { lines.append("… \(items.count - PluginContract.maxListItems) more") }
        }
        guard !lines.isEmpty else { return nil }
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard joined.count > PluginContract.maxAnswerCharacters else { return joined }
        return String(joined.prefix(PluginContract.maxAnswerCharacters - 1)) + "…"
    }

    public var isAlert: Bool { type == "answer" && kind == "alert" }

    /// Reads one line. Nil if the line is too long or is not a message.
    public static func parse(_ line: Data) -> PluginMessage? {
        guard !line.isEmpty, line.count <= PluginContract.maxLineBytes else { return nil }
        return try? JSONDecoder().decode(PluginMessage.self, from: line)
    }
}
