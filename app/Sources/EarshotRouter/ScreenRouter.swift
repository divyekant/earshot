import EarshotCore

/// What the words ask for on the screen.
struct ScreenParse {
    enum Kind: Equatable { case press, type, ordinal, scroll, back }
    var kind: Kind = .press
    var isCommand = false
    var target: [String] = []
    var roleHint: String?
    /// 1 is the first, -1 is the last.
    var ordinal: Int?
    var ordinalNoun: String?
    /// The words to type, as the owner said them.
    var text: String?
    var scroll: ScrollDirection?
}

/// Voice clicks on the front window. Ported from probe WebRouter (E2, section 6.1). It knows no site.
/// It gets only the words and the elements of the screen. Numbers in a command must match exactly (E2, section 7).
enum ScreenRouter {
    static let fillers: Set<String> = Set(["hey", "ok", "okay", "earshot", "please", "can", "could", "you", "would", "now", "then",
                                           "just", "lets", "let", "us", "i", "want", "to", "need"]).union(TextKit.hesitations)
    static let pressVerbs: Set<String> = ["click", "press", "tap", "open", "select", "choose", "hit", "follow", "visit", "go",
                                          "show", "check", "toggle", "expand", "view", "take", "jump", "pick"]
    static let typeVerbs: Set<String> = ["search", "find", "look", "type", "enter"]
    /// Words at the start of the target that are not part of a label.
    static let leadWords: Set<String> = ["to", "the", "a", "an", "on", "my", "this", "that", "me", "into", "at", "up", "over",
                                         "number"]
    /// Words at the end of the target that are not part of a label.
    static let tailWords: Set<String> = ["button", "link", "tab", "page", "field", "box", "menu", "item", "option", "section",
                                         "please", "here", "now", "for", "me", "checkbox", "one"]
    /// Small words that do not count when the router measures how much of a label the words cover.
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

    // MARK: - Elements

    static let buttonRoles: Set<String> = ["AXButton", "AXMenuButton", "AXPopUpButton", "AXDisclosureTriangle"]
    static let fieldRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// link, button, field, check, tab or choice. Nil for an element that earshot does not press.
    static func kind(_ e: ScreenElement) -> String? {
        let role = e.role
        if role == "AXLink" { return "link" }
        if buttonRoles.contains(role) { return "button" }
        if fieldRoles.contains(role) { return "field" }
        if role == "AXCheckBox" || role == "AXSwitch" { return "check" }
        if role == "AXRadioButton" { return e.subrole == "AXTabButton" ? "tab" : "choice" }
        if role == "AXTab" { return "tab" }
        if role == "AXMenuItem" { return "choice" }
        // The actions module also reads list rows (a chat in a sidebar) and the texts of its OCR fallback (R-CL-4).
        if role == "AXRow" { return "row" }
        if role == ocrRole { return "text" }
        return nil
    }

    /// The role that the actions module gives to a text found by OCR. It has no accessibility element.
    static let ocrRole = "OCRText"

    static func isSearchField(_ e: ScreenElement) -> Bool {
        kind(e) == "field" && (e.subrole == "AXSearchField" || TextKit.normalize(e.label).contains("search"))
    }

    // MARK: - Parse

    static func parse(_ spoken: String) -> ScreenParse {
        var p = ScreenParse()
        var tokens = Tokens(spoken)
        var lead = 0
        while lead < tokens.count - 1, fillers.contains(tokens.words[lead]) { lead += 1 }
        tokens.dropFirst(lead)
        let t = tokens.words
        guard !t.isEmpty else { return p }
        let joined = " \(t.joined(separator: " ")) "

        // Scroll.
        let scrollTop = [" go to the top ", " back to the top ", " top of the page ", " scroll to the top ", " scroll up to the top "]
        let scrollBottom = [" go to the bottom ", " bottom of the page ", " scroll to the bottom ", " scroll down to the bottom "]
        if scrollTop.contains(where: { joined.contains($0) }) { p.kind = .scroll; p.scroll = .top; p.isCommand = true; return p }
        if scrollBottom.contains(where: { joined.contains($0) }) { p.kind = .scroll; p.scroll = .bottom; p.isCommand = true; return p }
        if t.first == "scroll" || t.dropFirst().first == "scroll" || t == ["page", "down"] || t == ["page", "up"] {
            p.kind = .scroll
            p.scroll = t.contains("up") ? .up : .down
            p.isCommand = true
            return p
        }

        // Back.
        if let b = t.firstIndex(of: "back"), b <= 1, t[(b + 1)...].allSatisfy({ ["a", "one", "page"].contains($0) }) {
            p.kind = .back
            p.isCommand = true
            return p
        }
        if joined.contains(" previous page ") { p.kind = .back; p.isCommand = true; return p }

        // Type: "search for X", "look up X", "type X into Y".
        if let first = t.first, typeVerbs.contains(first), t.count >= 2 {
            var start = 1
            var end = t.count
            if first == "type" || first == "enter" {
                if let into = t.indices.dropFirst(2).last(where: { t[$0] == "into" || t[$0] == "in" }) {
                    p.target = strip(Array(t[(into + 1)...]))
                    end = into
                }
            } else {
                while start < end - 1, ["for", "up", "the", "web"].contains(t[start]) { start += 1 }
            }
            p.kind = .type
            p.text = tokens.raw(start..<end)
            p.isCommand = true
            return p
        }

        // Ordinal: "open the second result".
        for (i, w) in t.enumerated() {
            guard let n = ordinals[w] else { continue }
            let next = t[(i + 1)..<min(i + 3, t.count)]
            if let noun = next.first(where: { ordinalNouns.contains($0) }) {
                p.kind = .ordinal
                p.ordinal = n
                p.ordinalNoun = noun == "results" ? "result" : noun
                p.isCommand = true
                return p
            }
        }

        // Press.
        if let v = t.prefix(3).firstIndex(where: { pressVerbs.contains($0) }) {
            p.isCommand = true
            p.target = strip(TextKit.digitize(Array(t[(v + 1)...])))
        } else {
            p.target = strip(TextKit.digitize(t))
        }
        if let hint = t.reversed().first(where: { roleWords[$0] != nil }) { p.roleHint = roleWords[hint] }
        return p
    }

