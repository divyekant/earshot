import AppKit

// The E1 commands. See docs/experiments/E1-generic-router.md.
// catalogue, index and e1-make read only. e1-try and e1-run send text to Jev.
// e1-open presses keys: it opens the owner's own chat with the generated rows and types nothing.

struct TestCommand: Codable {
    let id: Int
    let kind: String
    let words: String
    /// Each of these answers is correct. A first name that two apps show has two correct answers.
    let expected: [Choice]
}

struct TestSet: Codable {
    let builtAt: String
    let commands: [TestCommand]

    enum CodingKeys: String, CodingKey {
        case commands
        case builtAt = "built_at"
    }
}

/// A small random number generator with a seed, so that e1-make gives the same set each time.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@MainActor
enum E1 {
    static var commandsURL: URL { Paths.logs.appendingPathComponent("e1-commands.json") }

    static func pad(_ s: String, _ n: Int) -> String {
        s.count >= n ? String(s.prefix(n - 1)) + " " : s.padding(toLength: n, withPad: " ", startingAt: 0)
    }

    // MARK: - catalogue (read only)

    static func catalogue(_ args: [String]) async throws -> Int32 {
        guard AX.trusted(prompt: false) else { throw ProbeError("Accessibility is off for this terminal") }
        let skip = Commands.option(args, "--skip").map { $0.split(separator: ",").map(String.init) } ?? Catalogue.defaultSkip
        let file = await Catalogue.build(skip: skip)
        try Catalogue.save(file)
        print("App catalogue from the menu bars of \(file.apps.count) running apps. Left out: \(skip.joined(separator: ", "))\n")
        print(pad("App", 22) + pad("Chat", 6) + pad("Keys", 14) + pad("Rule", 13) + pad("Read", 8) + "Menu item")
        for a in file.apps {
            print(pad(a.name, 22) + pad(a.chat ? "yes" : "-", 6) + pad(a.openChat?.keys ?? "-", 14)
                  + pad(a.openChat?.rule ?? "-", 13) + pad("\(Int(a.readMs.rounded())) ms", 8) + (a.openChat?.menuPath ?? ""))
        }
        // Compare with the rows written by hand for E0.
        if let data = try? Data(contentsOf: Paths.apps), let hand = try? JSONDecoder().decode(AppTable.self, from: data) {
            print("\nCompared with the hand-written rows in apps.json:")
            for row in hand.apps {
                guard let built = file.apps.first(where: { $0.bundleID == row.bundleID }) else {
                    print("  \(row.name): not in the catalogue (not running, or left out)")
                    continue
                }
                let keys = built.openChat?.keys ?? "none"
                let same = keys == row.openChat.keys
                print("  \(row.name): hand \(row.openChat.keys ?? "none"), built \(keys) → \(same ? "same" : "DIFFERENT")")
            }
        }
        print("\nInstalled apps that do not run now: \(file.installed.count)")
        print("Saved \(Catalogue.url.path)")
        return 0
    }

    // MARK: - index (read only)

    static func index(_ args: [String]) async throws -> Int32 {
        guard AX.trusted(prompt: false) else { throw ProbeError("Accessibility is off for this terminal") }
        let cat = try Catalogue.load()
        let file = await NameIndex.build(catalogue: cat, front: args.contains("--front"), debug: args.contains("--debug"),
                                         dumpTree: args.contains("--dump"))
        try NameIndex.save(file)
        print("\nName index. Owner: \(file.owner)")
        for app in cat.apps where app.chat {
            let names = file.entries.filter { $0.app == app.id }
            guard !names.isEmpty else { print("  \(app.name): not read (not running)"); continue }
            let ms = Int((file.readMs[app.id] ?? 0).rounded())
            let settled = Int((file.settleMs?[app.id] ?? 0).rounded())
            let shown = names.prefix(20).map { $0.isSelf ? "\($0.name) (self)" : $0.name }
            print("  \(app.name): \(names.count) names, one read \(ms) ms, settled in \(settled) ms: \(shown.joined(separator: " | "))\(names.count > 20 ? " | ..." : "")")
            if let extra = file.aliases?[app.id] { print("    extra app names from the screen: \(extra.joined(separator: ", "))") }
        }
        print("Saved \(NameIndex.url.path)")
        return 0
    }

    // MARK: - e1-make: the test commands

    static func firstName(_ name: String) -> String {
        Text.normalize(name).split(separator: " ").first.map(String.init) ?? name
    }

