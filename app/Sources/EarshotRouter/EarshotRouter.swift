// T2 owns this module. See docs/BUILD-PLAN.md.
import EarshotCore
import Foundation

/// The command router (R-SP-2). Rules and fuzzy match first, on the Mac, in a few ms.
/// Tier 2 runs only when the rules are unsure, only if the owner turned it on, and only within its budget.
/// There is no agent loop: one tier-2 call for each command at most.
public struct CommandRouter: Router {
    /// Nil means tier 2 is off: all decisions stay on the Mac (R-MD-1, D-9). This is the default.
    public var tier2: Tier2Chooser?
    /// The longest wait for tier 2. After it, the rules answer stays.
    public var tier2BudgetMs: Int

    /// Confidence of a sure rules answer.
    public static let sureConfidence = 0.9
    /// Confidence of a tier-2 answer.
    public static let tier2Confidence = 0.8
    /// Confidence of an unsure rules answer. It is below SafetyPolicy.minimumConfidence, so the app shows it and does nothing.
    public static let unsureConfidence = 0.5
    /// Confidence of an unsure "open the app" answer. Opening an app can be undone, so the app does it.
    public static let unsureOpenAppConfidence = 0.65

    public init(tier2: Tier2Chooser? = nil, tier2BudgetMs: Int = 1000) {
        self.tier2 = tier2
        self.tier2BudgetMs = tier2BudgetMs
    }

    /// The router for the owner's settings. Tier 2 is on only if `settings.tier2` is not "off" and a key exists.
    public init(settings: EarshotSettings, jevKey: String?) {
        self.init(tier2: Tier2Factory.make(settings, jevKey: jevKey), tier2BudgetMs: settings.tier2BudgetMs)
    }

    public func route(_ text: String, context: RouteContext) async -> RouteResult {
        let t0 = DispatchTime.now().uptimeNanoseconds
        func ms() -> Double { Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000 }
        let d = Self.rules(text, context: context)
        let alternatives = { (chosen: Intent) in Array(d.options.map(\.intent).filter { $0 != chosen }.prefix(3)) }

        if !d.sure, let tier2, !d.options.isEmpty {
            let labels = d.options.map(\.label)
            if let i = await Self.ask(tier2, text, labels, budgetMs: tier2BudgetMs), i >= 0, i < d.options.count {
                let intent = d.options[i].intent
                return RouteResult(intent: intent, confidence: Self.tier2Confidence, tier: .jev, ms: ms(),
                                   why: "tier 2: \(d.why)", alternatives: alternatives(intent),
                                   sendAfter: d.sendAfter && Self.hasText(intent))
            }
        }
        return RouteResult(intent: d.intent, confidence: Self.confidence(d), tier: Self.tier(d), ms: ms(),
                           why: d.why, alternatives: alternatives(d.intent), awaitsText: d.awaitsText,
                           sendAfter: d.sendAfter && Self.hasText(d.intent))
    }

    /// The words that no known name explains, and the chat app that the owner named, if any.
    /// The app can give them to the app's own search (NameFinder.search) and then route again with the new names (E1, section 6).
    public static func heardName(_ text: String, context: RouteContext) -> (name: String, appID: String?)? {
        let d = ChatRouter.decide(text, apps: context.apps, names: context.names, frontBundleID: context.frontBundleID)
        guard let n = d.heardName else { return nil }
        return (n, d.heardApp)
    }

    /// True if the words ask for a press on the screen ("click X", "open the X tab"), by the router's own verb parse.
    /// Not for typing, scrolling, back or an ordinal. The screenshot fallback runs only for a press (D-10).
    public static func isPress(_ text: String) -> Bool {
        let p = ScreenRouter.parse(text)
        return p.isCommand && p.kind == .press && !p.target.isEmpty
    }

    /// The label words that the owner said for a click, for example "send" in "click the send button".
    /// The app gives them to SafetyPolicy.mayPress with the tier and the input mode (R-NV-5).
    public static func spokenTarget(_ text: String) -> String {
        ScreenRouter.parse(text).target.joined(separator: " ")
    }

    // MARK: - Rules

