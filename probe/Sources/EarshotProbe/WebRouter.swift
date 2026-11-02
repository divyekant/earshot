import Foundation

// E2, question 2: the generic web router. It knows no site. It gets only the words
// and the element list of the page. Rules first; Jev only when the rules are unsure.
// One Jev call for each command at most. There is no agent loop (R-SP-2).

/// One web action: press an element, type into a field, scroll, go back, nothing, or blocked.
struct WebChoice: Codable, Equatable {
    let action: String
    let element: String?
    let text: String?

    static let noAction = WebChoice(action: "none", element: nil, text: nil)

    func matches(_ expected: WebChoice) -> Bool {
        guard action == expected.action else { return false }
        if let e = expected.element, e != element { return false }
        if let t = expected.text, Text.normalize(t) != Text.normalize(text ?? "") { return false }
        return true
    }

    func describe(_ elements: [WebElement]) -> String {
        let label = element.flatMap { id in elements.first(where: { $0.id == id }) }.map { "\($0.kind) \"\($0.label)\"" } ?? element ?? ""
        switch action {
        case "press": return "press \(label)"
        case "blocked": return "BLOCKED \(label)"
        case "type": return "type \"\(text ?? "")\" into \(label)"
        case "scroll": return "scroll \(text ?? "")"
        case "back": return "back"
        default: return "none"
        }
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = ["action": action]
        if let element { d["element"] = element }
        if let text { d["text"] = text }
        return d
    }
}

struct WebOption {
    let id: String
    let choice: WebChoice
    let label: String
    let score: Double
}

/// What the words ask for.
struct WebParse {
    var intent = "press"         // press, type, ordinal, scroll, back
    var isCommand = false
    var target: [String] = []
    var roleHint: String?
    var ordinal: Int?            // 1 is the first; -1 is the last
    var ordinalNoun: String?
    var text: String?            // the words to type, or the scroll direction
}

struct WebRoute {
    let parse: WebParse
    let options: [WebOption]
    let rules: WebChoice
    let sure: Bool
    let why: String
    let ms: Double
}

enum WebRouter {
    static let fillers: Set<String> = ["hey", "ok", "okay", "earshot", "please", "can", "could", "you", "would", "now", "then",
                                       "just", "lets", "let", "us", "i", "want", "to", "need"]
    static let pressVerbs: Set<String> = ["click", "press", "tap", "open", "select", "choose", "hit", "follow", "visit", "go",
                                          "show", "check", "toggle", "expand", "view", "take", "jump", "pick"]
    static let typeVerbs: Set<String> = ["search", "find", "look", "type", "enter"]
    /// Words at the start of the target that are not part of a label.
    static let leadWords: Set<String> = ["to", "the", "a", "an", "on", "my", "this", "that", "me", "into", "at", "up", "over"]
    /// Words at the end of the target that are not part of a label.
    static let tailWords: Set<String> = ["button", "link", "tab", "page", "field", "box", "menu", "item", "option", "section",
                                         "please", "here", "now", "for", "me", "checkbox", "one"]
    /// Small words that do not count when the probe measures how much of a label the words cover.
    static let smallWords: Set<String> = ["to", "the", "a", "an", "of", "and", "for", "in", "on", "with", "your", "you", "at", "by", "or"]
    static let roleWords: [String: String] = ["button": "button", "link": "link", "tab": "tab", "field": "field", "box": "field",
                                              "checkbox": "check"]
    static let ordinals: [String: Int] = ["first": 1, "1st": 1, "second": 2, "2nd": 2, "third": 3, "3rd": 3, "fourth": 4, "4th": 4,
                                          "fifth": 5, "5th": 5, "sixth": 6, "6th": 6, "last": -1]
    static let ordinalNouns: Set<String> = ["result", "results", "link", "story", "article", "item", "entry", "post", "video",
                                            "button", "tab", "headline", "hit", "one"]

    static let strongMatch = 0.8
    static let margin = 0.08
    static let noMatch = 0.5
    static let shortListSize = 8

    // MARK: - Safety

