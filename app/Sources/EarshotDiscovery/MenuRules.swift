import EarshotCore
import Foundation

/// One menu item that has a key shortcut. `path` holds the titles from the menu bar down,
/// for example ["Go", "Switch to Channel"].
public struct MenuShortcut: Hashable, Sendable {
    public var path: [String]
    /// The shortcut as text, for example "cmd+k" or "cmd+shift+n".
    public var keys: String

    public init(path: [String], keys: String) { self.path = path; self.keys = keys }

    public var title: String { path.last ?? "" }
    public var pathText: String { path.joined(separator: " > ") }
}

/// The kind of menu item that the catalogue found.
public enum MenuRule: String, Codable, Sendable {
    /// "Switch to", "Jump to", "Quick switcher". It opens a chat by name.
    case switchTo = "switch"
    /// "New message", "New chat". It opens a "To:" field.
    case newMessage = "new message"
    /// "Search", "Find". It does not open a chat by itself.
    case search
}

/// The menu item that opens a chat, and the rule that found it.
public struct MenuGuess: Hashable, Sendable {
    public var keys: String
    public var menuPath: String
    public var rule: MenuRule

    public init(keys: String, menuPath: String, rule: MenuRule) { self.keys = keys; self.menuPath = menuPath; self.rule = rule }

    /// True if the item opens a chat by name. A search item alone does not make an app a chat app (E1).
    public var opensChat: Bool { rule != .search }
}

/// The rules that turn the menu items of an app into a catalogue row (E1, section 3.1).
/// They match whole words of the item title only. No rule names an app (R-MT-1).
public enum MenuRules {
    /// Title words, in order of preference. The first rule that matches wins.
    public static let rules: [(rule: MenuRule, words: [String])] = [
        (.switchTo, ["jump to", "switch to", "quick switcher", "go to conversation", "go to chat", "go to channel",
                     "find conversation"]),
        (.newMessage, ["new message", "new chat", "new conversation", "new direct message"]),
        (.search, ["search", "find"]),
    ]

    /// A title with one of these words is not a way to open a chat.
    public static let excluded = ["next", "previous", "selection", "replace", "spelling", "google", "page", "tab", "tabs",
                                  "mailbox", "web", "workspace", "window", "quit", "force",
                                  // "Jump to End" (WhatsApp) scrolls a chat. It does not switch chats.
                                  "end", "top", "bottom", "beginning", "latest", "oldest", "unread", "line",
                                  "date", "today", "definition"]

    /// Finds the best menu item that opens a chat. It skips the Apple menu, and keys that
    /// earshot cannot press. A shortcut with Return or Enter never counts: Command-Return sends a message in some apps.
    public static func guess(_ shortcuts: [MenuShortcut]) -> MenuGuess? {
        for (rule, words) in rules {
            for s in shortcuts {
                if s.path.first == "Apple" { continue }
                // Test the item title only: "Edit > Find > Find..." has the title "Find...".
                let title = " \(Words.normalize(s.title)) "
                guard words.contains(where: { title.contains(" \($0) ") }) else { continue }
                guard !excluded.contains(where: { title.contains(" \($0) ") }) else { continue }
                guard isPressable(s.keys) else { continue }
                return MenuGuess(keys: s.keys, menuPath: s.pathText, rule: rule)
            }
        }
        return nil
    }

    /// True if earshot can press the keys and they are not Return or Enter.
    public static func isPressable(_ keys: String) -> Bool {
        let parts = keys.split(separator: "+").map(String.init)
        guard let key = parts.last, !keys.contains("key code") else { return false }
        return !["return", "enter"].contains(key)
    }

    /// AXMenuItemCmdModifiers: 0 means Command only. Add 1 for Shift, 2 for Option, 4 for Control, 8 for no Command.
    public static func shortcutText(char: String, modifiers mods: Int, keyCode code: Int?) -> String {
        var parts: [String] = []
        if mods & 4 != 0 { parts.append("ctrl") }
        if mods & 2 != 0 { parts.append("opt") }
        if mods & 1 != 0 { parts.append("shift") }
        if mods & 8 == 0 { parts.append("cmd") }
        let names: [UInt32: String] = [0x0D: "return", 0x03: "enter", 0x09: "tab", 0x1B: "escape", 0x20: "space",
                                       0x08: "delete", 0x7F: "delete"]
        let codeNames: [Int: String] = [123: "left", 124: "right", 125: "down", 126: "up", 36: "return", 76: "enter"]
        if let scalar = char.unicodeScalars.first, let name = names[scalar.value] {
            parts.append(name)
        } else if let code, let name = codeNames[code] {
            parts.append(name)
        } else if let scalar = char.unicodeScalars.first,
                  scalar.properties.generalCategory == .control || scalar.properties.generalCategory == .privateUse {
            parts.append("key code \(code.map(String.init) ?? "?")")
        } else {
            parts.append(char.lowercased())
        }
        return parts.joined(separator: "+")
    }

