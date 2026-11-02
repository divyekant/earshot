import EarshotCore
import Foundation

/// One name that earshot read from a sidebar.
public struct SidebarName: Hashable, Sendable {
    public var name: String
    public var isSelf: Bool
    /// True if the name came from a row of a list. A row is the most reliable source (E1).
    public var fromRow: Bool

    public init(name: String, isSelf: Bool = false, fromRow: Bool) { self.name = name; self.isSelf = isSelf; self.fromRow = fromRow }
}

/// One screen line below a search field: the texts of the line, joined from left to right.
public struct ResultLine: Hashable, Sendable {
    public var text: String
    /// True if the texts of the line are inside a list row or cell.
    public var inRow: Bool

    public init(_ text: String, inRow: Bool = false) { self.text = text; self.inRow = inRow }
}

/// The text rules for chat names (E1, sections 3.2 and 3.5). They drop screen labels, times,
/// counts, prompts and message hits. No rule names an app or a person (R-MT-1).
public enum NameRules {
    /// Common words of chat app screens, as keys (no spaces). They are labels, not chat names.
    public static let uiWords: Set<String> = [
        "home", "activity", "dms", "directmessages", "channels", "apps", "threads", "later", "more", "unreads",
        "draftssent", "drafts", "sent", "huddles", "search", "filter", "compose", "newmessage", "edit", "messages",
        "inbox", "archive", "junk", "trash", "flagged", "outbox", "vip", "allmail", "files", "canvases", "lists",
        "mentions", "saved", "starred", "pinned", "people", "contacts", "settings", "help", "chats", "calls",
        "status", "communities", "updates", "add", "addchannels", "addcoworkers", "invite", "browse", "show",
        "showmore", "showless", "seeall", "new", "today", "yesterday", "now", "unread", "read", "delivered",
        "typing", "online", "away", "active", "you", "me", "workspace", "external", "sidebar", "tools",
        "admin", "canvas", "list", "folder", "upgradeplan", "directories", "templates",
        "workflows", "automations", "starredchannels", "recent", "favorites", "favourites", "conversations",
        "channel", "directmessage", "dm", "group", "private", "public", "huddle", "mute", "muted", "notifications",
        "moreactions", "options", "close", "avatar", "image", "photo", "profile", "presence", "inactive", "pin",
        "select", "givefeedback", "selectgivefeedback", "agent", "sirifoundinapps", "suggestions", "topresults",
        "recentsearches",
    ]

    public static let weekdays: Set<String> = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                                               "mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    public static func isLoading(_ raw: String) -> Bool { raw.lowercased().contains("loading") }