    /// One wrong vowel, as speech to text can hear a name: "prakash" gives "prakush".
    static func mishear(_ word: String) -> String {
        var chars = Array(word.lowercased())
        let swaps: [Character: Character] = ["a": "u", "e": "i", "i": "e", "o": "u", "u": "o"]
        if let i = chars.indices.reversed().first(where: { $0 > 0 && swaps[chars[$0]] != nil }) {
            chars[i] = swaps[chars[i]]!
            return String(chars)
        }
        return word + "h"
    }

    static let nonCommands = [
        "I think the meeting moved to Thursday",
        "running late, be there in ten minutes",
        "the build passed on the second try",
        "what is the weather like today",
        "remind me to call the bank tomorrow",
        "can you summarise this page",
    ]

    /// Phrasings that the rules grammar was not written for. The Bool says if the phrasing names the app.
    static let freePhrasings: [(String, Bool)] = [
        ("can you pull up {first} on {app}", true),
        ("{first} on {app}", true),
        ("get me {first}'s chat", false),
        ("I need to talk to {first} on {app}", true),
        ("reply to {first}", false),
        ("DM {first} on {app}", true),
        ("open {app} and go to {first}", true),
        ("let's write to {first}", false),
        ("{app}, {first}", true),
        ("switch over to my chat with {first}", false),
    ]

    /// Names that are very likely not in the owner's chats.
    static let unknownNames = ["Ishaan", "Ingrid Vasquez", "Thembeka", "Okonkwo"]