    static let sendPhrases: Set<String> = ["send", "send it", "send that", "send this", "send now", "send it now",
                                           "send the message", "send message", "send the text", "now send", "and send"]
    static let showNumbers: Set<String> = ["show numbers", "show the numbers", "numbers", "show me numbers", "show me the numbers",
                                           "number the elements", "show labels"]
    static let hideNumbers: Set<String> = ["hide numbers", "hide the numbers", "clear numbers", "remove numbers",
                                           "remove the numbers", "no numbers", "stop numbers", "hide labels"]
    /// Verbs that ask for a press on the screen, not for a chat.
    static let pressOnly: Set<String> = ["click", "press", "tap", "select", "choose", "hit", "follow", "visit", "toggle",
                                         "expand", "check", "pick", "focus"]
    static let typeFirst: Set<String> = ["search", "look", "type", "enter"]
    static let fillers: Set<String> = Set(["hey", "ok", "okay", "earshot", "please", "now", "then", "and"]).union(TextKit.hesitations)

    // MARK: - Command words

    /// Words that start a command.
    static let commandStarts: Set<String> = ScreenRouter.pressVerbs.union(ScreenRouter.typeVerbs).union(ChatRouter.commandVerbs)
        .union(pressOnly).union(["scroll", "back", "focus", "in", "into"])

    /// True if the words hold a command word: a verb such as "click", "type" or "message", an app name at the start,
    /// "send", "show numbers", a web address, or a later sentence that starts with a command word.
    /// The app uses it for dictation: plain words with no command word in a focused text field (hold key only).
    public static func hasCommandWord(_ text: String, context: RouteContext) -> Bool {
        if PluginRouter.match(text, plugins: context.plugins, apps: context.apps) != nil { return true }
        return sentences(text).contains { isCommandSentence($0, apps: context.apps) }
    }

    /// True if the FIRST sentence is a command. Dictation after "type" uses it: a command word later in the text,
    /// for example an app name, is text (live test: a dictated sentence that named "earshot" opened a Slack channel).
    public static func startsWithCommand(_ text: String, context: RouteContext) -> Bool {
        if PluginRouter.match(text, plugins: context.plugins, apps: context.apps) != nil { return true }
        return sentences(text).first.map { isCommandSentence($0, apps: context.apps) } ?? false
    }