    /// Words that the owner says in commands. The last word of an app name is not a spoken name
    /// if it is one of these: "Sublime Text" must not give "text" (E1).
    public static let commandWords: Set<String> = [
        "message", "text", "ping", "dm", "tell", "write", "chat", "open", "go", "switch", "launch", "show", "reply",
        "jump", "start", "send", "bring", "pull", "talk", "find", "reach", "saying", "say", "that", "hey", "ok", "okay",
        "earshot", "please", "can", "could", "you", "would", "to", "on", "in", "at", "with", "my", "the", "a", "an",
        "and", "app", "conversation", "channel", "i", "am", "is", "for", "of", "up", "back", "new", "own", "about",
        "over", "there", "here", "into",
    ]

    /// Spoken names for an app: the name, the bundle names, and the last word of a name with
    /// two or more words ("Google Chrome" gives "chrome"). No app name is written by hand.
    public static func aliases(for name: String, extra: [String] = []) -> [String] {
        var out: [String] = []
        func add(_ s: String) {
            let n = Words.normalize(s)
            if !n.isEmpty, !out.contains(n) { out.append(n) }
        }
        add(name)
        extra.forEach(add)
        let words = Words.normalize(name).split(separator: " ")
        if words.count >= 2, let last = words.last.map(String.init), last.count >= 4, !commandWords.contains(last) {
            add(last)
        }
        return out
    }

    /// URL schemes that many apps register. They do not name one app.
    public static let genericSchemes: Set<String> = [
        "http", "https", "file", "mailto", "ftp", "ftps", "sftp", "ssh", "telnet", "tel", "callto", "webcal", "feed",
        "feeds", "rss", "data", "about", "javascript", "ws", "wss", "git", "svn", "news", "nntp", "smb", "afp", "vnc",
        "itms", "itmss", "ical", "calshow", "maps", "help", "applescript", "shortcuts",
    ]

    /// Spoken names that an app declares in its Info.plist:
    /// - CFBundleDisplayName and CFBundleName.
    /// - The URL schemes in CFBundleURLTypes, if a scheme has only letters, at least 3 of them,
    ///   is not generic and is not a command word. Messages declares "imessage" and "sms" this way.
    public static func declaredNames(_ info: [String: Any]) -> [String] {
        var out = ["CFBundleDisplayName", "CFBundleName"].compactMap { info[$0] as? String }
        for type in info["CFBundleURLTypes"] as? [[String: Any]] ?? [] {
            for scheme in type["CFBundleURLSchemes"] as? [String] ?? [] {
                let s = scheme.lowercased()
                guard s.count >= 3, s.allSatisfy({ $0.isASCII && $0.isLetter }), !genericSchemes.contains(s),
                      !commandWords.contains(s), !out.contains(where: { Words.normalize($0) == s }) else { continue }
                out.append(s)
            }
        }
        return out
    }

    /// Makes one catalogue row from what earshot read. A row that opens chats needs the owner's approval
    /// before actions use it (R-MT-2). A row that only opens the app is approved: earshot presses no key in it.
    public static func entry(name: String, bundleID: String, extraNames: [String] = [], shortcuts: [MenuShortcut]?,
                             electron: Bool) -> AppEntry {
        let found = shortcuts.flatMap(guess)
        let chat = found?.opensChat ?? false
        let open: OpenChat = chat ? .switcher(keys: found!.keys) : .none
        let id = Words.key(name).isEmpty ? Words.key(bundleID) : Words.key(name)
        return AppEntry(id: id, name: name, bundleID: bundleID, aliases: aliases(for: name, extra: extraNames),
                        isChat: chat, openChat: open, electron: electron, approved: !chat, enabled: true)
    }

    /// Joins a new scan with the rows that the owner already has.
    /// - New spoken names from discovery always join the row's names.
    /// - An approved row stays as the owner left it. If it gains chat keys from a new menu read,
    ///   it takes the keys and keeps the approval, the name, the aliases and "enabled".
    /// - A row that is not approved takes the new scan, but keeps the owner's "enabled" choice.
    /// - A scan with less data (an installed app that does not run now) does not replace a row with menu data.
    /// - A row that the scan did not find stays.
    /// - Two apps with the same id get a number after the id: "notes", "notes2".
    public static func merge(existing: [AppEntry], found: [AppEntry]) -> [AppEntry] {
        var out = existing
        var index: [String: Int] = [:]
        for (i, row) in out.enumerated() { index[row.bundleID] = i }
        for new in found {
            if let i = index[new.bundleID] {
                let old = out[i]
                // New spoken names from discovery join the owner's names. The owner's names come first.
                let aliases = old.aliases + new.aliases.filter { !old.aliases.contains($0) }
                if (old.approved && (old.isChat || !new.isChat)) || (!new.isChat && old.isChat) {
                    out[i].aliases = aliases
                    continue
                }
                var row = new
                row.id = old.id
                row.enabled = old.enabled
                row.aliases = aliases
                if old.approved {
                    // The owner approved this row before earshot could read its menus, for example
                    // while Accessibility was off. Keep the approval and the owner's name.
                    row.approved = true
                    row.name = old.name
                }
                out[i] = row
            } else {
                var row = new
                let ids = Set(out.map(\.id))
                if ids.contains(row.id) {
                    var n = 2
                    while ids.contains("\(new.id)\(n)") { n += 1 }
                    row.id = "\(new.id)\(n)"
                }
                index[row.bundleID] = out.count
                out.append(row)
            }
        }
        return out.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