    static func make(_ args: [String]) throws -> Int32 {
        let cat = try Catalogue.load()
        let idx = try NameIndex.load()
        let perApp = Int(Commands.option(args, "--per-app") ?? "") ?? 7
        var rng = SeededRandom(seed: UInt64(Commands.option(args, "--seed") ?? "") ?? 7)
        var out: [TestCommand] = []
        func add(_ kind: String, _ words: String, _ expected: [Choice]) {
            guard !expected.isEmpty else { return }
            out.append(TestCommand(id: out.count + 1, kind: kind, words: words, expected: expected))
        }
        func chat(_ e: IndexEntry) -> Choice { Choice(action: "open_chat", app: e.app, target: e.name) }
        /// The chats that a first name can mean, in one app or in all apps.
        func byFirst(_ first: String, app: String?) -> [Choice] {
            idx.entries.filter { e in
                !e.isSelf && (app == nil || e.app == app)
                    && (Text.key(firstName(e.name)) == Text.key(first) || Text.key(e.name) == Text.key(first))
            }.map(chat)
        }

        let chatApps = cat.apps.filter { a in a.chat && idx.entries.contains { $0.app == a.id && !$0.isSelf } }
        let kinds = ["full", "app-first", "first-only", "misheard", "with-text"]
        var n = 0
        for app in chatApps {
            let picks = idx.entries.filter { $0.app == app.id && !$0.isSelf }.shuffled(using: &rng).prefix(perApp)
            for e in picks {
                let first = firstName(e.name)
                // One phrasing that the rules were not written for.
                let (template, needsApp) = freePhrasings[n % freePhrasings.count]
                let words = template.replacingOccurrences(of: "{first}", with: first)
                    .replacingOccurrences(of: "{app}", with: app.name)
                add("free", words, byFirst(first, app: needsApp ? app.id : nil))
                for kind in [kinds[n % 5]] {
                    switch kind {
                    case "full":
                        let t = ["message \(e.name) on \(app.name)", "open my chat with \(e.name) in \(app.name)",
                                 "go to \(e.name) on \(app.name)"][n % 3]
                        add(kind, t, [chat(e)])
                    case "app-first":
                        add(kind, "\(app.name) \(first)", byFirst(first, app: app.id))
                    case "first-only":
                        add(kind, ["message \(first)", "ping \(first)"][n % 2], byFirst(first, app: nil))
                    case "misheard":
                        add(kind, "message \(mishear(first)) on \(app.name)", byFirst(first, app: app.id))
                    default:
                        let t = ["tell \(first) on \(app.name) that I will be ten minutes late",
                                 "\(app.name) \(first), can we move the call to four"][n % 2]
                        add("with-text", t, byFirst(first, app: app.id))
                    }
                }
                n += 1
            }
            let mine = idx.entries.filter { $0.app == app.id && $0.isSelf }.map(chat)
            add("self", "message me on \(app.name)", mine)
            add("self", "\(app.name) me, buy milk", mine)
            add("self", "open my own chat in \(app.name)", mine)
            add("open-app", "switch to \(app.name)", [Choice(action: "open_app", app: app.id, target: nil)])
        }
        // A common spoken name of Messages that no menu shows. Only the message box placeholder shows it.
        if let messages = chatApps.first(where: { $0.id == "messages" }) {
            let names = idx.entries.filter { $0.app == messages.id && !$0.isSelf }.prefix(2)
            for e in names { add("spoken-app", "text \(firstName(e.name)) on iMessage", byFirst(firstName(e.name), app: messages.id)) }
        }
        for a in cat.apps.filter({ !$0.chat }).shuffled(using: &rng).prefix(2) {
            add("open-app", "open \(a.name)", [Choice(action: "open_app", app: a.id, target: nil)])
        }
        for a in cat.installed.shuffled(using: &rng).prefix(2) {
            add("open-app", "open \(a.name)", [Choice(action: "open_app", app: a.id, target: nil)])
        }
        for s in nonCommands { add("none", s, [Choice.noAction]) }
        // Names that are not in the index. Doing nothing is correct. Opening only the app is also safe.
        for (i, name) in unknownNames.enumerated() where byFirst(firstName(name), app: nil).isEmpty {
            if let app = chatApps.isEmpty ? nil : chatApps[i % chatApps.count], i % 2 == 0 {
                add("unknown", "message \(name) on \(app.name)", [Choice.noAction, Choice(action: "open_app", app: app.id, target: nil)])
            } else {
                add("unknown", "ping \(name)", [Choice.noAction])
            }
        }

        let set = TestSet(builtAt: ISO8601DateFormatter().string(from: Date()), commands: out)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(set).write(to: commandsURL)
        var counts: [String: Int] = [:]
        for c in out { counts[c.kind, default: 0] += 1 }
        print("\(out.count) test commands: " + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        for c in out { print("  \(c.id). [\(c.kind)] \(c.words)  →  \(c.expected.map(\.describe).joined(separator: " or "))") }
        print("Saved \(commandsURL.path)")
        return 0
    }

    static func loadCommands() throws -> TestSet {
        guard let data = try? Data(contentsOf: commandsURL) else {
            throw ProbeError("probe/logs/e1-commands.json does not exist. Run: swift run earshot-probe e1-make")
        }
        return try JSONDecoder().decode(TestSet.self, from: data)
    }

    static func world() throws -> World { World(catalogue: try Catalogue.load(), index: try NameIndex.load()) }

    // MARK: - e1-try: one command

    static func tryOne(_ args: [String]) async throws -> Int32 {
        let w = try world()
        let words = Commands.positional(args).joined(separator: " ")
        let r = E1Router.retrieve(words, world: w)
        let rr = E1Router.rules(r)
        print("\"\(words)\"  (short list in \(String(format: "%.2f", r.ms)) ms, command: \(r.isCommand), unknown words: \(r.unknownWords))")
        for o in r.options { print("  \(pad(o.id, 6)) \(String(format: "%.2f", o.score))  \(o.label)") }
        print("rules: \(rr.choice.describe) (\(rr.confident ? "sure" : "unsure"): \(rr.why))")
        if !args.contains("--no-jev") {
            let jev = try JevClient()
            _ = try await jev.warmUp()
            let (choice, a) = try await E1Router.askJev(words, r, world: w, jev: jev)
            print("jev:   \(choice.describe) (confidence \(String(format: "%.2f", a.confidence)), \(Int(a.ms.rounded())) ms warm, \(a.inputTokens ?? 0) tokens in)")
        }
        return 0
    }

    // MARK: - e1-run: all test commands

    static func runAll(_ args: [String]) async throws -> Int32 {
        let w = try world()
        let set = try loadCommands()
        let limit = Int(Commands.option(args, "--limit") ?? "") ?? set.commands.count
        let jev: JevClient? = args.contains("--no-jev") ? nil : try JevClient()
        let log = try RunLog(kind: "route", experiment: "e1")
        print("E1 router test: \(min(limit, set.commands.count)) commands. Jev: \(jev == nil ? "off" : "on, text only").")
        print("Log: \(log.url.path)\n")
        if let jev {
            let cold = try await jev.warmUp()
            print("Jev warm-up (no personal data): \(Int(cold.ms.rounded())) ms cold, model \(cold.modelVersion ?? "?")\n")
            log.write(["event": "warmup", "ms": cold.ms, "model": cold.modelVersion ?? ""])
        }

        struct Row {
            let kind: String
            let recall: Bool
            let rulesOK: Bool, rulesSure: Bool, rulesMs: Double
            let jevOK: Bool?, jevMs: Double?
            let hybridOK: Bool, hybridMs: Double
            let tokens: Int?
            /// A wrong chat is the unsafe error: the owner could type into it.
            let rulesWrongChat: Bool, jevWrongChat: Bool, hybridWrongChat: Bool
        }
        var rows: [Row] = []
        for cmd in set.commands.prefix(limit) {
            let r = E1Router.retrieve(cmd.words, world: w)
            let t1 = Clock.nowNs()
            let rr = E1Router.rules(r)
            let rulesMs = r.ms + Clock.ms(since: t1)
            let recall = cmd.expected.contains { e in r.options.contains { $0.choice.matches(e) } }
            let rulesOK = cmd.expected.contains { rr.choice.matches($0) }

            var jevChoice: Choice?
            var answer: JevClient.Answer?
            var jevError: String?
            if let jev {
                do {
                    let (c, a) = try await E1Router.askJev(cmd.words, r, world: w, jev: jev)
                    jevChoice = c
                    answer = a
                } catch { jevError = "\(error)" }
            }
            var jevOK: Bool?
            if jev != nil { jevOK = jevChoice.map { c in cmd.expected.contains { c.matches($0) } } ?? false }
            // Hybrid: the rules answer when they are sure, else Jev. If Jev fails, the rules answer stays.
            let hybrid = rr.confident || jevChoice == nil ? rr.choice : jevChoice!
            let hybridOK = cmd.expected.contains { hybrid.matches($0) }
            let hybridMs = rulesMs + (rr.confident ? 0 : (answer?.ms ?? 0))
            func wrongChat(_ c: Choice?, _ ok: Bool?) -> Bool { c?.action == "open_chat" && ok == false }
            rows.append(Row(kind: cmd.kind, recall: recall, rulesOK: rulesOK, rulesSure: rr.confident, rulesMs: rulesMs,
                            jevOK: jevOK, jevMs: answer?.ms, hybridOK: hybridOK, hybridMs: hybridMs,
                            tokens: answer?.inputTokens,
                            rulesWrongChat: wrongChat(rr.choice, rulesOK), jevWrongChat: wrongChat(jevChoice, jevOK),
                            hybridWrongChat: wrongChat(hybrid, hybridOK)))

            var entry: [String: Any] = [
                "event": "route", "id": cmd.id, "kind": cmd.kind, "words": cmd.words,
                "expected": cmd.expected.map(\.dictionary), "options": r.options.map { ["id": $0.id, "label": $0.label, "score": $0.score] },
                "recall": recall, "retrieve_ms": r.ms, "is_command": r.isCommand, "unknown_words": r.unknownWords,
                "rules": rr.choice.dictionary, "rules_sure": rr.confident, "rules_why": rr.why, "rules_ok": rulesOK, "rules_ms": rulesMs,
                "hybrid": hybrid.dictionary, "hybrid_ok": hybridOK, "hybrid_ms": hybridMs,
            ]
            if let jevChoice { entry["jev"] = jevChoice.dictionary }
            if let jevOK { entry["jev_ok"] = jevOK }
            if let a = answer {
                entry["jev_ms"] = a.ms
                entry["jev_confidence"] = a.confidence
                entry["jev_tries"] = a.tries
                entry["jev_tokens_in"] = a.inputTokens ?? 0
                entry["jev_tokens_out"] = a.outputTokens ?? 0
            }
            if let jevError { entry["jev_error"] = jevError }
            log.write(entry)

            let mark = { (ok: Bool?) -> String in ok == nil ? "-" : (ok! ? "✓" : "✗") }
            var line = "\(pad("\(cmd.id).", 4))rules \(mark(rulesOK))\(rr.confident ? " " : "?") jev \(mark(jevOK)) hybrid \(mark(hybridOK))  "
            line += "[\(cmd.kind)] \(cmd.words)  →  rules: \(rr.choice.describe)"
            if let jevChoice { line += " · jev: \(jevChoice.describe) \(Int((answer?.ms ?? 0).rounded())) ms" }
            if let jevError { line += " · jev error: \(jevError.prefix(80))" }
            if !recall { line += " · RIGHT ANSWER NOT IN THE SHORT LIST" }
            print(line)
        }

        // Summary.
        let total = rows.count
        func pct(_ k: Int) -> String { total == 0 ? "-" : "\(k)/\(total) (\(Int((Double(k) / Double(total) * 100).rounded())) %)" }
        print("\nSummary")
        print(pad("Router", 24) + pad("Correct", 16) + pad("Wrong chat", 12) + pad("Median", 10) + "Slowest 1 in 10")
        print(pad("Rules + fuzzy (Mac)", 24) + pad(pct(rows.filter(\.rulesOK).count), 16)
              + pad("\(rows.filter(\.rulesWrongChat).count)", 12)
              + pad(Stats.ms(Stats.median(rows.map(\.rulesMs))), 10) + Stats.ms(Stats.percentile(rows.map(\.rulesMs), 0.9)))
        if jev != nil {
            let jevMs = rows.compactMap(\.jevMs)
            print(pad("Jev alone (cloud)", 24) + pad(pct(rows.filter { $0.jevOK == true }.count), 16)
                  + pad("\(rows.filter(\.jevWrongChat).count)", 12)
                  + pad(Stats.ms(Stats.median(jevMs)), 10) + Stats.ms(Stats.percentile(jevMs, 0.9)))
            print(pad("Rules, Jev if unsure", 24) + pad(pct(rows.filter(\.hybridOK).count), 16)
                  + pad("\(rows.filter(\.hybridWrongChat).count)", 12)
                  + pad(Stats.ms(Stats.median(rows.map(\.hybridMs))), 10) + Stats.ms(Stats.percentile(rows.map(\.hybridMs), 0.9)))
        }
        let sure = rows.filter(\.rulesSure)
        print("\nRules were sure for \(sure.count) of \(total) commands, and right for \(sure.filter(\.rulesOK).count) of those.")
        print("Right answer in the short list: \(pct(rows.filter(\.recall).count)).")
        if let t = Stats.median(rows.compactMap(\.tokens).map { Double($0) }) { print("Jev input tokens per call: median \(Int(t)).") }
        print("\nBy kind (rules / jev / hybrid):")
        for kind in Array(Set(rows.map(\.kind))).sorted() {
            let k = rows.filter { $0.kind == kind }
            let j = jev == nil ? "-" : "\(k.filter { $0.jevOK == true }.count)"
            print("  \(pad(kind, 12)) \(k.filter(\.rulesOK).count) / \(j) / \(k.filter(\.hybridOK).count) of \(k.count)")
        }
        return 0
    }

    // MARK: - e1-open: the generated rows open the owner's own chat (presses keys, types nothing)

    static func open(_ args: [String]) async throws -> Int32 {
        guard AX.trusted(prompt: true) else { throw ProbeError("Accessibility is off. Run: swift run earshot-probe check") }
        let cat = try Catalogue.load()
        let idx = try NameIndex.load()
        let pos = Commands.positional(args)
        let runs = pos.compactMap { Int($0) }.first ?? 3
        let only = pos.first(where: { Int($0) == nil })
        let rows = cat.apps.filter { only == nil || $0.id == only }.compactMap { $0.appRow() }
        let pipeline = Pipeline(apps: rows)
        pipeline.prime()
        let log = try RunLog(kind: "open", experiment: "e1")
        print("E1: the generated rows open your own chat. They type nothing. Do not touch the keyboard or mouse.")
        print("Log: \(log.url.path)\n")
        for row in rows {
            let name = idx.entries.first(where: { $0.app == row.id && $0.isSelf })?.name ?? idx.owner
            let me = Person(name: name, aliases: nil, isSelf: true, handles: [:], display: nil)
            for i in 0..<runs {
                if i % 2 == 1 { _ = await pipeline.bringToFront(bundleID: "com.apple.finder") }
                await sleepMs(300)
                let cmd = Command(app: row, person: me, unmatchedName: nil, text: nil, nameScore: 1)
                let watch = Stopwatch()
                let out = await pipeline.execute(cmd, watch: watch, typing: .off)
                log.write(["event": "command", "id": i + 1, "mode": "typed", "app": row.id, "keys": row.openChat.keys ?? "",
                           "from_other_app": i % 2 == 1, "stages": watch.dictionary, "outcome": out.dictionary])
                print("\(row.name) \(i + 1)/\(runs) \(out.ok ? "✓" : "✗") \(watch.summary) · open=\(out.openMethod) focus=\(out.focusMethod) chat=\(out.chatCheck)\(out.reason.map { " · \($0)" } ?? "")")
                await sleepMs(500)
            }
        }
        return 0
    }
}
