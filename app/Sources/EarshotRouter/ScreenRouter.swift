import EarshotCore
import Foundation

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
    /// All the words after the lead fillers, with numbers as digits. A menu title can start with a verb ("Select All").
    var words: [String] = []
    /// The first command word: "type", "search", "click", "focus" and so on.
    var verb: String?
    /// Ways to read the words as a text box and the text to type into it: "type hi into the notes box",
    /// "in notes type hi", "click notes and type hi". The router uses a split only if the box words match a text field well.
    var splits: [BoxSplit] = []
    /// True if the words make sense only with a box ("in notes type hi"): no box match gives no action.
    var splitOnly = false
}

/// One way to read a command as a text box and the text for it.
struct BoxSplit {
    let box: [String]
    let text: String
}

/// Voice clicks on the front window. Ported from probe WebRouter (E2, section 6.1). It knows no site.
/// It gets only the words and the elements of the screen. Numbers in a command must match exactly (E2, section 7).
enum ScreenRouter {
    static let fillers: Set<String> = Set(["hey", "ok", "okay", "earshot", "please", "can", "could", "you", "would", "now", "then",
                                           "just", "lets", "let", "us", "i", "want", "to", "need"]).union(TextKit.hesitations)
    static let pressVerbs: Set<String> = ["click", "press", "tap", "open", "select", "choose", "hit", "follow", "visit", "go",
                                          "show", "check", "toggle", "expand", "view", "take", "jump", "pick", "switch", "focus"]
    /// Words that end a box name before the text: "click notes and type hi".
    static let thenType: [[String]] = [["and", "type"], ["then", "type"], ["and", "enter"], ["and", "write"]]
    /// Words after "type" that stand for the text that comes later: "type a message in notes: hi".
    static let textStandIns: Set<String> = ["a", "the", "some", "message", "text", "this", "note"]
    /// Words before a window word at the end of a command: "on open Chrome window", "in this window".
    static let windowWords: Set<String> = ["window", "app", "application"]
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
    /// The score that a menu item needs when the owner says no verb. Above a sound match (0.82).
    static let noVerbMenuMatch = 0.9
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

    /// The message box: the one text area, else the text area that is clearly the largest (1.5 times the next).
    /// A one-line text field never counts: it can be a sign-in or form field. Nil if unsure.
    static func messageBox(_ fields: [ScreenElement]) -> ScreenElement? {
        let areas = fields.filter { $0.role == "AXTextArea" }
        if areas.count == 1 { return areas[0] }
        let sorted = areas.sorted { $0.w * $0.h > $1.w * $1.h }
        guard let top = sorted.first else { return nil }
        if let next = sorted.dropFirst().first, top.w * top.h < 1.5 * next.w * next.h { return nil }
        return top
    }

    static func isSearchField(_ e: ScreenElement) -> Bool {
        kind(e) == "field" && (e.subrole == "AXSearchField" || TextKit.normalize(e.label).contains("search"))
    }

    // MARK: - Parse

