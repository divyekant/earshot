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
    /// The time in ms of one read of the sidebar, for each app.
    let readMs: [String: Double]
    /// The time in ms until the list stopped changing, for each app. Electron apps build the tree late.
    let settleMs: [String: Double]?
    /// Extra spoken names of an app, from the placeholder of its message box ("iMessage").
    let aliases: [String: [String]]?

    enum CodingKeys: String, CodingKey {
        case owner, entries, aliases
        case builtAt = "built_at"
        case readMs = "read_ms"
        case settleMs = "settle_ms"
    }
}

/// One name read from a sidebar.
struct SidebarName {
    let name: String
    let isSelf: Bool
    /// True if the name came from a row of a list. A row is the most reliable source.
    let fromRow: Bool
    let how: String
}

struct SidebarRead {
    var names: [SidebarName] = []
    var nodes = 0
    /// True if the sidebar shows "loading". The app has not built its list yet.
    var loading = false
    var placeholder: String?
    var ms = 0.0
}

@MainActor
enum NameIndex {
    static var url: URL { Paths.logs.appendingPathComponent("index.json") }

    /// The sidebar is at most the left 42 % of the main window. It ends where the message box starts.
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
        "admin", "canvas", "list", "folder", "upgradeplan", "directories", "slack", "slackbot", "templates",
        "workflows", "automations", "starredchannels", "recent", "favorites", "favourites", "conversations",
        "channel", "directmessage", "dm", "group", "private", "public", "huddle", "mute", "muted", "notifications",
        "moreactions", "options", "close", "avatar", "image", "photo", "profile", "presence", "inactive", "pin",
    ]

    static let weekdays: Set<String> = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                                        "mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    static func isLoading(_ raw: String) -> Bool { raw.lowercased().contains("loading") }

    static let liveRegions: Set<String> = ["AXApplicationAlert", "AXApplicationLog", "AXApplicationStatus",
                                           "AXApplicationTimer", "AXApplicationMarquee"]

    /// Removes the owner mark, notes in brackets and invisible characters.
    /// Returns nil if the text is not a chat name.
    static func clean(_ raw: String) -> (name: String, isSelf: Bool)? {
        var s = Text.squash(raw)
        var isSelf = false
        if let range = s.range(of: "(you)", options: .caseInsensitive) {
            isSelf = true
            s.removeSubrange(range)
        }
        // "Drafts & sent (has unsent messages)" gives "Drafts & sent".
        s = s.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !isLoading(s), (2...48).contains(s.count), s.contains(where: \.isLetter) else { return nil }
        // A name with a phone number in it ("Manel & +1 (415) ...") stays out. It must not go to Jev.
        guard s.filter(\.isNumber).count < 6 else { return nil }
        let key = Text.key(s)
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

    /// The texts of a list row, from the top left. Chat lists put the name there,
    /// and the last message and the time after it.
    static func rowTexts(_ row: AXUIElement, maxNodes: Int = 120) -> [String] {
        var stack: [AXUIElement] = [row]
        var texts: [(String, Frame)] = []
        var count = 0
        while let el = stack.popLast(), count < maxNodes {
            count += 1
            let r = AX.role(el)
            let f = AX.frame(el) ?? Frame(x: 0, y: 0, w: 0, h: 0)
            if r == "AXStaticText", let v = AX.string(el, "AXValue"), !v.isEmpty {
                texts.append((v, f))
            } else if r != "AXRow", r != "AXCell" {
                // SwiftUI and Catalyst rows can carry the name as a description of a group, with no text child.
                for attribute in ["AXTitle", "AXDescription"] {
                    if let s = AX.string(el, attribute), !s.isEmpty { texts.append((s, f)) }
                }
            }
            stack.append(contentsOf: AX.elements(el, "AXChildren"))
        }
        let sorted = texts.sorted { a, b in
            let ay = (a.1.y / 6).rounded(), by = (b.1.y / 6).rounded()
            return ay != by ? ay < by : a.1.x < b.1.x
        }
        var out = sorted.map(\.0)
        // Last, the row's own name. A row name can hold several parts: "Ravi, 2 unread".
        for attribute in ["AXTitle", "AXDescription"] {
            if let s = AX.string(row, attribute), !s.isEmpty { out.append(s) }
        }
        return out
    }

    /// The right edge of the sidebar: the left edge of the message box, else 42 % of the window.
    static func sidebarEdge(_ window: AXUIElement, _ w: Frame) -> (Double, AXUIElement?) {
        var right = w.x + sidebarWidth * w.w
        let (box, _) = AX.findComposer(in: window)
        if let box, let b = AX.frame(box), b.x > w.x + 0.05 * w.w { right = min(right, b.x) }
        return (right, box)
    }

    /// Reads the sidebar of one window. It reads only.
    static func sidebar(window: AXUIElement, budgetMs: Int = 1500, maxNodes: Int = 20000) -> SidebarRead {
        var result = SidebarRead()
        guard let w = AX.frame(window) else { return result }
        let t0 = Clock.nowNs()
        let (right, box) = sidebarEdge(window, w)
        result.placeholder = box.flatMap { AX.string($0, "AXPlaceholderValue") }
        // Messages shows the placeholder as a text next to the box ("Text Message • SMS").
        let placeholderKey = result.placeholder.map { Text.key($0) } ?? ""
        let top = w.y + 0.03 * w.h
        var queue: [AXUIElement] = [window]
        var index = 0
        var seen = Set<String>()
        func add(_ raw: String?, fromRow: Bool, _ how: String, frame: Frame? = nil) -> Bool {
            guard let raw else { return false }
            // A text with no size is not on screen, for example a live region that says "loading…".
            if let f = frame, f.w == 0 || f.h == 0 { return false }
            if isLoading(raw) { result.loading = true }
            if !placeholderKey.isEmpty, Text.key(raw) == placeholderKey { return false }
            guard let c = clean(raw) else { return false }
            if seen.insert(Text.key(c.name)).inserted {
                result.names.append(SidebarName(name: c.name, isSelf: c.isSelf, fromRow: fromRow, how: how))
            }
            return true
        }
        while index < queue.count, index < maxNodes, Clock.ms(since: t0) < Double(budgetMs) {
            let el = queue[index]
            index += 1
            let r = AX.role(el)
            if ["AXMenuBar", "AXMenu", "AXImage", "AXScrollBar", "AXToolbar"].contains(r) { continue }
            // Live regions announce changes ("loading…", new messages). They are not the chat list.
            if liveRegions.contains(AX.subrole(el)) { continue }
            let frame = AX.frame(el)
            if let f = frame, f.w > 0, f.h > 0, !CFEqual(el, window) {
                // Leave out the main pane and the title bar, with all their children.
                if f.x >= right || f.maxY <= top { continue }
            }
            if r == "AXRow" || r == "AXCell" {
                for text in rowTexts(el) {
                    // The first part of a row name: "Ravi, 2 unread" gives "Ravi".
                    let part = text.split(separator: ",").first.map(String.init) ?? text
                    if add(part, fromRow: true, r) { break }
                }
                continue
            }
            if r == "AXStaticText" {
                // Messages (Catalyst) shows each chat as a text with an empty value. Its description
                // holds "Name, Unread, last message", so the name is the part before the first comma.
                let value = AX.string(el, "AXValue") ?? ""
                let text = value.isEmpty
                    ? AX.string(el, "AXDescription")?.split(separator: ",").first.map(String.init) : value
                _ = add(text, fromRow: false, r, frame: frame)
            }
            if r == "AXLink" || r == "AXButton" {
                _ = add(AX.string(el, "AXTitle") ?? AX.string(el, "AXDescription"), fromRow: false, r, frame: frame)
            }
            queue.append(contentsOf: AX.elements(el, "AXChildren"))
        }
        result.nodes = index
        result.ms = Clock.ms(since: t0)
        return result
    }

    /// Prints the sidebar part of the tree: role, position and the length of each text.
    /// It prints the first 20 characters of a text only, so that message previews do not show in full.
    static func dump(window: AXUIElement, maxNodes: Int = 300) {
        guard let w = AX.frame(window) else { return }
        let (right, _) = sidebarEdge(window, w)
        print("   sidebar edge at x \(Int(((right - w.x) / max(w.w, 1) * 100).rounded()))%")
        var count = 0
        func pct(_ v: Double, _ origin: Double, _ size: Double) -> Int { Int(((v - origin) / max(size, 1) * 100).rounded()) }
        func walk(_ el: AXUIElement, _ depth: Int) {
            guard count < maxNodes, depth < 16 else { return }
            count += 1
            let f = AX.frame(el)
            if let f, f.w > 0, f.x >= right, !CFEqual(el, window) { return }
            var line = String(repeating: "  ", count: depth) + AX.role(el)
            let sub = AX.subrole(el)
            if !sub.isEmpty { line += "/\(sub)" }
            if let f { line += " [x\(pct(f.x, w.x, w.w)) y\(pct(f.y, w.y, w.h)) w\(Int((f.w / max(w.w, 1) * 100).rounded())) h\(Int((f.h / max(w.h, 1) * 100).rounded()))]" }
            for (short, attribute) in [("t", "AXTitle"), ("d", "AXDescription"), ("v", "AXValue")] {
                if let s = AX.string(el, attribute), !s.isEmpty {
                    line += " \(short)=\"\(Text.squash(s).prefix(20))\"(\(s.count))"
                }
            }
            let children = AX.elements(el, "AXChildren")
            if !children.isEmpty { line += " children=\(children.count)" }
            print("   " + line)
            for c in children { walk(c, depth + 1) }
        }
        walk(window, 0)
    }

    /// Spoken app names in the placeholder of the message box. Only a word with a capital letter
    /// inside it counts, such as "iMessage", so that the chat name in "Message Ravi" does not count.
    static func placeholderAliases(_ placeholder: String?) -> [String] {
        guard let p = placeholder else { return [] }
        return p.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { word in
            word.count >= 4 && word.dropFirst().contains(where: \.isUppercase)
        }.map { $0.lowercased() }
    }

    /// Reads the sidebar of each chat app in the catalogue. It reads again every 300 ms,
    /// up to 8 times, until the list stops changing. The owner's own chat gets the owner's name.
    static func build(catalogue: CatalogueFile, front: Bool, debug: Bool, dumpTree: Bool) async -> IndexFile {
        let owner = NSFullUserName()
        let before = NSWorkspace.shared.frontmostApplication
        var entries: [IndexEntry] = []
        var times: [String: Double] = [:]
        var settle: [String: Double] = [:]
        var aliases: [String: [String]] = [:]
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
            if debug || dumpTree { print("== \(app.name)") }
            let windows = Array(AX.elements(el, "AXWindows").prefix(2))
            if dumpTree { for win in windows { dump(window: win) } }

            var kept: [SidebarName] = []
            var lastCount = -1
            var oneRead = 0.0
            var nodes = 0
            var placeholder: String?
            var stillLoading = false
            for attempt in 0..<8 {
                var all: [SidebarName] = []
                var loading = false
                nodes = 0
                oneRead = 0
                for win in windows {
                    let r = sidebar(window: win)
                    nodes += r.nodes
                    oneRead += r.ms
                    loading = loading || r.loading
                    placeholder = placeholder ?? r.placeholder
                    for n in r.names where !all.contains(where: { Text.key($0.name) == Text.key(n.name) }) { all.append(n) }
                }
                // Rows are the chat list. If the sidebar has rows, the loose texts and buttons
                // around them are labels of the screen, not chats.
                let rows = all.filter(\.fromRow)
                let now = rows.isEmpty ? all : rows
                if now.count >= kept.count { kept = now }
                stillLoading = loading
                if !loading, now.count == lastCount, now.count > 0 { break }
                lastCount = now.count
                if attempt < 7 { await sleepMs(300) }
            }
            let total = (Clock.ms(since: t0) * 10).rounded() / 10
            times[app.id] = (oneRead * 10).rounded() / 10
            settle[app.id] = total
            let extra = placeholderAliases(placeholder).filter { !app.aliases.contains($0) }
            if !extra.isEmpty { aliases[app.id] = extra }
            if debug {
                for n in kept { print("     \(n.how)\(n.fromRow ? " (row)" : ""): \(n.name)\(n.isSelf ? " (self)" : "")") }
                print("   \(kept.count) names, \(nodes) nodes, one read \(Int(oneRead.rounded())) ms, settled in \(Int(total.rounded())) ms\(stillLoading ? ", STILL LOADING" : "")")
                if let placeholder { print("   message box placeholder: \"\(placeholder.prefix(40))\" → extra app names: \(extra)") }
            }
            var hasSelf = false
            for n in kept {
                let isSelf = n.isSelf || Text.key(n.name) == Text.key(owner)
                hasSelf = hasSelf || isSelf
                entries.append(IndexEntry(app: app.id, name: n.name, isSelf: isSelf))
            }
            // E0 showed that both Slack and Messages find the owner's own chat by the owner's name.
            if !hasSelf { entries.append(IndexEntry(app: app.id, name: owner, isSelf: true)) }
        }
        if front { before?.activate() }
        return IndexFile(builtAt: ISO8601DateFormatter().string(from: Date()), owner: owner, entries: entries,
                         readMs: times, settleMs: settle, aliases: aliases)
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