    /// Removes the owner mark "(you)", notes in brackets and invisible characters.
    /// Returns nil if the text is not a chat name.
    public static func clean(_ raw: String) -> (name: String, isSelf: Bool)? {
        var s = Words.squash(raw)
        var isSelf = false
        if let range = s.range(of: "(you)", options: .caseInsensitive) {
            isSelf = true
            s.removeSubrange(range)
        }
        // "Drafts & sent (has unsent messages)" gives "Drafts & sent".
        s = s.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !isLoading(s), (2...48).contains(s.count), s.contains(where: \.isLetter) else { return nil }
        // A name with a phone number in it stays out. It must not go to tier 2.
        guard s.filter(\.isNumber).count < 6 else { return nil }
        let key = Words.key(s)
        guard !uiWords.contains(key), !weekdays.contains(key) else { return nil }
        let lower = s.lowercased()
        // A draft row such as "New Message to Ravi" is not a chat.
        if ["new message", "new chat", "new conversation"].contains(where: { lower.hasPrefix($0) }) { return nil }
        // Section titles such as "Channel alerts" or "Direct message with ...".
        if lower.hasPrefix("channel ") || lower.hasPrefix("direct message") { return nil }
        // Times, dates and counts: "10:42", "9.30 PM", "12/10/26", "3m", "2 new".
        if lower.range(of: #"^\d{1,2}[:.]\d{2}"#, options: .regularExpression) != nil { return nil }
        if lower.range(of: #"^\d{1,2}/\d{1,2}(/\d{2,4})?$"#, options: .regularExpression) != nil { return nil }
        if lower.range(of: #"^\d+\s?(s|m|h|d|w|min|mins|new|more)$"#, options: .regularExpression) != nil { return nil }
        if lower.range(of: #"\b(am|pm)$"#, options: .regularExpression) != nil, s.contains(where: \.isNumber) { return nil }
        return (s, isSelf)
    }

    /// Spoken app names in the placeholder of the message box. Only a word with a capital letter
    /// inside it counts, such as "iMessage", so that the chat name in "Message Ravi" does not count.
    public static func placeholderAliases(_ placeholder: String?) -> [String] {
        guard let p = placeholder else { return [] }
        return p.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { word in
            word.count >= 4 && word.dropFirst().contains(where: \.isUppercase)
        }.map { $0.lowercased() }
    }

    /// The names to keep from one sidebar read. If the sidebar has list rows, the loose texts
    /// and buttons around them are screen labels, not chats (E1).
    public static func preferRows(_ names: [SidebarName]) -> [SidebarName] {
        let rows = names.filter(\.fromRow)
        return rows.isEmpty ? names : rows
    }

    // MARK: - Search results

    /// Prompt lines repeat the typed text: "Show results for: ravi", "Search for: ravi".
    public static let promptStarts = ["show results for", "search for", "results for", "recent messages", "no results",
                                      "try searching", "search all", "jump to"]

    /// Section titles after which the lines are message hits, not chats.
    public static let messageSections = ["recent messages", "messages in", "messages", "message results"]

    /// Turns one screen line of a result list into a chat name, or nil if the line is not a chat.
    public static func cleanResultLine(_ raw: String, appName: String) -> String? {
        var view = String.UnicodeScalarView()
        for u in raw.unicodeScalars where u.properties.generalCategory != .format { view.append(u) }
        var line = String(view)
        for (entity, char) in [("&#39;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            line = line.replacingOccurrences(of: entity, with: char)
        }
        line = Words.squash(line)
        // "Ravi Kumar • Today" is a message hit in Ravi's chat. Keep the name part.
        if let dot = line.range(of: " • ") { line = String(line[..<dot.lowerBound]) }
        let lower = line.lowercased()
        if promptStarts.contains(where: { lower.hasPrefix($0) }) { return nil }
        // File names and links: "setup.md", "NOTES_2026.pdf", "https://...".
        if lower.contains("://") || hasFileName(lower) { return nil }
        line = dropHandles(line)
        let words = line.split(separator: " ")
        // A sentence is a help item, not a chat name ("Connect your tools to Slack").
        if words.count >= 5 { return nil }
        // A line with the app's own name is a help or app item.
        let app = Words.normalize(appName)
        if !app.isEmpty, Words.normalize(line).split(separator: " ").contains(where: { $0 == app }) { return nil }
        // Section titles in capital letters ("SIRI FOUND IN APPS").
        if words.count >= 3, !line.contains(where: \.isLowercase) { return nil }
        let first = line.split(separator: ",").first.map(String.init) ?? line
        return clean(first)?.name
    }

    /// Common document, image, media, archive and code file types. A user handle such as
    /// "prakash.iyer" has a dot too, so the check needs a known file type.
    public static let fileTypes: Set<String> = [
        "md", "txt", "rtf", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "csv", "tsv", "json", "xml", "yml",
        "yaml", "log", "png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "mov", "mp4", "m4a", "mp3", "wav", "zip",
        "gz", "tar", "dmg", "pkg", "key", "pages", "numbers", "swift", "js", "ts", "py", "rb", "go", "rs", "java",
        "html", "css", "sh", "sql", "fig", "sketch", "ipynb",
    ]

    /// True if a word of the line is a file name, for example "notes_2026.pdf" in "notes_2026.pdf, 2 KB".
    public static func hasFileName(_ lower: String) -> Bool {
        lower.split(whereSeparator: { $0 == " " || $0 == "," }).contains { word in
            guard let dot = word.lastIndex(of: "."), word.distance(from: word.startIndex, to: dot) >= 2 else { return false }
            return fileTypes.contains(String(word[word.index(after: dot)...]))
        }
    }

    /// Removes user handles ("prakash.iyer", "@ravi", "ravi_k") from a line that also has a name:
    /// "Prakash Iyer prakash.iyer" gives "Prakash Iyer".
    public static func dropHandles(_ line: String) -> String {
        let words = line.split(separator: " ").map(String.init)
        let kept = words.filter { w in
            let handle = w.hasPrefix("@") || (w == w.lowercased() && (w.contains(".") || w.contains("_")) && w.count > 2)
            return !handle
        }
        return kept.isEmpty ? line : kept.joined(separator: " ")
    }

    /// True if the line is a section title of message hits.
    public static func isMessageSection(_ raw: String) -> Bool {
        let n = Words.normalize(raw)
        return messageSections.contains { n == $0 || n.hasPrefix($0 + " ") }
    }

    /// The chat names in a result list, best first (E1, section 6):
    /// - It drops the echo: a line that is exactly the typed text, unless the line is a row of its own.
    /// - It drops the lines below a "Recent messages" title: they are message hits.
    /// - It puts message hits ("Ravi Kumar • Today") after the other names.
    /// - It keeps 12 names at most.
    public static func results(_ lines: [ResultLine], term: String, appName: String, limit: Int = 12) -> [String] {
        var names: [String] = []
        var hits: [String] = []
        var seen = Set<String>()
        let termKey = Words.key(term)
        for line in lines {
            if isMessageSection(line.text) { break }
            guard let name = cleanResultLine(line.text, appName: appName) else { continue }
            if !line.inRow, Words.key(Words.squash(line.text)) == termKey { continue }
            guard seen.insert(Words.key(name)).inserted else { continue }
            if line.text.contains(" • ") { hits.append(name) } else { names.append(name) }
        }
        return Array((names + hits).prefix(limit))
    }
}

/// Decides when the sidebar list is stable. Electron apps build the tree late, so earshot
/// reads again every 300 ms, 8 times at most (E1, section 3.2).
public struct SettleCheck: Sendable {
    public static let maxReads = 8
    public private(set) var kept: [SidebarName] = []
    public private(set) var reads = 0
    public private(set) var stillLoading = false
    private var lastCount = -1

    public init() {}

    /// Adds one read. Returns true when earshot can stop: the list did not change and nothing loads.
    /// An app with no list in its sidebar stops after 3 reads.
    public mutating func add(_ names: [SidebarName], loading: Bool) -> Bool {
        let now = NameRules.preferRows(names)
        if now.count >= kept.count { kept = now }
        stillLoading = loading
        defer { reads += 1; lastCount = now.count }
        if !loading, now.count == lastCount, now.count > 0 || reads >= 2 { return true }
        return reads + 1 >= SettleCheck.maxReads
    }
}

/// Joins names from several sources into one list for each app.
public enum NameMerge {
    static func rank(_ s: NameSource) -> Int {
        switch s {
        case .manual: return 0
        case .sidebar: return 1
        case .search: return 2
        case .contacts: return 3
        }
    }

    /// One entry for each app and name key. The router trusts the sources in this order:
    /// manual, sidebar, search, contacts. The best source wins. Aliases and the self mark join.
    public static func merge(_ lists: [[NameEntry]]) -> [NameEntry] {
        var out: [NameEntry] = []
        var index: [String: Int] = [:]
        for entry in lists.joined() {
            let k = entry.appID + "\u{1F}" + Words.key(entry.name)
            guard let i = index[k] else {
                index[k] = out.count
                out.append(entry)
                continue
            }
            var kept = out[i]
            if rank(entry.source) < rank(kept.source) {
                let aliases = kept.aliases
                let wasSelf = kept.isSelf
                kept = entry
                kept.aliases = aliases
                kept.isSelf = kept.isSelf || wasSelf
            }
            kept.isSelf = kept.isSelf || entry.isSelf
            for a in entry.aliases where !kept.aliases.contains(a) { kept.aliases.append(a) }
            out[i] = kept
        }
        return out
    }

    /// Names from Contacts: the full name, and the given name and the nickname as aliases.
    /// A card with no person name uses the company name.
    public static func contactEntry(appID: String, given: String, family: String, nickname: String,
                                    organization: String) -> NameEntry? {
        let full = Words.squash([given, family].filter { !$0.isEmpty }.joined(separator: " "))
        let name = full.isEmpty ? Words.squash(organization) : full
        guard NameRules.clean(name) != nil else { return nil }
        var aliases: [String] = []
        for a in [given, nickname] {
            let n = Words.normalize(a)
            if !n.isEmpty, n != Words.normalize(name), !aliases.contains(n) { aliases.append(n) }
        }
        return NameEntry(appID: appID, name: name, aliases: aliases, source: .contacts)
    }
}