    static func parse(_ spoken: String) -> ScreenParse {
        var p = ScreenParse()
        var tokens = Tokens(joinThousands(spoken))
        var lead = 0
        while lead < tokens.count - 1, fillers.contains(tokens.words[lead]) { lead += 1 }
        tokens.dropFirst(lead)
        let t = tokens.words
        guard !t.isEmpty else { return p }
        p.words = TextKit.digitize(t)
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

        // "in <box> type X", "into <box> enter X".
        if ["in", "into", "on"].contains(t[0]),
           let k = t.indices.dropFirst(2).first(where: { t[$0] == "type" || t[$0] == "enter" }), k + 1 < t.count {
            p.kind = .type
            p.verb = t[k]
            p.isCommand = true
            p.text = tokens.raw((k + 1)..<t.count)
            p.splits = [BoxSplit(box: strip(TextKit.digitize(Array(t[1..<k]))), text: p.text ?? "")]
            p.splitOnly = true
            return p
        }

        // Type: "search for X", "look up X", "type X", "type X into Y".
        if let first = t.first, typeVerbs.contains(first), t.count >= 2 {
            var start = 1
            let end = t.count
            p.verb = first
            if first == "type" || first == "enter" {
                // "type X in/into <box>". The box must match a text field, else all the words are the text:
                // "type I'm in the meeting" types all of it.
                if let into = t.indices.dropFirst(2).last(where: { t[$0] == "into" || t[$0] == "in" }), into + 1 < t.count {
                    p.splits.append(BoxSplit(box: strip(TextKit.digitize(Array(t[(into + 1)...]))), text: tokens.raw(1..<into)))
                }
                // "type a message in <box>. <text>": the box part ends at a stop mark.
                var j = 1
                while j < t.count, textStandIns.contains(t[j]) { j += 1 }
                if j < t.count, ["in", "into", "and", "to", "on"].contains(t[j]),
                   let stop = tokens.stops.first(where: { $0 > j + 1 && $0 < t.count }) {
                    p.splits.append(BoxSplit(box: strip(TextKit.digitize(Array(t[(j + 1)..<stop]))), text: tokens.raw(stop..<t.count)))
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
        var verb: String?
        if let v = t.prefix(3).firstIndex(where: { pressVerbs.contains($0) }) {
            p.isCommand = true
            verb = t[v]
            p.verb = t[v]
            p.target = strip(TextKit.digitize(dropWindow(Array(t[(v + 1)...]))))
            // "click <box> and type X", "focus on <box> then type X".
            for pair in thenType {
                guard let a = t.indices.dropFirst(v + 2).first(where: { $0 + 1 < t.count && Array(t[$0...($0 + 1)]) == pair }),
                      a + 2 < t.count else { continue }
                p.splits.append(BoxSplit(box: strip(TextKit.digitize(Array(t[(v + 1)..<a]))), text: tokens.raw((a + 2)..<t.count)))
            }
        } else {
            p.target = strip(TextKit.digitize(dropWindow(t)))
        }
        if let hint = t.reversed().first(where: { roleWords[$0] != nil }) { p.roleHint = roleWords[hint] }
        // "switch to <title>" asks for a tab.
        if verb == "switch", p.roleHint == nil { p.roleHint = "tab" }
        return p
    }

    /// Removes a trailing "on <words> window": "home on open Chrome window" gives "home".
    /// The app part is not known here. The command router removes "on <app>" for the apps in the app table.
    static func dropWindow(_ words: [String]) -> [String] {
        guard let last = words.last, windowWords.contains(last), words.count >= 3 else { return words }
        let from = max(1, words.count - 5)
        guard let on = words[from..<(words.count - 1)].lastIndex(where: { $0 == "on" || $0 == "in" }) else { return words }
        return Array(words[..<on])
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
    /// A number counts only as a whole number: "10" is not in "100", and "10,000" is one number.
    /// A word of letters and digits gives its digit runs: "gw8" gives "8".
    static func numbers(_ words: [String]) -> Set<String> { digitRuns(TextKit.digitize(words)) }

    /// The digit runs of words that are already digitized.
    static func digitRuns(_ words: [String]) -> Set<String> {
        var out = Set<String>()
        for w in words where w.unicodeScalars.contains(where: { $0.value >= 48 && $0.value <= 57 }) {
            if TextKit.isNumber(w) { out.insert(w); continue }
            var run = ""
            for c in w.unicodeScalars {
                if c.value >= 48 && c.value <= 57 { run.unicodeScalars.append(c) } else if !run.isEmpty { out.insert(run); run = "" }
            }
            if !run.isEmpty { out.insert(run) }
        }
        return out
    }

    /// Removes the comma in a number with thousands: "10,000" gives "10000", so it stays one number.
    static func joinThousands(_ text: String) -> String {
        guard text.contains(",") else { return text }
        return text.replacingOccurrences(of: #"(?<=\d),(?=\d{3}(?!\d))"#, with: "", options: .regularExpression)
    }

    /// Joins a short letter group and the number after it: "gw 8" gives "gw8", as in the label "Review GW8".
    static func joinLetterNumber(_ words: [String]) -> [String] {
        var out: [String] = []
        for w in words {
            if TextKit.isNumber(w), let last = out.last, (1...3).contains(last.count), !smallWords.contains(last),
               last.unicodeScalars.allSatisfy({ $0.value >= 97 && $0.value <= 122 }) {
                out[out.count - 1] = last + w
            } else {
                out.append(w)
            }
        }
        return out
    }

    /// True if the label is mostly a number: "2", "(+2)", "Page 12".
    static func mostlyNumber(_ label: String) -> Bool {
        let k = TextKit.key(label)
        guard !k.isEmpty else { return false }
        let digits = k.unicodeScalars.filter { $0.value >= 48 && $0.value <= 57 }.count
        return digits * 2 >= k.count
    }

    /// The label without a status part at the end: "Home (New unread posts)" gives "Home",
    /// "Pull requests (1)" gives "Pull requests", "Chats, 44" gives "Chats". Nil if the label has no status part.
    static func statusFree(_ label: String) -> String? {
        var s = label.trimmingCharacters(in: .whitespaces)
        // Fast path: a status part ends with ")" or a digit. Most labels do not, and a regular expression is slow.
        guard let last = s.last, last == ")" || last.isNumber else { return nil }
        var changed = false
        while true {
            if let r = s.range(of: #"\s*\([^()]*\)$"#, options: .regularExpression) { s.removeSubrange(r) }
            else if let r = s.range(of: #"\s*[,·]\s*\d+$"#, options: .regularExpression) { s.removeSubrange(r) }
            else { break }
            changed = true
            s = s.trimmingCharacters(in: .whitespaces)
        }
        return changed && !TextKit.key(s).isEmpty ? s : nil
    }

    /// The match data of one label. The router makes it one time for each label and keeps it in a cache,
    /// so a command does not parse the same labels again (a menu bar can have 1000 items).
    struct LabelInfo: Sendable {
        /// The words of the label, with numbers as digits.
        let words: [String]
        /// The words of the label with no status part, or nil if the label has no status part.
        let bare: [String]?
        /// Letters and digits only, for the label and for the label with no status part.
        let keys: [String]
        /// The sound codes of the keys that have 3 or more letters.
        let codes: [String]
        /// The sound code of each word of `bare ?? words`, for the "maybe" note.
        let wordCodes: [String]
        let numbers: Set<String>
        let mostlyNumber: Bool
        let bareMostlyNumber: Bool

        init(_ raw: String) {
            let label = ScreenRouter.joinThousands(raw)
            words = TextKit.digitize(TextKit.words(label))
            let free = ScreenRouter.statusFree(label)
            bare = free.map { TextKit.digitize(TextKit.words($0)) }
            keys = [words.joined()] + (bare.map { [$0.joined()] } ?? [])
            codes = keys.filter { $0.count >= 3 }.map(SoundCode.code)
            wordCodes = (bare ?? words).map { $0.count >= 3 ? SoundCode.code($0) : "" }
            numbers = ScreenRouter.digitRuns(words)
            mostlyNumber = ScreenRouter.mostlyNumber(label)
            bareMostlyNumber = free.map(ScreenRouter.mostlyNumber) ?? false
        }
    }

    /// The words that the owner said, with their key and sound code. The router makes it one time for each command.
    struct Said {
        let words: [String]
        let key: String
        let code: String
        let numbers: Set<String>
        /// The words with a short letter group and its number joined ("gw 8" gives "gw8"), or nil if nothing joins.
        let joined: [String]?
        /// The words with each UI word changed to its other word ("refresh" gives "reload"), or nil if none changes.
        let swapped: [[String]]

        init(_ words: [String]) {
            self.words = words
            swapped = UIWords.swaps(words)
            let j = ScreenRouter.joinLetterNumber(words)
            joined = j == words ? nil : j
            key = TextKit.key(words.joined())
            code = key.count >= 3 ? SoundCode.code(key) : ""
            numbers = ScreenRouter.numbers(words)
        }
    }

    /// The label cache. The labels of the front window and of its menus repeat from one command to the next.
    final class LabelCache: @unchecked Sendable {
        private let lock = NSLock()
        private var infos: [String: LabelInfo] = [:]
        static let limit = 20_000

        func info(_ label: String) -> LabelInfo {
            lock.lock()
            if let i = infos[label] { lock.unlock(); return i }
            lock.unlock()
            let i = LabelInfo(label)
            lock.lock()
            if infos.count >= Self.limit { infos.removeAll(keepingCapacity: true) }
            infos[label] = i
            lock.unlock()
            return i
        }
    }

    static let cache = LabelCache()

    static func info(_ label: String) -> LabelInfo { cache.info(label) }

    /// The match keys of a label: letters and digits only, for the label and for the label with no status part.
    static func keys(_ label: String) -> [String] { info(label).keys }

    /// 1.0 is a full match. The largest of: the score for the label, the score for the label with no status part
    /// ("Home (New unread posts)" for "home"), and a sound match.
    static func score(_ target: [String], _ label: String) -> Double {
        score(Said(target), info(label))
    }

    static func score(_ said: Said, _ label: LabelInfo) -> Double {
        guard !said.words.isEmpty else { return 0 }
        // Numbers must match exactly: "382 comments" never matches "384 comments" (E2, section 5.6).
        guard said.numbers.isSubset(of: label.numbers) else { return 0 }
        // Letters and digits only: "shad CN/UI" is "shadcn/ui". This is a full match, so stop here.
        if label.keys.contains(said.key), !(label.mostlyNumber && !label.numbers.isSubset(of: said.numbers)) { return 1 }
        var s = wordScore(said.words, label.words, mostlyNumber: label.mostlyNumber)
        if s < 1, let bare = label.bare { s = max(s, wordScore(said.words, bare, mostlyNumber: label.bareMostlyNumber)) }
        if s < 1, let j = said.joined {
            s = max(s, wordScore(j, label.words, mostlyNumber: label.mostlyNumber))
            if let bare = label.bare { s = max(s, wordScore(j, bare, mostlyNumber: label.bareMostlyNumber)) }
        }
        // Another common word for the same UI action: "refresh" for the button "Reload". It is a fuzzy match, never exact.
        if s < UIWords.score {
            for w in said.swapped {
                let alt = Said(w)
                if label.keys.contains(alt.key) { s = UIWords.score; break }
                s = max(s, min(UIWords.score, wordScore(w, label.words, mostlyNumber: label.mostlyNumber)))
            }
        }
        // A sound match: speech to text writes "clawed" for "Claude". It is never an exact match (R-NV-5).
        if s < soundMatch, let first = said.code.first {
            for c in label.codes where c.first == first && c == said.code { s = soundMatch; break }
        }
        return s
    }

    /// The score of a label that only a sound match gives.
    static let soundMatch = 0.82

    /// True if a word of the label is close to a word that the owner said: the same word, a near spelling,
    /// or a near sound ("chart" for "chat"). A "maybe" for the owner when no label matches well.
    static func near(_ target: [String], _ label: String) -> Bool {
        let said = target.filter { $0.count >= 3 && !smallWords.contains($0) && !TextKit.isNumber($0) }
        guard !said.isEmpty else { return false }
        let l = info(label)
        // A label with other numbers is not near: "plan gw 10" is not "Player Who Returned 10,000 Years Later".
        guard numbers(target).isSubset(of: l.numbers) else { return false }
        let words = l.bare ?? l.words
        return said.contains { t in
            let tc = SoundCode.code(t)
            return words.indices.contains { i in
                let w = words[i]
                if w == t || TextKit.similarity(t, w) >= 0.75 { return true }
                let wc = l.wordCodes[i]
                guard !wc.isEmpty, wc.first == tc.first else { return false }
                return TextKit.similarity(tc, wc) >= 0.75
            }
        }
    }

    /// The word score of a label, as before the match keys: whole phrase, word cover and a run of words.
    static func wordScore(_ target: [String], _ labelWords: [String], mostlyNumber: Bool) -> Double {
        let want = digitRuns(target)
        let have = digitRuns(labelWords)
        if !want.isSubset(of: have) { return 0 }
        if mostlyNumber, !have.isSubset(of: want) { return 0 }
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
        // ("Prakash Iyyer" in "user avatar Prakash Iyer Verified account 1h ..."). The long label does not count against it.
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

        // A text box and the text for it, if the box words match a text field well.
        if !p.splits.isEmpty {
            let fields = elements.filter { kind($0) == "field" && !$0.risky }
            for split in p.splits where !split.box.isEmpty && !split.text.isEmpty {
                let said = Said(split.box)
                let ranked = fields.map { ($0, score(said, info($0.label))) }.sorted { $0.1 > $1.1 }
                guard let top = ranked.first, top.1 >= strongMatch else { continue }
                if let next = ranked.dropFirst().first, next.1 > top.1 - margin { continue }
                options.append(RouteOption(intent: .typeInto(elementID: top.0.id, text: split.text),
                                           label: "Type the words into the field \"\(top.0.label)\"", score: top.1))
                let exact = info(top.0.label).keys.contains(said.key)
                return done(.typeInto(elementID: top.0.id, text: split.text), true, exact, "text box \"\(top.0.label)\"")
            }
            if p.splitOnly { return done(.none, true, true, "no text box matches") }
        }

        switch p.kind {
        case .scroll:
            return done(.scroll(p.scroll ?? .down), true, true, "scroll words")
        case .back:
            return done(.back, true, true, "back words")
        case .type:
            // "type X" with no box name: the focused text field. "search for X" still prefers a search field.
            if p.target.isEmpty, p.verb == "type" || p.verb == "enter", screen.focusedID != nil, let text = p.text, !text.isEmpty {
                return done(.typeText(text), true, true, "focused text field")
            }
            let fields = elements.filter { kind($0) == "field" && !$0.risky }
            // "type X" and "enter X" with no box name and no focus: the message box, not a search field.
            // The message box is the one text area, else the clearly largest text area. "search for X" keeps the search field.
            if p.target.isEmpty, p.verb == "type" || p.verb == "enter", let text = p.text, !text.isEmpty,
               let box = messageBox(fields.filter { !isSearchField($0) }) {
                options.append(RouteOption(intent: .typeInto(elementID: box.id, text: text),
                                           label: "Type the words into the field \"\(box.label)\"", score: 1))
                return done(.typeInto(elementID: box.id, text: text), true, true, "message box")
            }
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
        let isMenu = MenuElements.isMenu
        let said = Said(p.target), saidAll = Said(p.words)
        for e in elements where !e.label.isEmpty {
            let label = info(e.label)
            var s = score(said, label)
            if isMenu(e) {
                // A menu title can hold the verb: "select all" is the item "Select All". A match on all the words
                // wins by the margin over a full match on the words after the verb (the link "All").
                let whole = score(saidAll, label)
                if whole >= 1 { s = max(s, 1 + margin) } else { s = max(s, whole) }
            }
            if let hint = p.roleHint, hint == kind(e) || (hint == "tab" && e.role == "AXRadioButton") { s += 0.05 }
            if s >= 0.3 { scored.append((e, s)) }
        }
        // Same score: "click copy" prefers the element on the screen to the menu item.
        scored.sort {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if isMenu($0.0) != isMenu($1.0) { return !isMenu($0.0) }
            return $0.0.y != $1.0.y ? $0.0.y < $1.0.y : $0.0.x < $1.0.x
        }
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

        guard let first = scored.first, first.1 >= noMatch else {
            // No label matches well. If a label holds a word near a spoken word, the owner can see it: not a sure "none".
            let nearby = p.isCommand ? elements.filter({ !$0.label.isEmpty && !($0.risky || SafetyPolicy.isRisky($0))
                && ScreenRouter.near(p.target, $0.label) }).map { ($0, score(said, info($0.label))) } : []
            if let best = nearby.max(by: { $0.1 < $1.1 }) {
                let maybe = best.0, maybeScore = best.1
                if !options.contains(where: { $0.intent == .click(elementID: maybe.id) }) {
                    options.insert(RouteOption(intent: .click(elementID: maybe.id), label: "Click the \(kind(maybe) ?? "element") \"\(maybe.label)\"",
                                               score: maybeScore), at: 0)
                }
                return done(.none, false, false, "no label matches; maybe \"\(maybe.label)\"")
            }
            return done(.none, true, true, p.isCommand ? "no label matches" : "no command word")
        }
        // With no verb, only a menu item can match, and only a near-exact match: "copy", "export", "mute".
        // A sound match or a fuzzy match on one word is not enough: "type" sounds like the item "Top".
        let pool = p.isCommand ? scored : scored.filter { isMenu($0.0) }
        guard let top = pool.first, p.isCommand || top.1 >= noVerbMenuMatch else {
            return done(.none, first.1 < strongMatch, false, "a label matches, but no command word")
        }
        // Exact: the spoken words are the label, or the label with no status part, on letters and digits only.
        let labelKeys = keys(top.0.label)
        let exact = labelKeys.contains(TextKit.key(p.target.joined())) || (isMenu(top.0) && labelKeys.contains(TextKit.key(p.words.joined())))
        // A risky label needs the exact label from the owner (R-NV-5). A fuzzy match on a risky label does nothing.
        if top.0.risky || SafetyPolicy.isRisky(top.0) {
            if !exact { return done(.none, true, false, "blocked: risky label \"\(top.0.label)\"") }
        }
        let pick = Intent.click(elementID: top.0.id)
        // The next element with a different label, or the same label with a different address.
        let rival = pool.dropFirst().first { e in
            TextKit.key(e.0.label) != TextKit.key(top.0.label) || (e.0.url ?? "") != (top.0.url ?? "")
        }
        if top.1 >= strongMatch, rival == nil || rival!.1 <= top.1 - margin {
            return done(pick, true, exact, isMenu(top.0) ? "menu item" : "label match")
        }
        return done(pick, false, exact, rival != nil && rival!.1 > top.1 - margin ? "two labels match" : "weak label match")
    }
}
