import AppKit

// E1, question 2: the name index. The probe reads the chat names that each chat app
// shows in its sidebar. It needs no contact list and no names written by hand.

struct IndexEntry: Codable, Hashable {
    /// The catalogue id of the app.
    let app: String
    let name: String
    /// True for the owner's own chat.
    let isSelf: Bool

    enum CodingKeys: String, CodingKey {
        case app, name
        case isSelf = "self"
    }
}

struct IndexFile: Codable {
    let builtAt: String
    let owner: String
    let entries: [IndexEntry]
    /// Read time in ms for each app.
    let readMs: [String: Double]

    enum CodingKeys: String, CodingKey {
        case owner, entries
        case builtAt = "built_at"
        case readMs = "read_ms"
    }
}

@MainActor
enum NameIndex {
    static var url: URL { Paths.logs.appendingPathComponent("index.json") }

    /// The sidebar is the left part of the main window.
    static let sidebarWidth = 0.42

    /// Common words of chat app screens. They are labels, not chat names.
    static let uiWords: Set<String> = [
        "home", "activity", "dms", "directmessages", "channels", "apps", "threads", "later", "more", "unreads",
        "draftssent", "drafts", "sent", "huddles", "search", "filter", "compose", "newmessage", "edit", "messages",
        "inbox", "archive", "junk", "trash", "flagged", "outbox", "vip", "allmail", "files", "canvases", "lists",
        "mentions", "saved", "starred", "pinned", "people", "contacts", "settings", "help", "chats", "calls",
        "status", "communities", "updates", "add", "addchannels", "addcoworkers", "invite", "browse", "show",
        "showmore", "showless", "seeall", "new", "today", "yesterday", "now", "unread", "read", "delivered",
        "typing", "online", "away", "active", "you", "me", "workspace", "external", "sidebar", "tools",
    ]