    static let riskyWords: Set<String> = [
        "send", "pay", "buy", "purchase", "order", "checkout", "submit", "delete", "remove", "publish", "post", "merge",
        "close", "archive", "approve", "accept", "decline", "reject", "confirm", "donate", "subscribe", "unsubscribe",
        "install", "upload", "share", "report", "block", "mute", "transfer", "upvote", "downvote", "vote", "flag", "hide",
        "favorite", "favourite", "like", "follow", "unfollow", "star", "unstar", "fork", "watch", "unwatch", "sponsor",
        "logout", "signout", "save", "discard", "reply", "comment", "invite", "leave", "cancel", "reset", "revoke",
        "disconnect", "unpublish", "retweet", "repost",
    ]
    static let riskyPhrases = ["sign out", "log out", "add to cart", "buy now", "place order", "pay now", "check out"]

    /// True if pressing the element can change data, send something or spend money (R-NV-5, R-ON-5).
    static func isRisky(_ label: String) -> Bool {
        let n = Text.normalize(label)
        let words = Set(n.split(separator: " ").map(String.init))
        if !words.isDisjoint(with: riskyWords) { return true }
        return riskyPhrases.contains { " \(n) ".contains(" \($0) ") }
    }

    /// The last check before an answer leaves the router. A press on a risky element becomes "blocked".
    static func guarded(_ c: WebChoice, _ elements: [WebElement]) -> WebChoice {
        guard c.action == "press", let id = c.element, let e = elements.first(where: { $0.id == id }), isRisky(e.label) else { return c }
        return WebChoice(action: "blocked", element: id, text: nil)
    }

    // MARK: - Parse

    static func parse(_ words: String) -> WebParse {
        var p = WebParse()
        var t = Text.normalize(words).split(separator: " ").map(String.init)
        while let first = t.first, fillers.contains(first), t.count > 1 { t.removeFirst() }
        let joined = " \(t.joined(separator: " ")) "

        // Scroll.
        let scrollTop = [" go to the top ", " back to the top ", " top of the page ", " scroll to the top ", " scroll up to the top "]
        let scrollBottom = [" go to the bottom ", " bottom of the page ", " scroll to the bottom ", " scroll down to the bottom "]
        if scrollTop.contains(where: { joined.contains($0) }) { p.intent = "scroll"; p.text = "top"; p.isCommand = true; return p }
        if scrollBottom.contains(where: { joined.contains($0) }) { p.intent = "scroll"; p.text = "bottom"; p.isCommand = true; return p }
        if t.contains("scroll") || t == ["page", "down"] || t == ["page", "up"] {
            p.intent = "scroll"
            p.text = t.contains("up") ? "up" : "down"
            p.isCommand = true
            return p
        }

        // Back.
        if let b = t.firstIndex(of: "back"), b <= 1, Array(t[(b + 1)...]).allSatisfy({ ["a", "one", "page"].contains($0) }) {
            p.intent = "back"
            p.isCommand = true
            return p
        }
        if joined.contains(" previous page ") { p.intent = "back"; p.isCommand = true; return p }

        // Type: "search for X", "look up X", "type X into Y".
        if let first = t.first, typeVerbs.contains(first), t.count >= 2 {
            var rest = Array(t.dropFirst())
            if first == "type" || first == "enter" {
                if let into = rest.lastIndex(where: { $0 == "into" || $0 == "in" }), into > 0 {
                    p.target = strip(Array(rest[(into + 1)...]))
                    rest = Array(rest[..<into])
                }
            } else {
                while let w = rest.first, ["for", "up", "the", "web"].contains(w), rest.count > 1 { rest.removeFirst() }
            }
            p.intent = "type"
            p.text = rest.joined(separator: " ")
            p.isCommand = true
            return p
        }

        // Ordinal: "open the second result".
        for (i, w) in t.enumerated() {
            guard let n = ordinals[w] else { continue }
            let next = t[(i + 1)..<min(i + 3, t.count)]
            if let noun = next.first(where: { ordinalNouns.contains($0) }) {
                p.intent = "ordinal"
                p.ordinal = n
                p.ordinalNoun = noun == "results" ? "result" : noun
                p.isCommand = true
                return p
            }
        }

        // Press.
        if let v = t.prefix(3).firstIndex(where: { pressVerbs.contains($0) }) {
            p.isCommand = true
            p.target = strip(Array(t[(v + 1)...]))
        } else {
            p.target = strip(t)
        }
        if let hint = t.reversed().first(where: { roleWords[$0] != nil }) { p.roleHint = roleWords[hint] }
        return p
    }