    /// Removes the lead and tail words: "to the issues page" gives "issues".
    static func strip(_ words: [String]) -> [String] {
        var w = words
        while let f = w.first, leadWords.contains(f), w.count > 1 { w.removeFirst() }
        while let l = w.last, tailWords.contains(l), w.count > 1 { w.removeLast() }
        return w
    }

    // MARK: - Score

    /// The numbers in a list of words, as digits.
    static func numbers(_ words: [String]) -> Set<String> { Set(TextKit.digitize(words).filter(TextKit.isNumber)) }

    /// True if the label is mostly a number: "2", "(+2)", "Page 12".
    static func mostlyNumber(_ label: String) -> Bool {
        let k = TextKit.key(label)
        guard !k.isEmpty else { return false }
        let digits = k.unicodeScalars.filter { $0.value >= 48 && $0.value <= 57 }.count
        return digits * 2 >= k.count
    }

    /// 1.0 is a full match. The larger of the whole-phrase similarity and the word cover.
    /// Numbers must match exactly: "382 comments" never matches "384 comments" (E2, section 5.6).
    static func score(_ target: [String], _ label: String) -> Double {
        guard !target.isEmpty else { return 0 }
        let labelWords = TextKit.digitize(TextKit.words(label))
        let want = numbers(target)
        let have = Set(labelWords.filter(TextKit.isNumber))
        if !want.isSubset(of: have) { return 0 }
        if mostlyNumber(label), !have.isSubset(of: want) { return 0 }
        let full = TextKit.similarity(target.joined(), labelWords.joined())
        guard !labelWords.isEmpty else { return full }
        var cover = 0.0
        for t in target {
            let best = labelWords.map { TextKit.similarity(t, $0) }.max() ?? 0
            if best >= 0.75 { cover += best }
        }
        cover /= Double(target.count)
        var content = labelWords.filter { !smallWords.contains($0) && !TextKit.isNumber($0) }
        if content.isEmpty { content = labelWords }
        let found = content.filter { l in target.contains { TextKit.similarity($0, l) >= 0.75 } }.count
        let precision = Double(found) / Double(content.count)
        // Two or more words that match a run of words in the label, in order: a name in a long chat row
        // ("Darshan Panya" in "user avatar Darshan Pania Verified account 1h ..."). The long label does not count against it.
        var run = 0.0
        if target.count >= 2, labelWords.count >= target.count {
            for start in 0...(labelWords.count - target.count) {
                let sims = target.indices.map { TextKit.similarity(target[$0], labelWords[start + $0]) }
                if sims.allSatisfy({ $0 >= 0.75 }) { run = max(run, 0.9 * sims.reduce(0, +) / Double(sims.count)) }
            }
        }
        return max(full, cover * (0.7 + 0.3 * precision), run)
    }

    /// The elements in screen order: top to bottom, then left to right.
    static func ordered(_ elements: [ScreenElement]) -> [ScreenElement] {
        elements.sorted { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }
    }

    /// The list for an ordinal: links in headings, else links with 4 or more words.
    /// A risky element is never a result: on Wikipedia, the fundraising banner is a long link.
    static func ordinalList(_ noun: String, _ all: [ScreenElement]) -> [ScreenElement] {
        let elements = ordered(all.filter { !$0.risky && !SafetyPolicy.isRisky($0) })
        switch noun {
        case "button": return elements.filter { kind($0) == "button" }
        case "tab": return elements.filter { kind($0) == "tab" }
        case "link": return elements.filter { kind($0) == "link" }
        default:
            let headed = elements.filter { kind($0) == "link" && $0.inHeading }
            if headed.count >= 2 { return headed }
            return elements.filter { kind($0) == "link" && TextKit.words($0.label).count >= 4 }
        }
    }

    // MARK: - Route

