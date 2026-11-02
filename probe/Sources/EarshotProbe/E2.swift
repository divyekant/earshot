import AppKit

// The E2 web commands. See docs/experiments/E2-web-and-speech.md.
// e2-page opens the test pages in Chrome and reads them. It presses no key and clicks nothing.
// e2-make, e2-try and e2-run work on the saved reads. e2-try and e2-run send text to Jev.
// e2-act presses links, types into search fields and scrolls, on live pages. It runs only after the owner agrees.

struct WebTest: Codable {
    let id: Int
    let site: String
    let kind: String
    let words: String
    /// Each of these answers is correct.
    let expected: [WebChoice]
}

struct WebTestSet: Codable {
    let builtAt: String
    let tests: [WebTest]
}

@MainActor
enum E2 {
    static var testsURL: URL { Paths.logs.appendingPathComponent("e2-tests.json") }
    static func pad(_ s: String, _ n: Int) -> String { E1.pad(s, n) }

    /// The words in the arguments that are not options. "--browser", "--seed" and "--label" take a value.
    static func names(_ args: [String]) -> [String] {
        var out: [String] = []
        var skip = false
        for a in args {
            if skip { skip = false; continue }
            if ["--browser", "--seed", "--label"].contains(a) { skip = true; continue }
            if a.hasPrefix("--") { continue }
            out.append(a)
        }
        return out
    }

