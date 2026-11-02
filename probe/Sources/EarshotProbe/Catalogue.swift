import AppKit

// E1, question 1: the app catalogue. The probe builds it from the menu bar of each
// app that runs. Nobody writes a row by hand (R-MT-1, R-MT-2).

/// The menu item that opens a chat, and the rule that found it.
struct MenuGuess: Codable {
    let keys: String
    let menuPath: String
    /// "switch", "new message" or "search".
    let rule: String

    enum CodingKeys: String, CodingKey {
        case keys, rule
        case menuPath = "menu_path"
    }
}

/// One app in the generated catalogue.
struct CatalogueApp: Codable {
    let id: String
    let name: String
    let bundleID: String
    let aliases: [String]
    let electron: Bool
    let openChat: MenuGuess?
    /// True if the app has a menu item that switches to a chat or starts a new message.
    let chat: Bool
    let shortcuts: Int
    let readMs: Double

    enum CodingKeys: String, CodingKey {
        case id, name, aliases, electron, chat, shortcuts
        case bundleID = "bundle_id"
        case openChat = "open_chat"
        case readMs = "read_ms"
    }

    /// The same app as an E0 app row, so that the E0 pipeline can open a chat with it.
    /// Every generated row picks the top result with Return. The pipeline guards each Return.
    func appRow() -> AppRow? {
        guard chat, let guess = openChat else { return nil }
        return AppRow(id: id, name: name, say: nil, bundleID: bundleID, aliases: aliases, electron: electron,
                      openChat: OpenChat(kind: "switcher", template: nil, handle: nil, keys: guess.keys,
                                         pick: ["return"], settleMs: 250),
                      typeIntoPrefilled: nil, benchRuns: nil, scriptLines: nil, enabled: nil)
    }
}

/// An installed app that the owner can ask to open.
struct InstalledApp: Codable {
    let id: String
    let name: String
    let aliases: [String]
}

struct CatalogueFile: Codable {
    let builtAt: String
    let apps: [CatalogueApp]
    let installed: [InstalledApp]
    /// Bundle ids that the probe left out, for example by the owner's choice.
    let skipped: [String]

    enum CodingKeys: String, CodingKey {
        case apps, installed, skipped
        case builtAt = "built_at"
    }
}

@MainActor
enum Catalogue {
    static var url: URL { Paths.logs.appendingPathComponent("catalogue.json") }

    /// WhatsApp stays out, by the owner's choice in E0 (section 5.4 of E0-viability.md).
    static let defaultSkip = ["net.whatsapp.WhatsApp"]

    /// Menu title words, in order of preference. The first rule that matches wins.
    static let rules: [(rule: String, words: [String])] = [
        ("switch", ["jump to", "switch to", "quick switcher", "go to conversation", "go to chat", "go to channel",
                    "find conversation"]),
        ("new message", ["new message", "new chat", "new conversation", "new direct message"]),
        ("search", ["search", "find"]),
    ]

    /// A title with one of these words is not a way to open a chat.
    static let excluded = ["next", "previous", "selection", "replace", "spelling", "google", "page", "tab", "tabs",
                           "mailbox", "web", "workspace", "window", "quit", "force"]

    /// Finds the best menu item that opens a chat. It matches whole words only:
    /// "find" must not match "Finder". It skips the Apple menu.
    static func guess(_ shortcuts: [AX.MenuShortcut]) -> MenuGuess? {
        for (rule, words) in rules {
            for s in shortcuts {
                let parts = s.path.components(separatedBy: " > ")
                if parts.first == "Apple" { continue }
                // Test the item title only, not the menu path: "Edit > Find > Find..." has the title "Find...".
                let title = " \(Text.normalize(parts.last ?? s.path)) "
                guard words.contains(where: { title.contains(" \($0) ") }) else { continue }
                guard !excluded.contains(where: { title.contains(" \($0) ") }) else { continue }
                // Keys that the probe cannot press, or Return, never open a chat.
                guard !s.keys.contains("key code"), !s.keys.contains("return"), !s.keys.contains("enter") else { continue }
                return MenuGuess(keys: s.keys, menuPath: s.path, rule: rule)
            }
        }
        return nil
    }