    /// Removes the lead and tail words: "to the issues page" gives "issues".
    static func strip(_ words: [String]) -> [String] {
        var w = words
        while let f = w.first, leadWords.contains(f), w.count > 1 { w.removeFirst() }
        while let l = w.last, tailWords.contains(l), w.count > 1 { w.removeLast() }
        // "can you open the Talk link" leaves a role word only if it is the whole target.
        return w
    }

    // MARK: - Score

    /// 1.0 is a full match. The larger of the whole-phrase similarity and the word cover.
    static func score(_ target: [String], _ label: String) -> Double {
        guard !target.isEmpty else { return 0 }
        let full = Text.similarity(target.joined(), Text.key(label))
        let labelWords = Text.normalize(label).split(separator: " ").map(String.init)
        guard !labelWords.isEmpty else { return full }
        var cover = 0.0
        for t in target {
            let best = labelWords.map { Text.similarity(t, $0) }.max() ?? 0
            if best >= 0.75 { cover += best }
        }
        cover /= Double(target.count)
        var content = labelWords.filter { !smallWords.contains($0) && Int($0) == nil }
        if content.isEmpty { content = labelWords }
        let found = content.filter { l in target.contains { Text.similarity($0, l) >= 0.75 } }.count
        let precision = Double(found) / Double(content.count)
        return max(full, cover * (0.7 + 0.3 * precision))
    }

    /// The result list for an ordinal: links in headings, else links with 4 or more words.
    /// A risky element is never a result: on Wikipedia, the fundraising banner is a long link.
    static func ordinalList(_ noun: String, _ all: [WebElement]) -> [WebElement] {
        let elements = all.filter { !isRisky($0.label) }
        switch noun {
        case "button": return elements.filter { $0.kind == "button" }
        case "tab": return elements.filter { $0.kind == "tab" }
        case "link": return elements.filter { $0.kind == "link" }
        default:
            let headed = elements.filter { $0.kind == "link" && $0.inHeading }
            if headed.count >= 2 { return headed }
            return elements.filter { $0.kind == "link" && $0.words >= 4 }
        }
    }

    // MARK: - Route

    static func route(_ words: String, elements: [WebElement]) -> WebRoute {
        let t0 = Clock.nowNs()
        let p = parse(words)
        var options: [WebOption] = []
        func done(_ c: WebChoice, _ sure: Bool, _ why: String) -> WebRoute {
            WebRoute(parse: p, options: options, rules: guarded(c, elements), sure: sure, why: why, ms: Clock.ms(since: t0))
        }

        switch p.intent {
        case "scroll":
            return done(WebChoice(action: "scroll", element: nil, text: p.text), true, "scroll words")
        case "back":
            return done(WebChoice(action: "back", element: nil, text: nil), true, "back words")
        case "type":
            let fields = elements.filter { $0.kind == "field" }
            let ranked = fields.map { f -> (WebElement, Double) in
                let s = p.target.isEmpty ? (f.isSearchField ? 1.0 : (f.role == "AXTextArea" ? 0.4 : 0.6)) : score(p.target, f.label)
                return (f, s)
            }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.y < $1.0.y }
            for (f, s) in ranked.prefix(3) {
                options.append(WebOption(id: "o\(options.count + 1)", choice: WebChoice(action: "type", element: f.id, text: p.text),
                                         label: "Type the words into the field \"\(f.label)\"", score: s))
            }
            guard let top = ranked.first, top.1 >= 0.8, !(p.text ?? "").isEmpty else {
                return done(WebChoice.noAction, true, "no search field")
            }
            return done(WebChoice(action: "type", element: top.0.id, text: p.text), true, "search field")
        case "ordinal":
            let list = ordinalList(p.ordinalNoun ?? "result", elements)
            let n = p.ordinal ?? 1
            let index = n == -1 ? list.count - 1 : n - 1
            guard index >= 0, index < list.count else { return done(WebChoice.noAction, true, "list too short (\(list.count))") }
            return done(WebChoice(action: "press", element: list[index].id, text: nil), true, "\(p.ordinalNoun ?? "") \(n) of \(list.count)")
        default:
            break
        }

