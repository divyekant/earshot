import Foundation

// E1, question 3: the generic router. It knows no app and no person in advance.
// It uses only the generated catalogue and the name index (R-MT-1, R-MT-2).
// Step 1 (retrieve) makes a short list of options. Step 2 picks one option:
// local rules, or Jev, or rules first and Jev only when the rules are unsure.
// Each command makes one Jev call at most. There is no agent loop (R-SP-2).

/// One routing result: open a chat, open an app, or nothing.
struct Choice: Codable, Equatable {
    let action: String
    let app: String?
    let target: String?

    static let noAction = Choice(action: "none", app: nil, target: nil)

    func matches(_ other: Choice) -> Bool {
        action == other.action && (app ?? "") == (other.app ?? "")
            && Text.key(target ?? "") == Text.key(other.target ?? "")
    }

    var describe: String {
        switch action {
        case "open_chat": return "\(app ?? "?") · \(target ?? "?")"
        case "open_app": return "open \(app ?? "?")"
        default: return "none"
        }
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = ["action": action]
        if let app { d["app"] = app }
        if let target { d["target"] = target }
        return d
    }
}

/// One option in the short list.
struct RouteOption {
    let id: String
    let choice: Choice
    let label: String
    let score: Double
}

/// The apps and names that the router can use.
struct World {
    struct App {
        let id: String
        let name: String
        let aliases: [String]
        let chat: Bool
    }

    let apps: [App]
    let entries: [IndexEntry]
    let owner: String

    init(catalogue: CatalogueFile, index: IndexFile) {
        // The index adds spoken app names that it read on screen, such as "iMessage".
        let extra = index.aliases ?? [:]
        var list = catalogue.apps.map { App(id: $0.id, name: $0.name, aliases: $0.aliases + (extra[$0.id] ?? []), chat: $0.chat) }
        list += catalogue.installed.map { App(id: $0.id, name: $0.name, aliases: $0.aliases, chat: false) }
        apps = list
        entries = index.entries
        owner = index.owner
    }

    func appName(_ id: String) -> String { apps.first(where: { $0.id == id })?.name ?? id }
}

struct Retrieval {
    let options: [RouteOption]
    /// True if the words start with a command word or an app name, or say "on <app>".
    let isCommand: Bool
    /// The number of words that are not a command word, an app name or a known name.
    let unknownWords: Int
    let ms: Double
}

struct RulesResult {
    let choice: Choice
    let confident: Bool
    let why: String
}

enum E1Router {
    static let leadFillers: Set<String> = ["hey", "ok", "okay", "earshot", "please", "can", "could", "you", "would"]
    static let commandVerbs: Set<String> = ["message", "text", "ping", "dm", "tell", "write", "chat", "open", "go",
                                            "switch", "launch", "show", "reply", "jump", "start", "send", "bring",
                                            "pull", "talk", "find", "reach"]
    /// Words that end the name part. The message text comes after them.
    static let textLeads: Set<String> = ["saying", "say", "that"]
    static let selfWords: Set<String> = ["me", "myself", "self"]
    /// Words that are never part of a name.
    static let stopWords: Set<String> = commandVerbs.union(leadFillers).union([
        "to", "on", "in", "at", "with", "my", "the", "a", "an", "and", "app", "chat", "conversation", "channel",
        "i", "am", "is", "for", "of", "up", "back", "new", "own", "about", "over", "there", "here", "into",
    ])

    static let shortListSize = 8
    static let strongMatch = 0.8
    static let weakMatch = 0.6

    // MARK: - Step 1: the short list