    /// Spoken names for an app: the name, and the last word of a name with two or more words
    /// ("Google Chrome" gives "chrome"). No app name is written by hand.
    static func aliases(for name: String, extra: [String] = []) -> [String] {
        var out: [String] = []
        func add(_ s: String) {
            let n = Text.normalize(s)
            if !n.isEmpty, !out.contains(n) { out.append(n) }
        }
        add(name)
        extra.forEach(add)
        // The last word of a long name, if it is not a common command word: "Sublime Text" must not give "text".
        let words = Text.normalize(name).split(separator: " ")
        if words.count >= 2, let last = words.last.map(String.init), last.count >= 4,
           !E1Router.stopWords.contains(last), !E1Router.textLeads.contains(last) {
            add(last)
        }
        return out
    }

    static func isElectron(_ url: URL?) -> Bool {
        guard let url else { return false }
        let framework = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: framework.path)
    }

    /// Reads the menu bar of each regular app that runs. It reads only: it opens no menu and presses nothing.
    static func build(skip: [String]) async -> CatalogueFile {
        var apps: [CatalogueApp] = []
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for app in running {
            guard let bundleID = app.bundleIdentifier, !skip.contains(bundleID) else { continue }
            let name = app.localizedName ?? bundleID
            let t0 = Clock.nowNs()
            let el = AX.appElement(app.processIdentifier)
            let electron = isElectron(app.bundleURL)
            if electron { AX.set(el, "AXManualAccessibility", kCFBooleanTrue) }
            let shortcuts = AX.menuShortcuts(el)
            let found = guess(shortcuts)
            let chat = found.map { $0.rule == "switch" || $0.rule == "new message" } ?? false
            var extra: [String] = []
            if let info = app.bundleURL.flatMap({ Bundle(url: $0)?.infoDictionary }) {
                for key in ["CFBundleDisplayName", "CFBundleName"] {
                    if let s = info[key] as? String { extra.append(s) }
                }
            }
            apps.append(CatalogueApp(id: Text.key(name), name: name, bundleID: bundleID,
                                     aliases: aliases(for: name, extra: extra), electron: electron,
                                     openChat: found, chat: chat, shortcuts: shortcuts.count,
                                     readMs: (Clock.ms(since: t0) * 10).rounded() / 10))
        }
        apps.sort { $0.name.lowercased() < $1.name.lowercased() }
        let ids = Set(apps.map(\.id))
        let installed = installedApps().filter { !ids.contains($0.id) }
        return CatalogueFile(builtAt: ISO8601DateFormatter().string(from: Date()), apps: apps,
                             installed: installed, skipped: skip)
    }

    /// The names of the apps in the standard app folders. It reads folder names only.
    static func installedApps() -> [InstalledApp] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                       "/System/Applications/Utilities", "\(home)/Applications"]
        var out: [InstalledApp] = []
        var seen = Set<String>()
        for folder in folders {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            for item in items where item.hasSuffix(".app") {
                let name = String(item.dropLast(4))
                let id = Text.key(name)
                guard !id.isEmpty, seen.insert(id).inserted else { continue }
                out.append(InstalledApp(id: id, name: name, aliases: aliases(for: name)))
            }
        }
        return out.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    static func save(_ file: CatalogueFile) throws {
        try FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url)
    }

    static func load() throws -> CatalogueFile {
        guard let data = try? Data(contentsOf: url) else {
            throw ProbeError("probe/logs/catalogue.json does not exist. Run: swift run earshot-probe catalogue")
        }
        return try JSONDecoder().decode(CatalogueFile.self, from: data)
    }
}