        // Press: score every element with a label.
        var scored: [(WebElement, Double)] = []
        for e in elements where !e.label.isEmpty {
            var s = score(p.target, e.label)
            if let hint = p.roleHint, hint == e.kind { s += 0.05 }
            if s >= 0.3 { scored.append((e, s)) }
        }
        scored.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.y < $1.0.y }
        // The same label more than once: tell the copies apart for Jev.
        var seen: [String: Int] = [:]
        for (e, s) in scored.prefix(shortListSize) {
            let key = Text.key(e.label)
            seen[key, default: 0] += 1
            let copy = seen[key]! > 1 ? " (copy \(seen[key]!) on the page)" : ""
            options.append(WebOption(id: "o\(options.count + 1)", choice: WebChoice(action: "press", element: e.id, text: nil),
                                     label: "Click the \(e.kind) \"\(e.label)\"\(copy)", score: s))
        }
        options.append(WebOption(id: "scroll", choice: WebChoice(action: "scroll", element: nil, text: "down"),
                                 label: "Scroll down the page", score: 0))
        options.append(WebOption(id: "back", choice: WebChoice(action: "back", element: nil, text: nil),
                                 label: "Go back to the previous page", score: 0))
        options.append(WebOption(id: "none", choice: WebChoice.noAction,
                                 label: "None: no element on this page has a label with the meaning of the command", score: 0))

        guard let top = scored.first, top.1 >= noMatch else {
            return done(WebChoice.noAction, true, p.isCommand ? "no label matches" : "no command word")
        }
        let pick = WebChoice(action: "press", element: top.0.id, text: nil)
        guard p.isCommand else { return done(WebChoice.noAction, top.1 < strongMatch, "a label matches, but no command word") }
        // The next element with a different label, or the same label with a different address.
        let rival = scored.dropFirst().first { e in
            Text.key(e.0.label) != Text.key(top.0.label) || (e.0.url ?? "") != (top.0.url ?? "")
        }
        if top.1 >= strongMatch, rival == nil || rival!.1 <= top.1 - margin {
            return done(pick, true, "label match")
        }
        return done(pick, false, rival != nil && rival!.1 > top.1 - margin ? "two labels match" : "weak label match")
    }

    // MARK: - Jev

    static let jevGoal = "Pick the option that the owner's voice command asks for on this web page."
    static let jevRules = """
    The command comes from speech to text, so words can be heard wrong. \
    Pick the element whose label matches the command best. A command can name only part of a label. \
    If the command asks to scroll or to go back, pick that option. \
    Do not pick an element only because it is the closest option. \
    If no label has the meaning of the command, or the words are not a command for this page, pick none.
    """

    /// With `budgetMs`, it waits at most that time for Jev, and then throws. The caller then keeps the rules answer.
    static func askJev(_ words: String, _ r: WebRoute, elements: [WebElement], jev: JevClient, budgetMs: Int? = nil) async throws
        -> (WebChoice, JevClient.Answer) {
        let options = r.options.map { (id: $0.id, label: $0.label) }
        let ask: @Sendable () async throws -> JevClient.Answer = {
            try await jev.choose(id: "web", options: options, goal: jevGoal, rules: jevRules, state: ["command": words])
        }
        let answer: JevClient.Answer
        if let budgetMs {
            answer = try await withThrowingTaskGroup(of: JevClient.Answer?.self) { group in
                group.addTask { try await ask() }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(budgetMs) * 1_000_000)
                    return nil
                }
                defer { group.cancelAll() }
                guard let first = try await group.next(), let a = first else {
                    throw ProbeError("no answer in \(budgetMs) ms")
                }
                return a
            }
        } else {
            answer = try await ask()
        }
        let choice = r.options.first(where: { $0.id == answer.choice })?.choice ?? WebChoice.noAction
        return (guarded(choice, elements), answer)
    }
}