    static let weekdays: Set<String> = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                                        "mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    /// Removes the owner mark and invisible characters. Returns nil if the text is not a chat name.
    static func clean(_ raw: String) -> (name: String, isSelf: Bool)? {
        var s = Text.squash(raw)
        var isSelf = false
        if let range = s.range(of: "(you)", options: .caseInsensitive) {
            isSelf = true
            s.removeSubrange(range)
            s = s.trimmingCharacters(in: .whitespaces)
        }
        guard (2...48).contains(s.count), s.contains(where: \.isLetter) else { return nil }
        let key = Text.key(s)
        guard !uiWords.contains(key), !weekdays.contains(key) else { return nil }
        let lower = s.lowercased()
        // Times, dates and counts: "10:42", "9.30 PM", "12/10/26", "3m", "2 new".
        if lower.range(of: #"^\d{1,2}[:.]\d{2}"#, options: .regularExpression) != nil { return nil }
        if lower.range(of: #"^\d{1,2}/\d{1,2}(/\d{2,4})?$"#, options: .regularExpression) != nil { return nil }
        if lower.range(of: #"^\d+\s?(s|m|h|d|w|min|mins|new|more)$"#, options: .regularExpression) != nil { return nil }
        if lower.range(of: #"\b(am|pm)$"#, options: .regularExpression) != nil, s.contains(where: \.isNumber) { return nil }
        return (s, isSelf)
    }

    /// The first text in a list row: the text nearest the top left. Chat lists put the name there,
    /// and the last message and the time after it.
    static func firstText(in row: AXUIElement, maxNodes: Int = 120) -> String? {
        var stack: [AXUIElement] = [row]
        var texts: [(String, Frame)] = []
        var count = 0
        while let el = stack.popLast(), count < maxNodes {
            count += 1
            let r = AX.role(el)
            if r == "AXStaticText", let v = AX.string(el, "AXValue"), let f = AX.frame(el), !v.isEmpty {
                texts.append((v, f))
            }
            stack.append(contentsOf: AX.elements(el, "AXChildren"))
        }
        let sorted = texts.sorted { a, b in
            let ay = (a.1.y / 6).rounded(), by = (b.1.y / 6).rounded()
            return ay != by ? ay < by : a.1.x < b.1.x
        }
        for (text, _) in sorted where clean(text) != nil { return text }
        // No text child: use the row name, up to the first comma ("Ravi, 2 unread").
        for attribute in ["AXTitle", "AXDescription"] {
            if let s = AX.string(row, attribute), let first = s.split(separator: ",").first,
               clean(String(first)) != nil { return String(first) }
        }
        return nil
    }

    /// Reads the sidebar of one window. It reads only. It returns the names and the number of nodes read.
    static func sidebar(window: AXUIElement, budgetMs: Int = 1500, maxNodes: Int = 20000,
                        debug: Bool = false) -> ([(name: String, isSelf: Bool)], Int) {
        guard let w = AX.frame(window) else { return ([], 0) }
        let right = w.x + sidebarWidth * w.w
        let top = w.y + 0.03 * w.h
        let t0 = Clock.nowNs()
        var queue: [AXUIElement] = [window]
        var index = 0
        var out: [(name: String, isSelf: Bool)] = []
        var seen = Set<String>()
        func add(_ raw: String?, _ how: String) {
            guard let raw, let c = clean(raw), seen.insert(Text.key(c.name)).inserted else { return }
            if debug { print("     \(how): \(c.name)\(c.isSelf ? " (self)" : "")") }
            out.append(c)
        }
        while index < queue.count, index < maxNodes, Clock.ms(since: t0) < Double(budgetMs) {
            let el = queue[index]
            index += 1
            let r = AX.role(el)
            if ["AXMenuBar", "AXMenu", "AXImage", "AXScrollBar", "AXToolbar"].contains(r) { continue }
            if let f = AX.frame(el), f.w > 0, f.h > 0, !CFEqual(el, window) {
                // Leave out the main pane and the title bar, with all their children.
                if f.x >= right || f.maxY <= top { continue }
            }
            if r == "AXRow" || r == "AXCell" {
                add(firstText(in: el), r)
                continue
            }
            if r == "AXStaticText" { add(AX.string(el, "AXValue"), r) }
            if r == "AXLink" || r == "AXButton" { add(AX.string(el, "AXTitle") ?? AX.string(el, "AXDescription"), r) }
            queue.append(contentsOf: AX.elements(el, "AXChildren"))
        }
        return (out, index)
    }

    /// Reads the sidebar of each chat app in the catalogue. The owner's own chat gets the owner's name.
    static func build(catalogue: CatalogueFile, front: Bool, debug: Bool) async -> IndexFile {
        let owner = NSFullUserName()
        let before = NSWorkspace.shared.frontmostApplication
        var entries: [IndexEntry] = []
        var times: [String: Double] = [:]
        let pipeline = Pipeline(apps: [])
        for app in catalogue.apps where app.chat {
            guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first else { continue }
            if front {
                _ = await pipeline.bringToFront(bundleID: app.bundleID)
                await sleepMs(400)
            }
            let t0 = Clock.nowNs()
            let el = AX.appElement(running.processIdentifier)
            if app.electron { AX.set(el, "AXManualAccessibility", kCFBooleanTrue) }
            if debug { print("== \(app.name)") }
            var names: [(name: String, isSelf: Bool)] = []
            var nodes = 0
            for win in AX.elements(el, "AXWindows").prefix(2) {
                let (found, n) = sidebar(window: win, debug: debug)
                nodes += n
                for f in found where !names.contains(where: { Text.key($0.name) == Text.key(f.name) }) { names.append(f) }
            }
            let ms = (Clock.ms(since: t0) * 10).rounded() / 10
            times[app.id] = ms
            if debug { print("   \(names.count) names, \(nodes) nodes, \(Int(ms.rounded())) ms") }
            var hasSelf = false
            for n in names {
                let isSelf = n.isSelf || Text.key(n.name) == Text.key(owner)
                hasSelf = hasSelf || isSelf
                entries.append(IndexEntry(app: app.id, name: n.name, isSelf: isSelf))
            }
            // E0 showed that both Slack and Messages find the owner's own chat by the owner's name.
            if !hasSelf { entries.append(IndexEntry(app: app.id, name: owner, isSelf: true)) }
        }
        if front { before?.activate() }
        return IndexFile(builtAt: ISO8601DateFormatter().string(from: Date()), owner: owner, entries: entries, readMs: times)
    }

    static func save(_ file: IndexFile) throws {
        try FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url)
    }

    static func load() throws -> IndexFile {
        guard let data = try? Data(contentsOf: url) else {
            throw ProbeError("probe/logs/index.json does not exist. Run: swift run earshot-probe index")
        }
        return try JSONDecoder().decode(IndexFile.self, from: data)
    }
}
