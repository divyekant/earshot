import EarshotActions
import EarshotCore
import EarshotInput
import EarshotRouter
import EarshotUI
import Foundation

// T7: the command path. Speech → "for me?" gate → router → (app search) → actions → note and log.
// The pipeline uses protocols, so that the unit tests can give fake engines and runners.

/// The action module as the pipeline uses it. EarshotActionRunner is the real one.
protocol CommandActions: AnyObject {
    func screen() async -> ScreenSnapshot?
    func run(_ intent: Intent, context: RouteContext, command: CommandInfo) async -> ActionOutcome
}

extension EarshotActionRunner: CommandActions {}

/// The time from a start point, in ms.
struct Stopwatch {
    let t0 = DispatchTime.now().uptimeNanoseconds
    var ms: Double { Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000 }
}

final class CommandPipeline {
    var engine: SpeechEngine
    var router: Router
    let actions: CommandActions
    let names: NameFinder
    var feedback: FeedbackSink?
    var log: ActivityLog?
    var showFeedback = true
    /// The catalogue rows. The pipeline uses only approved, enabled rows.
    var apps: () -> [AppEntry]
    var allNames: () async -> [NameEntry]
    var frontBundleID: () -> String?
    /// Pauses always-on while earshot types, so that earshot does not hear its own typing.
    var pauseAlwaysOn: (Bool) -> Void = { _ in }
    var heardName: (String, RouteContext) -> (name: String, appID: String?)? = CommandRouter.heardName
    var gate = ForMeGate()
    private var lastCommandAt: Date?

    init(engine: SpeechEngine, router: Router, actions: CommandActions, names: NameFinder,
         apps: @escaping () -> [AppEntry], allNames: @escaping () async -> [NameEntry],
         frontBundleID: @escaping () -> String?) {
        self.engine = engine; self.router = router; self.actions = actions; self.names = names
        self.apps = apps; self.allNames = allNames; self.frontBundleID = frontBundleID
    }

    /// The input opened a turn (key down, or speech start in always-on).
    func begin() -> String? {
        do { try engine.begin(); return nil } catch { return "speech did not start: \(error)" }
    }

    /// The input dropped the turn. The text is not used.
    func cancel() async { _ = try? await engine.end() }

    /// The input closed the turn (key up, or end of speech). Runs the whole command, and returns the log record.
    @discardableResult
    func finish(mode: InputMode) async -> ActivityRecord {
        let clock = Stopwatch()
        var stages: [String: Double] = [:]
        let text: String
        do {
            text = try await engine.end().text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return done(heard: "", intent: "none", tier: .none, ok: false, note: "speech error: \(error)", stages: stages, clock)
        }
        stages["speech"] = clock.ms
        guard !text.isEmpty else { return done(heard: "", intent: "none", tier: .none, ok: false, note: "no words", stages: stages, clock, quiet: true) }

        // Always-on: is it for earshot? (R-ON-2, R-ON-5)
        var maySend = true
        if mode == .alwaysOn {
            let since = lastCommandAt.map { Date().timeIntervalSince($0) }
            switch gate.check(text, apps: apps(), secondsSinceLastCommand: since) {
            case .notForMe(let why):
                return done(heard: text, intent: "none", tier: .none, ok: false, note: "not for earshot: \(why)", stages: stages, clock, quiet: true)
            case .forMe(_, let send, _):
                maySend = send
            }
        }

        let rows = apps().filter { $0.approved && $0.enabled }
        // The names and the screen read do not depend on each other, so they run side by side.
        // Each keeps its own timer. "context" is the wall time of both together.
        let contextClock = Stopwatch()
        async let namesTimed: ([NameEntry], Double) = { let c = Stopwatch(); let n = await allNames(); return (n, c.ms) }()
        async let screenTimed: (ScreenSnapshot?, Double) = { let c = Stopwatch(); let s = await actions.screen(); return (s, c.ms) }()
        let (known, namesMs) = await namesTimed
        let (screen, screenMs) = await screenTimed
        stages["names"] = namesMs
        stages["screen"] = screenMs
        stages["context"] = contextClock.ms
        var context = RouteContext(apps: rows, names: known, frontBundleID: frontBundleID(), screen: screen)

        let routeClock = Stopwatch()
        var result = await router.route(text, context: context)
        stages["route"] = routeClock.ms

        // A name that no known chat explains: ask the app's own search once, then route again (E1).
        // Only when the route is not sure or is not a chat, and never for the owner's own chat: the search types
        // into the app, and in the first live test it searched Slack for the message words ("running late").
        if Self.needsAppSearch(text, result),
           let heard = heardName(text, context), let appID = heard.appID ?? Self.appID(of: result.intent) {
            let searchClock = Stopwatch()
            let found = await names.search(appID: appID, term: heard.name)
            stages["search"] = searchClock.ms
            if !found.isEmpty {
                context.names += found
                result = await router.route(text, context: context)
            }
        }

        let describe = IntentText.describe(result.intent, apps: rows, screen: context.screen)
        if result.confidence < SafetyPolicy.minimumConfidence {
            let options = result.alternatives.prefix(2).map { IntentText.describe($0, apps: rows, screen: context.screen) }
            let note = (["not sure: \(result.why)"] + options.map { "maybe \($0)" }).joined(separator: " · ")
            return done(heard: text, intent: describe, tier: result.tier, ok: false, note: note, stages: stages, clock, why: result.why)
        }

        var intent = result.intent
        if mode == .alwaysOn, intent == .send, !maySend { intent = .none }
        if intent == .none {
            return done(heard: text, intent: "none", tier: result.tier, ok: false, note: "not a command", stages: stages, clock, why: result.why)
        }

        let types = Self.types(intent)
        if types { pauseAlwaysOn(true) }
        let command = CommandInfo(mode: mode, tier: result.tier, spokenTarget: CommandRouter.spokenTarget(text))
        let outcome = await actions.run(intent, context: context, command: command)
        if types { pauseAlwaysOn(false) }
        for (k, v) in outcome.stages { stages["action." + k] = v }
        lastCommandAt = Date()
        return done(heard: text, intent: describe, tier: result.tier, ok: outcome.ok, note: outcome.note, stages: stages, clock, why: result.why)
    }