    /// The sentences of the words, split after ".", "!", "?" or "…" and a space.
    static func sentences(_ text: String) -> [Substring] {
        var out: [Substring] = []
        var start = text.startIndex
        var i = text.startIndex
        while i < text.endIndex {
            let next = text.index(after: i)
            if ".!?…".contains(text[i]), next < text.endIndex, text[next].isWhitespace {
                out.append(text[start..<next])
                start = next
            }
            i = next
        }
        out.append(text[start...])
        return out.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// True if one sentence is a command: a command word in its first three words (after fillers), an app name
    /// at the start, or a fixed phrase (send, show numbers, a web address).
    static func isCommandSentence<S: StringProtocol>(_ sentence: S, apps: [AppEntry]) -> Bool {
        let text = String(sentence)
        var words = TextKit.words(text)
        while let f = words.first, fillers.contains(f) || ScreenRouter.fillers.contains(f), words.count > 1 { words.removeFirst() }
        // "here at least open Slack" (the wake phrase heard wrong), "go ahead and click login".
        for lead in [["here", "at", "least"], ["at", "least"], ["go", "ahead"]] where words.count > lead.count && words.starts(with: lead) {
            words.removeFirst(lead.count)
            while let f = words.first, fillers.contains(f) || ScreenRouter.fillers.contains(f), words.count > 1 { words.removeFirst() }
        }
        guard !words.isEmpty else { return false }
        let phrase = words.joined(separator: " ")
        if sendPhrases.contains(phrase) || showNumbers.contains(phrase) || hideNumbers.contains(phrase) { return true }
        if keyDecision(words) != nil { return true }
        if words.prefix(3).contains(where: { commandStarts.contains($0) && $0 != "in" && $0 != "into" }) { return true }
        if ["in", "into"].contains(words[0]), words.contains("type") || words.contains("enter") { return true }
        if WebAddress.parse(text) != nil { return true }
        let kind = ScreenRouter.parse(text).kind
        if kind == .scroll || kind == .back || kind == .ordinal { return true }
        // An app name at the start: "Slack me, running late", "Messages Ravi".
        for span in 1...min(3, words.count) where exactApp(words[0..<span].joined(), apps) != nil { return true }
        return false
    }

    /// The words from the first command sentence on. If the first sentence is a command, all the words.
    /// "Not a useful feature. Click on notes and type hi." gives "Click on notes and type hi."
    static func fromCommandSentence(_ text: String, apps: [AppEntry]) -> String {
        let parts = sentences(text)
        guard parts.count > 1, !isCommandSentence(parts[0], apps: apps),
              let k = parts.indices.dropFirst().first(where: { isCommandSentence(parts[$0], apps: apps) }) else { return text }
        return String(text[parts[k].startIndex...]).trimmingCharacters(in: .whitespaces)
    }

    /// The rules answer, with no tier 2. Synchronous and on the Mac.
    /// Words at the start that are not part of the command: "Yeah, let's open the Slack" gives "open the Slack".
    static let leadFillers: Set<String> = fillers.union(["yeah", "yep", "yes", "lets", "let", "us", "alright", "well",
                                                         "hey", "can", "could", "you", "would", "actually", "basically",
                                                         "just", "i", "want", "wanna", "need", "to"])

    /// The raw words with the lead fillers removed. Case and punctuation stay.
    static func dropLeadFillers(_ text: String) -> String {
        let tokens = Tokens(text)
        var lead = 0
        func isFiller(_ i: Int) -> Bool {
            let w = tokens.words[i]
            // "I message" is the app name iMessage, heard as two words (PR #24). Keep it.
            if w == "i", tokens.words[i + 1] == "message" { return false }
            if leadFillers.contains(w) { return true }
            // "Here" at the very start is most often the end of a wake phrase ("hey atlas" heard as "Here").
            if i == 0, w == "here" { return true }
            // "right" is a filler, but not in "right click" or "right arrow" (a spoken key, I-34).
            if w == "right", !["click", "arrow"].contains(tokens.words[i + 1]) { return true }
            // "here at least" at the start is most often the wake phrase "hey atlas" (activity records, 2026-11-03).
            if i <= 1, w == "at", tokens.words[i + 1] == "least" { return true }
            if (1...2).contains(i), w == "least", tokens.words[i - 1] == "at" { return true }
            // "go ahead and click login": "go ahead" is not the verb "go".
            if w == "go", tokens.words[i + 1] == "ahead" { return true }
            if i >= 1, w == "ahead", tokens.words[i - 1] == "go" { return true }
            return false
        }
        while lead < tokens.count - 1, isFiller(lead) { lead += 1 }
        return lead == 0 ? text : tokens.raw(lead..<tokens.count)
    }

    /// Words that can follow a bare command word: "click on", "go to". A second command word is a target: "click chat".
    static let bareWords: Set<String> = ["to", "on", "the", "in", "into", "a"]

    // MARK: - A send phrase after the text

    /// The words with a trailing send phrase removed: "type see you soon and send" gives "type see you soon".
    /// The phrase needs "and", "then" or a comma before "send", so the text "I will send it" stays whole,
    /// and "sender" is not "send". Nil if there is no such phrase, or if no words are left.
    public static func withoutTrailingSend(_ text: String) -> String? {
        let pattern = #"(?i)(\s*[,;]\s*|\s+)(?:(?:and|then|and then)\s+)send(?:\s+(?:it|this|that))?(?:\s+now)?[\s.!]*$|\s*[,;]\s*send(?:\s+(?:it|this|that))?(?:\s+now)?[\s.!]*$"#
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        let rest = String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        return TextKit.words(rest).isEmpty ? nil : rest
    }

    /// True for an intent that carries text: typeText, typeInto and openChat with text.
    static func hasText(_ intent: Intent) -> Bool {
        switch intent {
        case .typeText(let t): return !t.isEmpty
        case .typeInto(_, let t): return !t.isEmpty
        case .openChat(_, _, let t): return !(t ?? "").isEmpty
        default: return false
        }
    }

    /// The rules answer. A trailing send phrase is never part of the text: the router routes the words without it,
    /// and if the answer carries text, it sets sendAfter. Else it routes all the words as before.
    static func rules(_ spoken: String, context: RouteContext) -> RulesDecision {
        if let rest = withoutTrailingSend(spoken) {
            var d = rulesBody(rest, context: context)
            if hasText(d.intent) || d.options.contains(where: { hasText($0.intent) }) {
                d.sendAfter = true
                return d
            }
        }
        return rulesBody(spoken, context: context)
    }

    static func rulesBody(_ spoken: String, context: RouteContext) -> RulesDecision {
        // A plugin lead (tier 0), on all the words: the words after it are text for the plugin, also a later
        // sentence (R-PL-2). A lead never starts with a core command word or an app name, so a core command still wins (R-PL-4).
        if let d = PluginRouter.decide(spoken, context: context) { return d }
        let text = dropLeadFillers(fromCommandSentence(spoken, apps: context.apps))
        var words = TextKit.words(text)
        while let f = words.first, fillers.contains(f), words.count > 1 { words.removeFirst() }
        while let l = words.last, ["please", "now"].contains(l), words.count > 1, words != ["send", "now"] { words.removeLast() }
        let phrase = words.joined(separator: " ")
        guard !words.isEmpty, !(words.count == 1 && fillers.contains(words[0])) else {
            return RulesDecision(intent: .none, sure: true, exact: true, why: "no words", options: [])
        }

        // Only an explicit spoken "send" makes a send intent (R-NV-5). "Send Ravi a message" opens a chat.
        if sendPhrases.contains(phrase) {
            return RulesDecision(intent: .send, sure: true, exact: true, why: "send words", options: [])
        }
        if showNumbers.contains(phrase) {
            return RulesDecision(intent: .showNumbers, sure: true, exact: true, why: "show numbers", options: [])
        }
        if hideNumbers.contains(phrase) {
            return RulesDecision(intent: .hideNumbers, sure: true, exact: true, why: "hide numbers", options: [])
        }
        // Spoken keys and "undo that" (I-34, D-13).
        if let d = keyDecision(words) { return d }

        // A bare command word never matches a target by sound or a fuzzy match: "type." once pressed the menu item "Top".
        // A bare "type" tells the app that the next turn is the text (awaitsText).
        if words.count <= 2, commandStarts.contains(words[0]), words.dropFirst().allSatisfy({ bareWords.contains($0) }),
           ![.scroll, .back].contains(ScreenRouter.parse(text).kind) {
            if words == ["type"] {
                var d = RulesDecision(intent: .none, sure: true, exact: true, why: "type with no text", options: [])
                d.awaitsText = true
                return d
            }
            return RulesDecision(intent: .none, sure: true, exact: true, why: "\(phrase) with no target", options: [])
        }

        // A screen command for one app: "On Chrome, click Chat", "open notifications on Chrome", "Chrome, open settings".
        for hit in [appPrefix(text, apps: context.apps), appSuffix(text, apps: context.apps), appComma(text, apps: context.apps)] {
            if let hit, let d = screenFor(hit.0, hit.1, context: context) { return d }
        }

        // "open the shadcn/ui tab", "go to the FPL Guru tab": a press on a tab of the front window.
        // "switch to <title>" with no word "tab" goes to the chat rules first, so "switch to Slack" opens the app.
        let tabParse = ScreenRouter.parse(text)
        if let screen = context.screen, words.contains("tab"), tabParse.isCommand,
           ["open", "go", "switch"].contains(words.first ?? "") {
            let d = ScreenRouter.decide(text, screen: screen)
            if d.intent != .none { return d }
        }

        // "open hn.com", "go to news dot ycombinator dot com", "Openhn.com" (R-NV-7).
        if let address = WebAddress.parse(text) {
            return RulesDecision(intent: .openURL(address), sure: true, exact: true, why: "web address", options: [])
        }

        let parse = ScreenRouter.parse(text)
        if parse.kind == .scroll { return RulesDecision(intent: .scroll(parse.scroll ?? .down), sure: true, exact: true, why: "scroll words", options: []) }
        if parse.kind == .back { return RulesDecision(intent: .back, sure: true, exact: true, why: "back words", options: []) }

        let first = words.first ?? ""
        let wantsScreen = pressOnly.contains(first) || typeFirst.contains(first) || parse.kind == .ordinal || parse.kind == .type
        if wantsScreen {
            if let screen = context.screen { return ScreenRouter.decide(text, screen: screen) }
            if first == "type", parse.kind == .type, let t = parse.text, !t.isEmpty, parse.target.isEmpty {
                return RulesDecision(intent: .typeText(t), sure: true, exact: true, why: "type words, no screen", options: [])
            }
        }

        let chat = ChatRouter.decide(text, apps: context.apps, names: context.names, frontBundleID: context.frontBundleID)
        if chat.sure && chat.intent != .none { return chat }
        // "Open Cloud" for "Open Claude": an app name by sound, before a fuzzy label or menu item (R-MT-1).
        if let app = appBySound(words, apps: context.apps, screen: context.screen) {
            return RulesDecision(intent: .openApp(appID: app.id), sure: true, exact: false, why: "app name by sound",
                                 options: chat.options)
        }
        if let screen = context.screen {
            var web = ScreenRouter.decide(text, screen: screen)
            if web.intent != .none || (!chat.sure && chat.intent == .none && web.options.contains { $0.score > 0 }) {
                if chat.intent != .none { web.options += chat.options }
                return web
            }
            if chat.intent != .none {
                var c = chat
                c.options += web.options.filter { $0.score > 0 }
                return c
            }
        }
        return chat
    }

    /// A leading "on <app>" or "in <app>": the app, and the raw words after it. "On Chrome, click Chat" gives Chrome
    /// and "click Chat". Only approved and enabled rows count, and the app name must match exactly (R-MT-1).
    static func appPrefix(_ text: String, apps: [AppEntry]) -> (AppEntry, String)? {
        var tokens = Tokens(text)
        var lead = 0
        while lead < tokens.count, fillers.contains(tokens.words[lead]) { lead += 1 }
        tokens.dropFirst(lead)
        let w = tokens.words
        guard w.count >= 3, ["on", "in"].contains(w[0]) else { return nil }
        for span in stride(from: min(3, w.count - 2), through: 1, by: -1) {
            let phrase = w[1...span].joined()
            for app in apps where app.approved && app.enabled {
                let names = (app.aliases + [app.name]).map(TextKit.key)
                if names.contains(phrase) { return (app, tokens.raw((span + 1)..<w.count)) }
            }
        }
        return nil
    }

    /// Words between "on" and the app name, and after the app name, that are not part of the name:
    /// "on the open Chrome window", "in this Chrome tab".
    static let appBefore: Set<String> = ["the", "open", "this", "my", "current"]
    static let appAfter: Set<String> = ["window", "tab", "page", "app", "application"]

    /// A trailing "on <app>" or "in <app>": the app, and the raw words before it. "open notifications on Chrome",
    /// "click home on open Chrome window".
    static func appSuffix(_ text: String, apps: [AppEntry]) -> (AppEntry, String)? {
        var tokens = Tokens(text)
        var lead = 0
        while lead < tokens.count, fillers.contains(tokens.words[lead]) { lead += 1 }
        tokens.dropFirst(lead)
        let w = tokens.words
        var n = w.count
        if n >= 4, appAfter.contains(w[n - 1]) { n -= 1 }
        guard n >= 3 else { return nil }
        for span in stride(from: min(3, n - 2), through: 1, by: -1) {
            guard let app = exactApp(w[(n - span)..<n].joined(), apps) else { continue }
            var on = n - span - 1
            while on >= 2, appBefore.contains(w[on]) { on -= 1 }
            if on >= 1, ["on", "in"].contains(w[on]) { return (app, tokens.raw(0..<on)) }
        }
        return nil
    }

    /// A leading "<app>," with a comma: the app, and the raw words after it. "Chrome, open settings".
    static func appComma(_ text: String, apps: [AppEntry]) -> (AppEntry, String)? {
        var tokens = Tokens(text)
        var lead = 0
        while lead < tokens.count, fillers.contains(tokens.words[lead]) { lead += 1 }
        tokens.dropFirst(lead)
        let w = tokens.words
        for span in stride(from: min(3, w.count - 1), through: 1, by: -1) where tokens.stops.contains(span) {
            if let app = exactApp(w[0..<span].joined(), apps) { return (app, tokens.raw(span..<w.count)) }
        }
        return nil
    }

    static let openVerbs: [[String]] = [["open"], ["go", "to"], ["switch", "to"], ["launch"], ["start"]]

    /// "open <one or two words>" whose sound code is the sound code of one approved app name, and of no other.
    /// The names come from the app table. A label on the screen with the same words wins: the screen rules press it.
    static func appBySound(_ words: [String], apps: [AppEntry], screen: ScreenSnapshot?) -> AppEntry? {
        guard let verb = openVerbs.first(where: { words.starts(with: $0) }) else { return nil }
        var rest = Array(words.dropFirst(verb.count))
        while let f = rest.first, ["the", "my"].contains(f), rest.count > 1 { rest.removeFirst() }
        if let l = rest.last, ["app", "application"].contains(l), rest.count > 1 { rest.removeLast() }
        guard (1...2).contains(rest.count) else { return nil }
        let key = rest.joined()
        guard key.count >= 3, !key.unicodeScalars.contains(where: { $0.value >= 48 && $0.value <= 57 }) else { return nil }
        if let screen, screen.elements.contains(where: { ScreenRouter.keys($0.label).contains(key) }) { return nil }
        let code = SoundCode.code(key)
        let hits = apps.filter { app in
            app.approved && app.enabled && (app.aliases + [app.name]).contains { name in
                let k = TextKit.key(name)
                return k.count >= 3 && k != key && SoundCode.code(k) == code
            }
        }
        return hits.count == 1 ? hits[0] : nil
    }

    static func exactApp(_ key: String, _ apps: [AppEntry]) -> AppEntry? {
        apps.first { $0.approved && $0.enabled && ($0.aliases + [$0.name]).map(TextKit.key).contains(key) }
    }

    /// The decision for a command that names one app, or nil to use the other rules.
    /// - A screen command (click, scroll, ...): route it on the screen if the app is in front, else open the app.
    /// - "open <words>": a click only if the app is in front and a label matches sure. A risky label never gets a click
    ///   from "open": only "click <exact label>" can press a risky label (R-NV-5).
    static func screenFor(_ app: AppEntry, _ rest: String, context: RouteContext) -> RulesDecision? {
        guard !rest.isEmpty else { return nil }
        let front = context.screen?.bundleID ?? context.frontBundleID
        if isScreenCommand(rest) {
            if front == app.bundleID { return rules(rest, context: context) }
            // The app is not in front, so the screen is not its screen. Open the app (it can be undone) and do not click.
            return RulesDecision(intent: .openApp(appID: app.id), sure: true, exact: true,
                                 why: "\(app.name) was not in front: say the command again", options: [])
        }
        var words = TextKit.words(rest)
        while let f = words.first, fillers.contains(f), words.count > 1 { words.removeFirst() }
        guard words.first == "open", words.count >= 2, front == app.bundleID, let screen = context.screen else { return nil }
        let d = ScreenRouter.decide(rest, screen: screen)
        if case .click(let id) = d.intent, d.sure {
            if let e = screen.elements.first(where: { $0.id == id }), e.risky || SafetyPolicy.isRisky(e) {
                return RulesDecision(intent: .none, sure: true, exact: true, why: "blocked: risky label \"\(e.label)\"", options: [])
            }
            return d
        }
        if d.intent == .none, d.why.hasPrefix("blocked") { return d }
        return nil
    }

    /// True if the words are a command for the screen: click, type, scroll, back, an ordinal, or show or hide numbers.
    static func isScreenCommand(_ text: String) -> Bool {
        var words = TextKit.words(text)
        while let f = words.first, fillers.contains(f), words.count > 1 { words.removeFirst() }
        let phrase = words.joined(separator: " ")
        if showNumbers.contains(phrase) || hideNumbers.contains(phrase) { return true }
        guard let first = words.first else { return false }
        if pressOnly.contains(first) || typeFirst.contains(first) { return true }
        return [.scroll, .back, .ordinal].contains(ScreenRouter.parse(text).kind)
    }

    static func confidence(_ d: RulesDecision) -> Double {
        if d.sure { return sureConfidence }
        if case .openApp = d.intent { return unsureOpenAppConfidence }
        return unsureConfidence
    }

    static func tier(_ d: RulesDecision) -> RouterTier {
        if d.intent == .none && !d.sure { return .none }
        return d.exact ? .rules : .fuzzy
    }

    /// Runs tier 2, and stops waiting after `budgetMs`. The router does not trust the chooser to keep its budget.
    static func ask(_ chooser: Tier2Chooser, _ text: String, _ options: [String], budgetMs: Int) async -> Int? {
        let box = ChooserBox(chooser)
        return await withBudget(budgetMs) { await box.chooser.choose(text, options: options, budgetMs: budgetMs) }
    }
}

/// Lets a chooser go into a child task. The router calls it from one task at a time.
final class ChooserBox: @unchecked Sendable {
    let chooser: Tier2Chooser
    init(_ chooser: Tier2Chooser) { self.chooser = chooser }
}