    static func retrieve(_ spoken: String, world: World) -> Retrieval {
        let t0 = Clock.nowNs()
        // "Felix's chat" names Felix. Remove the possessive before the words are split.
        let words = spoken.replacingOccurrences(of: #"['\u2019]s\b"#, with: "", options: .regularExpression)
        // Each comma-separated piece gives its own tokens, so that the probe knows where each comma is.
        var tokens: [String] = []
        var commaAfter: [Int] = []
        for piece in words.split(separator: ",", omittingEmptySubsequences: false) {
            tokens += Text.normalize(String(piece)).split(separator: " ").map(String.init)
            commaAfter.append(tokens.count)
        }
        commaAfter.removeLast()
        var dropped = 0
        while let first = tokens.first, leadFillers.contains(first) { tokens.removeFirst(); dropped += 1 }
        let commas = commaAfter.map { $0 - dropped }.filter { $0 > 0 && $0 < tokens.count }

        // App names, anywhere in the words. One word or more, almost exact (0.9):
        // "message" must not match the app "Messages".
        var mentioned: [String: Double] = [:]
        var appTokens = Set<Int>()
        var appAtStart = false
        var onApp = false
        for app in world.apps {
            for alias in app.aliases {
                let parts = alias.split(separator: " ").map(String.init)
                guard !parts.isEmpty else { continue }
                // Speech to text can split a one-word name: "TigerVNC" comes back as "Tiger VNC" (E2).
                let spans = parts.count == 1 && parts[0].count >= 5 ? [1, 2] : [parts.count]
                for span in spans where span <= tokens.count {
                    for start in 0...(tokens.count - span) {
                        let phrase = tokens[start..<(start + span)].joined()
                        let score = Text.similarity(phrase, parts.joined())
                        guard score >= 0.9 else { continue }
                        mentioned[app.id] = max(mentioned[app.id] ?? 0, score)
                        for i in start..<(start + span) { appTokens.insert(i) }
                        if start == 0 { appAtStart = true }
                        if start > 0, ["on", "in"].contains(tokens[start - 1]) { onApp = true }
                    }
                }
            }
        }

        // The name part ends at a comma or at a text lead word ("tell Ravi that ...").
        // A comma right after the app name does not end it: "Slack, Ravi" names Ravi.
        func hasNameWord(_ range: Range<Int>) -> Bool {
            range.contains { i in !appTokens.contains(i) && !stopWords.contains(tokens[i]) }
        }
        var nameEnd = commas.first(where: { hasNameWord(0..<$0) }) ?? tokens.count
        if let lead = tokens.indices.dropFirst().first(where: { textLeads.contains(tokens[$0]) }) {
            nameEnd = min(nameEnd, lead)
        }

        // A command word in the first three words: "let's write to Ravi", "can you pull up Ravi".
        let isCommand = tokens.prefix(3).contains { commandVerbs.contains($0) } || appAtStart || onApp
        let head = tokens.prefix(nameEnd)
        let wantsSelf = head.contains { selfWords.contains($0) } || (head.contains("my") && head.contains("own"))

        // Name words: the name part without stop words, app names and self words.
        let nameWords = tokens.indices.filter { i in
            i < nameEnd && !appTokens.contains(i) && !stopWords.contains(tokens[i]) && !selfWords.contains(tokens[i])
        }.map { tokens[$0] }
        var grams: [String] = []
        for n in 1...3 where nameWords.count >= n {
            for s in 0...(nameWords.count - n) { grams.append(nameWords[s..<(s + n)].joined()) }
        }

        // Only a chat app name changes the name scores. An app such as "Lock Screen" can match a common word.
        let chatMentioned = Set(mentioned.keys.filter { id in world.apps.contains { $0.id == id && $0.chat } })

        var scored: [(IndexEntry, Double)] = []
        var usedGrams = Set<String>()
        for entry in world.entries {
            let full = Text.key(entry.name)
            let parts = Text.normalize(entry.name).split(separator: " ")
            let firstName = parts.count >= 2 ? String(parts[0]) : ""
            var best = 0.0
            var bestGram = ""
            for g in grams where g.count >= 3 || g == full {
                var s = Text.similarity(g, full)
                if !firstName.isEmpty { s = max(s, 0.95 * Text.similarity(g, firstName)) }
                if s > best { best = s; bestGram = g }
            }
            if entry.isSelf && wantsSelf { best = 1.0 }
            if !chatMentioned.isEmpty {
                best += chatMentioned.contains(entry.app) ? 0.1 : -0.15
            }
            if best >= 0.45 {
                scored.append((entry, best))
                if best >= weakMatch, !bestGram.isEmpty { usedGrams.insert(bestGram) }
            }
        }
        scored.sort { $0.1 > $1.1 }

        var options: [RouteOption] = []
        for (entry, score) in scored.prefix(shortListSize) {
            let appName = world.appName(entry.app)
            let label = entry.isSelf ? "\(appName): open the owner's own chat (\(entry.name))"
                : "\(appName): open the chat \"\(entry.name)\""
            options.append(RouteOption(id: "o\(options.count + 1)",
                                       choice: Choice(action: "open_chat", app: entry.app, target: entry.name),
                                       label: label, score: score))
        }
        for (id, score) in mentioned.sorted(by: { $0.value > $1.value }) {
            options.append(RouteOption(id: "o\(options.count + 1)", choice: Choice(action: "open_app", app: id, target: nil),
                                       label: "Open the app \(world.appName(id))", score: score))
        }
        options.append(RouteOption(id: "none", choice: Choice.noAction,
                                   label: "None: the words do not ask to open a chat or an app", score: 0))

        // Words that nothing explains. A name word counts as known if it matched a name well.
        let unknown = nameWords.filter { w in !usedGrams.contains(where: { $0.contains(w) }) }.count
        return Retrieval(options: options, isCommand: isCommand, unknownWords: unknown,
                         ms: Clock.ms(since: t0))
    }

    // MARK: - Step 2a: local rules

    static func rules(_ r: Retrieval) -> RulesResult {
        let chats = r.options.filter { $0.choice.action == "open_chat" }
        guard r.isCommand else {
            // A known name with no command word: the rules cannot tell, so Jev decides ("get me Ravi's chat").
            if let c = chats.first, c.score >= strongMatch {
                return RulesResult(choice: Choice.noAction, confident: false, why: "a known name, but no command word")
            }
            return RulesResult(choice: Choice.noAction, confident: true, why: "no command word or app name")
        }
        let apps = r.options.filter { $0.choice.action == "open_app" }
        let c1 = chats.first
        let c2 = chats.dropFirst().first
        if let c1, c1.score >= strongMatch {
            if let c2, c2.score >= c1.score - 0.05 {
                return RulesResult(choice: c1.choice, confident: false, why: "two chats match")
            }
            return RulesResult(choice: c1.choice, confident: true, why: "name match")
        }
        if let a = apps.first, (c1?.score ?? 0) < weakMatch {
            let sure = r.unknownWords == 0
            return RulesResult(choice: a.choice, confident: sure, why: sure ? "app name" : "app name, other words unknown")
        }
        if let c1, c1.score >= weakMatch {
            return RulesResult(choice: c1.choice, confident: false, why: "weak name match")
        }
        return RulesResult(choice: Choice.noAction, confident: false, why: "nothing matches")
    }

    // MARK: - Step 2b: Jev

    static let jevGoal = "Pick the option that the owner's voice command asks for."
    static let jevRules = """
    The command comes from speech to text, so a name can be misspelled or heard wrong. \
    "Me", "myself" or "my own chat" means the owner's own chat. \
    If the command names an app, pick an option in that app. \
    If the command names no app, pick the chat whose name matches best. \
    If the command asks only to open or switch to an app, pick the app option. \
    If the words are not a request to open a chat or an app, pick none.
    """

    static func askJev(_ words: String, _ r: Retrieval, world: World, jev: JevClient) async throws
        -> (Choice, JevClient.Answer) {
        let state: [String: Any] = ["command": words, "owner": world.owner]
        let answer = try await jev.choose(id: "route", options: r.options.map { (id: $0.id, label: $0.label) },
                                          goal: jevGoal, rules: jevRules, state: state)
        let choice: Choice = r.options.first(where: { $0.id == answer.choice })?.choice ?? Choice.noAction
        return (choice, answer)
    }
}