    /// The Test tab: route typed text, and run the actions only if `runActions` is true. A typed command counts as a
    /// hold-key command, because the owner typed it on purpose.
    func test(_ text: String, runActions: Bool) async -> TestReport {
        let rows = apps().filter { $0.approved && $0.enabled }
        var context = RouteContext(apps: rows, names: await allNames(), frontBundleID: frontBundleID())
        context.screen = await actions.screen()
        let result = await router.route(text, context: context)
        guard runActions, result.confidence >= SafetyPolicy.minimumConfidence, result.intent != .none else {
            return TestReport(heard: text, route: result)
        }
        let command = CommandInfo(mode: .hold, tier: result.tier, spokenTarget: CommandRouter.spokenTarget(text))
        return TestReport(heard: text, route: result, outcome: await actions.run(result.intent, context: context, command: command))
    }

    private func done(heard: String, intent: String, tier: RouterTier, ok: Bool, note: String,
                      stages: [String: Double], _ clock: Stopwatch, quiet: Bool = false, why: String = "") -> ActivityRecord {
        var stages = stages
        stages["total"] = clock.ms
        // The log keeps the router's reason too, so that a wrong intent can be explained later
        // (for example "open Slack" when Slack had no chat keys). The note on screen stays short.
        let logNote = why.isEmpty || note.contains(why) ? note : "\(note) · route: \(why)"
        let record = ActivityRecord(heard: heard, intent: intent, tier: tier, ok: ok, note: logNote, stages: stages)
        try? log?.append(record)
        if showFeedback, !quiet {
            feedback?.show(ok ? "→ \(intent)" : "✗ \(note)", ok: ok)
        }
        return record
    }

    /// The app search rule (E1, first live test).
    static func needsAppSearch(_ text: String, _ result: RouteResult) -> Bool {
        guard !namesSelf(text) else { return false }
        if case .openChat = result.intent { return result.confidence < CommandRouter.sureConfidence }
        return true
    }

    /// True if the name part names the owner's own chat ("me", "myself", "my own chat").
    /// The name part: the words before the first comma, or, with no comma, the first three words.
    /// So "Slack Ravi, call me later" and "Slack Ravi call me later" do not count: "me" is in the message.
    static func namesSelf(_ text: String) -> Bool {
        let head = text.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? text
        var words = SafetyPolicy.normalize(head).split(separator: " ").map(String.init)
        if !text.contains(",") { words = Array(words.prefix(3)) }
        let set = Set(words)
        return !set.isDisjoint(with: ["me", "myself"]) || (set.contains("my") && set.contains("own"))
    }

    static func appID(of intent: Intent) -> String? {
        switch intent {
        case .openChat(let appID, _, _), .openApp(let appID): return appID
        default: return nil
        }
    }

    /// True if the intent types text, so that always-on must not listen.
    static func types(_ intent: Intent) -> Bool {
        switch intent {
        case .openChat(_, _, let text): return text != nil
        case .typeText, .typeInto: return true
        default: return false
        }
    }
}