    static func decide(_ spoken: String, screen: ScreenSnapshot) -> RulesDecision {
        let p = parse(spoken)
        let elements = screen.elements.filter { kind($0) != nil }
        var options: [RouteOption] = []
        func done(_ intent: Intent, _ sure: Bool, _ exact: Bool, _ why: String) -> RulesDecision {
            RulesDecision(intent: intent, sure: sure, exact: exact, why: why, options: options)
        }

        switch p.kind {
        case .scroll:
            return done(.scroll(p.scroll ?? .down), true, true, "scroll words")
        case .back:
            return done(.back, true, true, "back words")
        case .type:
            let fields = elements.filter { kind($0) == "field" && !$0.risky }
            let ranked = fields.map { f -> (ScreenElement, Double) in
                let s = p.target.isEmpty ? (isSearchField(f) ? 1.0 : (f.role == "AXTextArea" ? 0.4 : 0.6)) : score(p.target, f.label)
                return (f, s)
            }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.y < $1.0.y }
            let text = p.text ?? ""
            for (f, s) in ranked.prefix(3) {
                options.append(RouteOption(intent: .typeInto(elementID: f.id, text: text),
                                           label: "Type the words into the field \"\(f.label)\"", score: s))
            }
            guard let top = ranked.first, top.1 >= 0.8, !text.isEmpty else {
                return done(.none, true, true, "no search field")
            }
            return done(.typeInto(elementID: top.0.id, text: text), true, true, "search field")
        case .ordinal:
            let list = ordinalList(p.ordinalNoun ?? "result", elements)
            let n = p.ordinal ?? 1
            let index = n == -1 ? list.count - 1 : n - 1
            guard index >= 0, index < list.count else { return done(.none, true, true, "list too short (\(list.count))") }
            return done(.click(elementID: list[index].id), true, true, "\(p.ordinalNoun ?? "") \(n) of \(list.count)")
        case .press:
            break
        }

        // A lone number: a label that is that number ("2" in a page list), else the number that
        // "show numbers" put on the element (R-CL-3). The actions module gives element n the id "e<n>".
        if p.isCommand, p.target.count == 1, let n = Int(p.target[0]), n >= 0 {
            let same = elements.filter { mostlyNumber($0.label) && numbers(TextKit.words($0.label)) == [String(n)] }
            let shown = screen.elements.first { $0.id == "e\(n)" }
            let pick: ScreenElement? = same.first ?? shown
            if let e = pick {
                if e.risky || SafetyPolicy.isRisky(e) { return done(.none, true, true, "blocked: risky label \"\(e.label)\"") }
                let why = same.isEmpty ? "shown number \(n)" : "number label"
                return done(.click(elementID: e.id), same.count <= 1, true, why)
            }
        }

        // Press: score every element with a label.
        var scored: [(ScreenElement, Double)] = []
        for e in elements where !e.label.isEmpty {
            var s = score(p.target, e.label)
            if let hint = p.roleHint, hint == kind(e) { s += 0.05 }
            if s >= 0.3 { scored.append((e, s)) }
        }
        scored.sort { $0.1 != $1.1 ? $0.1 > $1.1 : ($0.0.y != $1.0.y ? $0.0.y < $1.0.y : $0.0.x < $1.0.x) }
        // The same label more than once: tell the copies apart for tier 2.
        var seen: [String: Int] = [:]
        for (e, s) in scored.prefix(shortListSize) where !(e.risky || SafetyPolicy.isRisky(e)) {
            let key = TextKit.key(e.label)
            seen[key, default: 0] += 1
            let copy = seen[key]! > 1 ? " (copy \(seen[key]!) on the page)" : ""
            options.append(RouteOption(intent: .click(elementID: e.id), label: "Click the \(kind(e) ?? "element") \"\(e.label)\"\(copy)",
                                       score: s))
        }
        options.append(RouteOption(intent: .scroll(.down), label: "Scroll down the page", score: 0))
        options.append(RouteOption(intent: .back, label: "Go back to the previous page", score: 0))

        guard let top = scored.first, top.1 >= noMatch else {
            return done(.none, true, true, p.isCommand ? "no label matches" : "no command word")
        }
        guard p.isCommand else { return done(.none, top.1 < strongMatch, false, "a label matches, but no command word") }
        let exact = TextKit.key(p.target.joined()) == TextKit.key(TextKit.digitize(TextKit.words(top.0.label)).joined())
        // A risky label needs the exact label from the owner (R-NV-5). A fuzzy match on a risky label does nothing.
        if top.0.risky || SafetyPolicy.isRisky(top.0) {
            if !exact { return done(.none, true, false, "blocked: risky label \"\(top.0.label)\"") }
        }
        let pick = Intent.click(elementID: top.0.id)
        // The next element with a different label, or the same label with a different address.
        let rival = scored.dropFirst().first { e in
            TextKit.key(e.0.label) != TextKit.key(top.0.label) || (e.0.url ?? "") != (top.0.url ?? "")
        }
        if top.1 >= strongMatch, rival == nil || rival!.1 <= top.1 - margin {
            return done(pick, true, exact, "label match")
        }
        return done(pick, false, exact, rival != nil && rival!.1 > top.1 - margin ? "two labels match" : "weak label match")
    }
}