    static func bringToFront(_ bundleID: String) async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        return await waitUntil(timeoutMs: 3000) {
            guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
            else { return false }
            return AX.frontPid() == pid
        }
    }

    // MARK: - e2-page: read the test pages (no key press, no click)

    static func page(_ args: [String]) async throws -> Int32 {
        guard AX.trusted(prompt: false) else { throw ProbeError("Accessibility is off for this terminal") }
        let file = try WebPage.loadSites()
        let bundle = Commands.option(args, "--browser") ?? file.browser
        let only = Set(names(args))
        let front = args.contains("--front")
        let before = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let app = WebPage.browser(bundle) else { throw ProbeError("\(bundle) does not run. Open it first.") }
        await sleepMs(500)

        var sites = file.sites.filter { only.isEmpty || only.contains($0.id) }
        if args.contains("--current") {
            sites = [WebSite(id: only.first ?? "current", url: WebPage.currentURL(app) ?? "")]
        }
        print("E2 page read. Browser: \(bundle). Front: \(front ? "yes" : "no (pages open behind the front app)").\n")
        print(pad("Site", 12) + pad("Elements", 10) + pad("Links", 7) + pad("Buttons", 9) + pad("Fields", 8) + pad("No label", 10)
              + pad("Read", 9) + pad("Find page", 11) + pad("Walk", 16) + "Method")
        for site in sites {
            if !args.contains("--current") {
                guard let url = URL(string: site.url), let host = url.host else { continue }
                WebPage.open(url, bundleID: bundle, activate: front)
                guard await WebPage.waitForPage(app, host: host) else {
                    print("\(site.id): the page did not load in 10 s, or Chrome shows no web tree")
                    continue
                }
                await sleepMs(1000)
            }
            // Three timed reads without the heading check, then one full read for the saved snapshot.
            var reads: [LiveRead] = []
            for _ in 0..<3 {
                if let r = WebPage.read(app, headings: false) { reads.append(r) }
                await sleepMs(200)
            }
            let full = WebPage.read(app)
            guard let last = full else {
                print("\(site.id): no page found in the front window")
                continue
            }
            // Save only the page of the site, and never a sign-in, code or payment page (E2 live run 3).
            if let why = WebPage.refuse(last, host: args.contains("--current") ? nil : URL(string: site.url)?.host) {
                print("\(site.id): \(why). Not saved.")
                continue
            }
            // The tree walk, for comparison with the one-call search.
            var walkMs: Double?
            var walkCount: Int?
            if let w = AX.window(app), let area = WebPage.webArea(in: w), let vp = AX.frame(area) {
                let t0 = Clock.nowNs()
                let (found, _) = WebPage.walk(area, viewport: vp)
                walkMs = Clock.ms(since: t0)
                walkCount = found.count
            }
            let title = AX.window(app).flatMap { AX.string($0, "AXTitle") } ?? ""
            let snap = WebSnapshot(builtAt: ISO8601DateFormatter().string(from: Date()), site: site.id, url: last.url,
                                   title: WebPage.clean(title), method: last.method, readMs: reads.map(\.ms),
                                   walkMs: walkMs, walkCount: walkCount, unlabelled: last.unlabelled, elements: last.elements)
            try WebPage.save(snap)
            let els = last.elements
            let read = Stats.median(reads.map(\.ms))
            let find = Stats.median(reads.map(\.findMs))
            print(pad(site.id, 12) + pad("\(els.count)", 10) + pad("\(els.filter { $0.kind == "link" }.count)", 7)
                  + pad("\(els.filter { $0.kind == "button" }.count)", 9) + pad("\(els.filter { $0.kind == "field" }.count)", 8)
                  + pad("\(last.unlabelled)", 10) + pad(Stats.ms(read), 9) + pad(Stats.ms(find), 11)
                  + pad(walkMs.map { "\(Stats.ms($0)) (\(walkCount ?? 0))" } ?? "-", 16) + "\(last.method), page by \(last.areaPath)")
            let headed = els.filter(\.inHeading).count
            let risky = els.filter { WebRouter.isRisky($0.label) }.count
            print("    links in headings: \(headed), search fields: \(els.filter(\.isSearchField).count), risky labels: \(risky), full read with headings: \(Stats.ms(last.ms))")
            if args.contains("--list") {
                for e in els {
                    print("    \(pad(e.id, 6))\(pad(e.kind, 8))\(e.inHeading ? "H " : "  ")\(WebRouter.isRisky(e.label) ? "! " : "  ")\(e.label)")
                }
            }
        }
        if front, let id = before { _ = await bringToFront(id) }
        print("\nSaved probe/logs/e2-page-<site>.json. The pages stay open in new tabs.")
        return 0
    }

    // MARK: - e2-make: the test commands

    static let exactForms = ["click {l}", "open {l}", "press {l}", "go to {l}"]
    static let freeForms = ["take me to {l}", "can you open the {l} {role}", "show me {l}", "I want to see {l}",
                            "{l} please", "hit the {l} {role}"]
    static let unknownLabels = ["pricing plans", "download the desktop app", "contact sales", "shopping cart", "weather forecast"]

    static func make(_ args: [String]) throws -> Int32 {
        let file = try WebPage.loadSites()
        var rng = SeededRandom(seed: UInt64(Commands.option(args, "--seed") ?? "") ?? 11)
        var out: [WebTest] = []
        func add(_ site: String, _ kind: String, _ words: String, _ expected: [WebChoice]) {
            guard !expected.isEmpty else { return }
            out.append(WebTest(id: out.count + 1, site: site, kind: kind, words: words, expected: expected))
        }
        func press(_ e: WebElement) -> WebChoice { WebChoice(action: "press", element: e.id, text: nil) }
        /// The words that speech to text gives for a label: no symbols.
        func spoken(_ label: String) -> String { Text.normalize(label) }

        var loaded: [WebSnapshot] = []
        var n = 0
        for site in file.sites {
            guard let snap = try? WebPage.load(site.id) else {
                print("\(site.id): no saved read. Run e2-page first.")
                continue
            }
            if let host = URL(string: site.url)?.host, !WebPage.onHost(snap.url, host)
                || WebPage.sensitive(url: snap.url, elements: snap.elements) != nil {
                print("\(site.id): the saved read is not a page of \(host), or it is a sign-in page. Run e2-page again.")
                continue
            }
            loaded.append(snap)
            let els = snap.elements
            var counts: [String: Int] = [:]
            for e in els { counts[Text.key(e.label), default: 0] += 1 }
            func unique(_ e: WebElement) -> Bool { counts[Text.key(e.label)] == 1 }
            // Targets: links and buttons with a label that occurs once, 1 to 5 words, with letters, not risky.
            let targets = els.filter { e in
                (e.kind == "link" || e.kind == "button") && unique(e) && (1...5).contains(e.words)
                    && Text.key(e.label).count >= 3 && Text.key(e.label).rangeOfCharacter(from: .letters) != nil
                    && !WebRouter.isRisky(e.label)
            }.shuffled(using: &rng)
            var next = 0
            func take(_ ok: (WebElement) -> Bool = { _ in true }) -> WebElement? {
                while next < targets.count {
                    let e = targets[next]
                    next += 1
                    if ok(e) { return e }
                }
                return nil
            }

            for _ in 0..<2 {
                guard let e = take() else { break }
                add(site.id, "exact", exactForms[n % exactForms.count].replacingOccurrences(of: "{l}", with: spoken(e.label)), [press(e)])
                n += 1
            }
            for _ in 0..<2 {
                guard let e = take() else { break }
                let words = freeForms[n % freeForms.count].replacingOccurrences(of: "{l}", with: spoken(e.label))
                    .replacingOccurrences(of: "{role}", with: e.kind == "link" ? "link" : "button")
                add(site.id, "free", words, [press(e)])
                n += 1
            }
            // Part of a long label: one or two of its words, if they point at this element only.
            if let e = take({ $0.words >= 3 }) {
                let content = Text.normalize(e.label).split(separator: " ").map(String.init)
                    .filter { !WebRouter.smallWords.contains($0) && $0.count >= 3 }
                let tries = [Array(content.prefix(2)), Array(content.suffix(1)), Array(content.prefix(1))].filter { !$0.isEmpty }
                for words in tries {
                    let mine = WebRouter.score(words, e.label)
                    let clear = !els.contains { o in o.id != e.id && WebRouter.score(words, o.label) >= mine - WebRouter.margin }
                    if clear {
                        add(site.id, "partial", "open \(words.joined(separator: " "))", [press(e)])
                        break
                    }
                }
            }
            // One wrong vowel in a word of 5 or more letters.
            if let e = take({ l in Text.normalize(l.label).split(separator: " ").contains { $0.count >= 5 } }) {
                var words = Text.normalize(e.label).split(separator: " ").map(String.init)
                if let i = words.firstIndex(where: { $0.count >= 5 }) {
                    words[i] = E1.mishear(words[i])
                    add(site.id, "misheard", "click \(words.joined(separator: " "))", [press(e)])
                }
            }
            // A risky element: the router must block it. All copies of the label count.
            if let r = els.first(where: { WebRouter.isRisky($0.label) && (1...3).contains($0.words) && $0.kind != "field" }) {
                let copies = els.filter { Text.key($0.label) == Text.key(r.label) }
                add(site.id, "risky", "click \(spoken(r.label))", copies.map { WebChoice(action: "blocked", element: $0.id, text: nil) })
            }
            // Search: type into any search field, no Return.
            let fields = els.filter(\.isSearchField)
            if !fields.isEmpty {
                add(site.id, "search", "search for local voice control",
                    fields.map { WebChoice(action: "type", element: $0.id, text: "local voice control") })
            }
            // Ordinal: the router's own result list. The live run prints the label to check by eye.
            // Only a page with a list of results gets this test: links in headings, or many long links.
            let results = WebRouter.ordinalList("result", els)
            let headed = results.filter(\.inHeading).count
            if results.count >= 3, headed >= 2 || results.count >= 15 {
                add(site.id, "ordinal", "open the second result", [press(results[1])])
            }
            // A label that the page does not have.
            if let u = unknownLabels.first(where: { l in
                let w = Text.normalize(l).split(separator: " ").map(String.init)
                return !els.contains { WebRouter.score(w, $0.label) >= WebRouter.noMatch }
            }) {
                add(site.id, "unknown", "click \(u)", [WebChoice.noAction])
            }
        }
        guard !loaded.isEmpty else { throw ProbeError("no saved page reads. Run: swift run earshot-probe e2-page") }
        // Page actions and words that are not commands. They do not depend on the page.
        let s = loaded.map(\.site)
        add(s[0], "scroll", "scroll down", [WebChoice(action: "scroll", element: nil, text: "down")])
        add(s[min(1, s.count - 1)], "scroll", "go to the top", [WebChoice(action: "scroll", element: nil, text: "top")])
        add(s[min(2, s.count - 1)], "back", "go back", [WebChoice(action: "back", element: nil, text: nil)])
        for (i, words) in E1.nonCommands.prefix(4).enumerated() {
            add(s[i % s.count], "none", words, [WebChoice.noAction])
        }

        let set = WebTestSet(builtAt: ISO8601DateFormatter().string(from: Date()), tests: out)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(set).write(to: testsURL)
        var counts: [String: Int] = [:]
        for t in out { counts[t.kind, default: 0] += 1 }
        print("\(out.count) web test commands: " + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        for t in out {
            let els = loaded.first(where: { $0.site == t.site })?.elements ?? []
            print("  \(t.id). [\(t.site) \(t.kind)] \(t.words)  →  \(t.expected.map { $0.describe(els) }.joined(separator: " or "))")
        }
        print("Saved \(testsURL.path)")
        return 0
    }

    static func loadTests() throws -> WebTestSet {
        guard let data = try? Data(contentsOf: testsURL) else {
            throw ProbeError("probe/logs/e2-tests.json does not exist. Run: swift run earshot-probe e2-make")
        }
        return try JSONDecoder().decode(WebTestSet.self, from: data)
    }

    /// Jev gets a question only for a press command that has element options.
    static func jevApplies(_ r: WebRoute) -> Bool {
        r.parse.intent == "press" && r.options.contains { $0.choice.action == "press" }
    }

    // MARK: - e2-try: one command on a saved page

    static func tryOne(_ args: [String]) async throws -> Int32 {
        let pos = names(args)
        guard pos.count >= 2 else { throw ProbeError("usage: e2-try <site> \"<words>\"") }
        let snap = try WebPage.load(pos[0])
        let words = pos.dropFirst().joined(separator: " ")
        let r = WebRouter.route(words, elements: snap.elements)
        print("\"\(words)\" on \(snap.site)  (\(String(format: "%.2f", r.ms)) ms, intent: \(r.parse.intent), command: \(r.parse.isCommand), target: \(r.parse.target.joined(separator: " ")))")
        for o in r.options { print("  \(pad(o.id, 7)) \(String(format: "%.2f", o.score))  \(o.label)") }
        print("rules: \(r.rules.describe(snap.elements)) (\(r.sure ? "sure" : "unsure"): \(r.why))")
        if !args.contains("--no-jev"), jevApplies(r) {
            let jev = try JevClient()
            _ = try await jev.warmUp()
            let (c, a) = try await WebRouter.askJev(words, r, elements: snap.elements, jev: jev)
            print("jev:   \(c.describe(snap.elements)) (confidence \(String(format: "%.2f", a.confidence)), \(Int(a.ms.rounded())) ms warm)")
        }
        return 0
    }

    // MARK: - e2-run: all test commands on the saved pages

    static func runAll(_ args: [String]) async throws -> Int32 {
        let set = try loadTests()
        let jev: JevClient? = args.contains("--no-jev") ? nil : try JevClient()
        let log = try RunLog(kind: "route", experiment: "e2")
        var pages: [String: WebSnapshot] = [:]
        print("E2 web router test: \(set.tests.count) commands. Jev: \(jev == nil ? "off" : "on, text only").")
        print("Log: \(log.url.path)\n")
        if let jev {
            let cold = try await jev.warmUp()
            print("Jev warm-up (no personal data): \(Int(cold.ms.rounded())) ms cold\n")
        }

        struct Row {
            let kind: String
            let rulesOK: Bool, rulesSure: Bool, rulesMs: Double
            let jevOK: Bool, jevMs: Double?
            let hybridOK: Bool, hybridMs: Double
            /// A wrong press is the unsafe error: the page does something that the owner did not ask for.
            let rulesWrong: Bool, jevWrong: Bool, hybridWrong: Bool
            let riskyMissed: Bool
        }
        var rows: [Row] = []
        for t in set.tests {
            if pages[t.site] == nil { pages[t.site] = try WebPage.load(t.site) }
            let els = pages[t.site]!.elements
            let r = WebRouter.route(t.words, elements: els)
            let rulesOK = t.expected.contains { r.rules.matches($0) }
            var jevChoice: WebChoice?
            var answer: JevClient.Answer?
            var jevError: String?
            if let jev, jevApplies(r) {
                do {
                    let (c, a) = try await WebRouter.askJev(t.words, r, elements: els, jev: jev)
                    jevChoice = c
                    answer = a
                } catch { jevError = "\(error)" }
            }
            // Jev alone: Jev for press commands; the parse answer for scroll, back, search and ordinal commands.
            let jevAlone = jevChoice ?? r.rules
            let jevOK = t.expected.contains { jevAlone.matches($0) }
            let hybrid = r.sure || jevChoice == nil ? r.rules : jevChoice!
            let hybridOK = t.expected.contains { hybrid.matches($0) }
            let hybridMs = r.ms + (r.sure ? 0 : (answer?.ms ?? 0))
            func wrong(_ c: WebChoice, _ ok: Bool) -> Bool { !ok && (c.action == "press" || c.action == "type") }
            let riskyMissed = t.kind == "risky" && hybrid.action != "blocked"
            rows.append(Row(kind: t.kind, rulesOK: rulesOK, rulesSure: r.sure, rulesMs: r.ms, jevOK: jevOK, jevMs: answer?.ms,
                            hybridOK: hybridOK, hybridMs: hybridMs, rulesWrong: wrong(r.rules, rulesOK),
                            jevWrong: wrong(jevAlone, jevOK), hybridWrong: wrong(hybrid, hybridOK), riskyMissed: riskyMissed))

            var entry: [String: Any] = [
                "event": "route", "id": t.id, "site": t.site, "kind": t.kind, "words": t.words,
                "expected": t.expected.map(\.dictionary), "intent": r.parse.intent, "target": r.parse.target.joined(separator: " "),
                "options": r.options.map { ["id": $0.id, "label": $0.label, "score": $0.score] },
                "rules": r.rules.dictionary, "rules_sure": r.sure, "rules_why": r.why, "rules_ok": rulesOK, "rules_ms": r.ms,
                "hybrid": hybrid.dictionary, "hybrid_ok": hybridOK, "hybrid_ms": hybridMs,
            ]
            if let jevChoice { entry["jev"] = jevChoice.dictionary }
            if let a = answer {
                entry["jev_ms"] = a.ms
                entry["jev_confidence"] = a.confidence
                entry["jev_tokens_in"] = a.inputTokens ?? 0
            }
            if let jevError { entry["jev_error"] = jevError }
            log.write(entry)

            let mark = { (ok: Bool) -> String in ok ? "✓" : "✗" }
            var line = "\(pad("\(t.id).", 4))rules \(mark(rulesOK))\(r.sure ? " " : "?") jev \(jevChoice == nil ? "-" : mark(jevOK)) hybrid \(mark(hybridOK))  "
            line += "[\(t.site) \(t.kind)] \(t.words)  →  \(r.rules.describe(els))"
            if let jevChoice { line += " · jev: \(jevChoice.describe(els)) \(Int((answer?.ms ?? 0).rounded())) ms" }
            if let jevError { line += " · jev error: \(jevError.prefix(80))" }
            if !hybridOK { line += " · WANTED: \(t.expected.first?.describe(els) ?? "")" }
            print(line)
        }

        let total = rows.count
        func pct(_ k: Int) -> String { total == 0 ? "-" : "\(k)/\(total) (\(Int((Double(k) / Double(total) * 100).rounded())) %)" }
        print("\nSummary")
        print(pad("Router", 24) + pad("Correct", 16) + pad("Wrong press", 13) + pad("Median", 10) + "Slowest 1 in 10")
        print(pad("Rules + fuzzy (Mac)", 24) + pad(pct(rows.filter(\.rulesOK).count), 16) + pad("\(rows.filter(\.rulesWrong).count)", 13)
              + pad(Stats.ms(Stats.median(rows.map(\.rulesMs))), 10) + Stats.ms(Stats.percentile(rows.map(\.rulesMs), 0.9)))
        if jev != nil {
            let jevMs = rows.compactMap(\.jevMs)
            print(pad("Jev for press commands", 24) + pad(pct(rows.filter(\.jevOK).count), 16) + pad("\(rows.filter(\.jevWrong).count)", 13)
                  + pad(Stats.ms(Stats.median(jevMs)), 10) + Stats.ms(Stats.percentile(jevMs, 0.9)))
            print(pad("Rules, Jev if unsure", 24) + pad(pct(rows.filter(\.hybridOK).count), 16) + pad("\(rows.filter(\.hybridWrong).count)", 13)
                  + pad(Stats.ms(Stats.median(rows.map(\.hybridMs))), 10) + Stats.ms(Stats.percentile(rows.map(\.hybridMs), 0.9)))
        }
        let sure = rows.filter(\.rulesSure)
        print("\nRules were sure for \(sure.count) of \(total) commands, and right for \(sure.filter(\.rulesOK).count) of those.")
        print("Risky elements not blocked: \(rows.filter(\.riskyMissed).count) of \(rows.filter { $0.kind == "risky" }.count).")
        print("\nBy kind (rules / jev / hybrid):")
        for kind in Array(Set(rows.map(\.kind))).sorted() {
            let k = rows.filter { $0.kind == kind }
            print("  \(pad(kind, 10)) \(k.filter(\.rulesOK).count) / \(k.filter(\.jevOK).count) / \(k.filter(\.hybridOK).count) of \(k.count)")
        }
        return 0
    }

    // MARK: - e2-act: live run (presses links, types into search fields, scrolls)

    /// The address without the part after "#".
    static func bare(_ u: String) -> String { u.split(separator: "#", maxSplits: 1).first.map(String.init) ?? u }

    /// Presses the Back button of the browser, and waits for the start page.
    static func goBack(_ app: AXUIElement, to start: String, bundle: String) async -> String {
        if let w = AX.window(app), let b = WebPage.backButton(in: w), let f = AX.frame(b) {
            _ = WebPage.press(b, frame: f, browserPid: AX.pid(app))
            if await waitUntil(timeoutMs: 4000, intervalMs: 100, { bare(WebPage.currentURL(app) ?? "") == bare(start) }) {
                await sleepMs(700)
                return "back"
            }
        }
        // A link that opened a new tab: open the start page again.
        if let url = URL(string: start), let host = url.host {
            WebPage.open(url, bundleID: bundle, activate: true)
            if await WebPage.waitForPage(app, host: host), bare(WebPage.currentURL(app) ?? "") == bare(start) {
                await sleepMs(700)
                return "opened again"
            }
        }
        return "failed"
    }

    /// The longest wait for Jev in the live run. Jev took 106 ms (median) and 168 ms (slowest 1 in 10) in e2-run.
    static let jevBudgetMs = 1000
    static let liveKinds: Set<String> = ["exact", "free", "partial", "misheard", "ordinal", "search", "risky", "unknown", "scroll", "none"]
    static let pageDown = Keys.Combo(key: CGKeyCode(0x79), flags: [])
    static let home = Keys.Combo(key: CGKeyCode(0x73), flags: [])

    static func act(_ args: [String]) async throws -> Int32 {
        guard AX.trusted(prompt: true) else { throw ProbeError("Accessibility is off. Run: swift run earshot-probe check") }
        let file = try WebPage.loadSites()
        let set = try loadTests()
        let bundle = file.browser
        let only = Set(names(args))
        let jev: JevClient? = args.contains("--no-jev") ? nil : try JevClient()
        let before = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let app = WebPage.browser(bundle) else { throw ProbeError("\(bundle) does not run. Open it first.") }
        let log = try RunLog(kind: "act", experiment: "e2")
        print("E2 live run in \(bundle). It presses links only, never Return, and never a risky label.")
        print("Do not touch the keyboard or the mouse. Log: \(log.url.path)\n")
        if let jev { _ = try await jev.warmUp() }

        struct Row {
            let kind: String
            let ok: Bool
            let decideMs: Double
            let actMs: Double?
            let readMs: Double
        }
        var rows: [Row] = []
        var stop = false
        var pressedCount = 0
        var changeMs: [Double] = []
        for site in file.sites where only.isEmpty || only.contains(site.id) {
            if stop { break }
            guard let url = URL(string: site.url), let host = url.host else { continue }
            let tests = set.tests.filter { $0.site == site.id && liveKinds.contains($0.kind) }
            guard !tests.isEmpty else { continue }
            WebPage.open(url, bundleID: bundle, activate: true)
            guard await WebPage.waitForPage(app, host: host) else {
                print("\(site.id): the page did not load in 10 s. Next site.")
                continue
            }
            await sleepMs(1000)
            guard let start = WebPage.currentURL(app) else { continue }
            let snap = try? WebPage.load(site.id)
            print("== \(site.id) (\(tests.count) commands)")

            for t in tests {
                // The live page can differ from the saved read, so the check compares labels, not ids.
                let wanted = t.expected.map { e -> (String, String) in
                    let label = e.element.flatMap { id in snap?.elements.first(where: { $0.id == id })?.label } ?? ""
                    return (e.action, Text.key(label))
                }
                // Only an ordinal command needs the heading check.
                let headings = WebRouter.parse(t.words).intent == "ordinal"
                // Act only on a page that the hit test found on screen. A page found by the search can be a hidden tab.
                if let check = WebPage.read(app, headings: false), check.areaPath != "hit test" {
                    _ = await bringToFront(bundle)
                    await sleepMs(500)
                }
                let t0 = Clock.nowNs()
                guard let read = WebPage.read(app, headings: headings) else {
                    print("  no page in the front window. The run stops.")
                    stop = true
                    break
                }
                guard read.areaPath == "hit test" else {
                    print("  the page is not on screen (found by \(read.areaPath) only). The run stops, so that no hidden tab gets a press.")
                    stop = true
                    break
                }
                // Act only on the page of the site, and never on a sign-in, code or payment page (E2 live run 3).
                if let why = WebPage.refuse(read, host: host) {
                    print("  \(why). The run stops. Nothing was done on this page.")
                    stop = true
                    break
                }
                let readMs = Clock.ms(since: t0)
                let r = WebRouter.route(t.words, elements: read.elements)
                var choice = r.rules
                var jevMs: Double?
                var jevNote = ""
                if !r.sure, jevApplies(r), let jev {
                    // Jev gets a time budget. After that time, the rules answer stays (live run 2: one call took 5 s).
                    do {
                        let answer = try await WebRouter.askJev(t.words, r, elements: read.elements, jev: jev, budgetMs: jevBudgetMs)
                        choice = answer.0
                        jevMs = answer.1.ms
                    } catch {
                        jevNote = "Jev: \(error), rules answer used"
                    }
                }
                let decideMs = Clock.ms(since: t0)
                let index = choice.element.flatMap { id in read.elements.firstIndex(where: { $0.id == id }) }
                let picked = index.map { read.elements[$0] }
                // Google results and Hacker News stories change between e2-make and e2-act (live run 2).
                // If the expected label is gone from the live page, the correct answer is "none".
                // For an ordinal command, the position counts, so any press is correct. The label is printed for a check by eye.
                let pressKeys = wanted.filter { $0.0 == "press" && !$0.1.isEmpty }.map { $0.1 }
                let labelGone = !pressKeys.isEmpty && pressKeys.allSatisfy { k in !read.elements.contains { Text.key($0.label) == k } }
                let ok: Bool
                if labelGone {
                    ok = t.kind == "ordinal" ? choice.action == "press" : choice.action == "none"
                } else {
                    ok = wanted.contains { w in
                        w.0 == choice.action && (w.1.isEmpty || w.1 == Text.key(picked?.label ?? ""))
                            && (choice.action != "scroll" || t.expected.contains { $0.text == choice.text })
                    }
                }

                var acted = choice.action
                var actMs: Double?
                var after = ""
                switch choice.action {
                case "press":
                    guard let i = index, let e = picked else { acted = "no element"; break }
                    // Safety rules 1 and 2: links only, never a risky label.
                    if WebRouter.isRisky(e.label) { acted = "blocked"; break }
                    if e.kind != "link" { acted = "not pressed (\(e.kind))"; break }
                    let tp = Clock.nowNs()
                    let press = WebPage.press(read.handles[i], frame: Frame(x: e.x, y: e.y, w: e.w, h: e.h), browserPid: AX.pid(app))
                    actMs = Clock.ms(since: tp)
                    guard press.done else { acted = "not pressed (\(press.way))"; break }
                    acted = "pressed (\(press.way))"
                    pressedCount += 1
                    let tc = Clock.nowNs()
                    let changed = await waitUntil(timeoutMs: 4000, intervalMs: 20) { (WebPage.currentURL(app) ?? start) != start }
                    let now = WebPage.currentURL(app) ?? ""
                    after = changed ? "page: \(URL(string: now)?.host ?? now)\(bare(now) == bare(start) ? " (same page)" : "")" : "no page change in 4 s"
                    if changed {
                        // From the press to the new address in the visible tab.
                        changeMs.append((actMs ?? 0) + Clock.ms(since: tc))
                        let back = await goBack(app, to: start, bundle: bundle)
                        after += ", \(back)"
                        if back == "failed" {
                            print("  could not get back to the start page. The run stops.")
                            stop = true
                        }
                    }
                case "type":
                    guard let i = index, let e = picked, e.isSearchField else { acted = "not typed (not a search field)"; break }
                    let field = read.handles[i]
                    let text = Text.printable(choice.text ?? "")
                    let tp = Clock.nowNs()
                    AX.set(field, "AXFocused", kCFBooleanTrue)
                    let wasSet = AX.set(field, "AXValue", text as CFString)
                    actMs = Clock.ms(since: tp)
                    acted = wasSet && Text.normalize(AX.value(field) ?? "") == Text.normalize(text) ? "typed (value)" : "type failed"
                    // Fallback: type the words as key events, only if the focus is in that field.
                    // Key events never hold Return: Keys.type removes control characters.
                    var typedKeys = false
                    if acted == "type failed", await waitUntil(timeoutMs: 500, { AX.same(AX.focused(app), field) }) {
                        let tk = Clock.nowNs()
                        Keys.type(text)
                        typedKeys = true
                        let shown = await waitUntil(timeoutMs: 1000) { Text.normalize(AX.value(field) ?? "") == Text.normalize(text) }
                        actMs = Clock.ms(since: tk)
                        acted = shown ? "typed (keys)" : "type failed (keys too)"
                    }
                    // Empty the field and move the focus back to the page. No Return.
                    AX.set(field, "AXValue", "" as CFString)
                    if typedKeys, !(AX.value(field) ?? "").isEmpty, AX.same(AX.focused(app), field) {
                        Keys.press(Keys.selectAll)
                        Keys.press(Keys.deleteKey)
                    }
                    Keys.press(Keys.escape)
                    if let w = AX.window(app), let area = WebPage.webArea(in: w) { AX.set(area, "AXFocused", kCFBooleanTrue) }
                    await sleepMs(300)
                case "scroll":
                    if let f = AX.focused(app), AX.textRoles.contains(AX.role(f)),
                       let w = AX.window(app), let area = WebPage.webArea(in: w) {
                        AX.set(area, "AXFocused", kCFBooleanTrue)
                    }
                    // "Go to the top" on a page that is at the top shows no change. Scroll down first (not timed).
                    var firstBefore = read.elements.first.map { "\($0.label)@\(Int($0.y))" } ?? ""
                    if choice.text == "top" || choice.text == "up" {
                        Keys.press(pageDown)
                        await sleepMs(500)
                        firstBefore = WebPage.read(app, headings: false)?.elements.first.map { "\($0.label)@\(Int($0.y))" } ?? ""
                    }
                    let tp = Clock.nowNs()
                    Keys.press(choice.text == "top" || choice.text == "up" ? home : pageDown)
                    actMs = Clock.ms(since: tp)
                    await sleepMs(500)
                    let firstAfter = WebPage.read(app)?.elements.first.map { "\($0.label)@\(Int($0.y))" } ?? ""
                    acted = firstAfter != firstBefore ? "scrolled" : "scroll: no change seen"
                    Keys.press(home)
                    await sleepMs(400)
                default:
                    break
                }

                rows.append(Row(kind: t.kind, ok: ok, decideMs: decideMs, actMs: actMs, readMs: readMs))
                var entry: [String: Any] = [
                    "event": "act", "id": t.id, "site": t.site, "kind": t.kind, "words": t.words,
                    "choice": choice.dictionary, "picked": picked?.label ?? "", "picked_kind": picked?.kind ?? "",
                    "ok": ok, "sure": r.sure, "why": r.why, "acted": acted, "after": after,
                    "read_ms": readMs, "elements": read.elements.count, "method": read.method, "page_by": read.areaPath,
                    "route_ms": r.ms, "decide_ms": decideMs,
                ]
                if let jevMs { entry["jev_ms"] = jevMs }
                if !jevNote.isEmpty { entry["jev_note"] = jevNote }
                if labelGone { entry["label_gone"] = true }
                if let actMs { entry["act_ms"] = actMs }
                log.write(entry)
                let total = decideMs + (actMs ?? 0)
                print("  \(pad("\(t.id).", 4))\(ok ? "✓" : "✗") [\(t.kind)] \(t.words)  →  \(choice.describe(read.elements)) · \(acted)"
                      + " · read \(Int(readMs.rounded())) + route \(String(format: "%.1f", r.ms))\(jevMs.map { " + jev \(Int($0.rounded()))" } ?? "")"
                      + " + act \(Int((actMs ?? 0).rounded())) = \(Int(total.rounded())) ms\(after.isEmpty ? "" : " · \(after)")"
                      + (labelGone ? " · the expected label is gone from the page" : "") + (jevNote.isEmpty ? "" : " · \(jevNote)"))
                if stop { break }
                await sleepMs(400)
            }
        }
        if let id = before { _ = await bringToFront(id) }

        let total = rows.count
        let acted = rows.filter { $0.actMs != nil }
        print("\nSummary: \(rows.filter(\.ok).count) of \(total) correct.")
        print("Read the page: median \(Stats.ms(Stats.median(rows.map(\.readMs)))), slowest 1 in 10 \(Stats.ms(Stats.percentile(rows.map(\.readMs), 0.9))).")
        let toAction = acted.map { $0.decideMs + ($0.actMs ?? 0) }
        print("Text to action (read, route, Jev if unsure, act): median \(Stats.ms(Stats.median(toAction))), slowest 1 in 10 \(Stats.ms(Stats.percentile(toAction, 0.9))), \(acted.count) actions.")
        print("Links pressed: \(pressedCount). Page changed: \(changeMs.count)"
              + (changeMs.isEmpty ? "." : ", median \(Stats.ms(Stats.median(changeMs))) from the press to the new address."))
        print("Pages stay open in new tabs. Nothing was submitted.")
        return 0
    }
}
