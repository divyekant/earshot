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
        var context = RouteContext(apps: rows, names: await allNames(), frontBundleID: frontBundleID())
        let screenClock = Stopwatch()
        context.screen = await actions.screen()
        stages["screen"] = screenClock.ms

        let routeClock = Stopwatch()
        var result = await router.route(text, context: context)
        stages["route"] = routeClock.ms

        // A name that no known chat explains: ask the app's own search once, then route again (E1).
        if let heard = heardName(text, context), let appID = heard.appID ?? Self.appID(of: result.intent) {
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
            return done(heard: text, intent: describe, tier: result.tier, ok: false, note: note, stages: stages, clock)
        }

        var intent = result.intent
        if mode == .alwaysOn, intent == .send, !maySend { intent = .none }
        if intent == .none {
            return done(heard: text, intent: "none", tier: result.tier, ok: false, note: "not a command", stages: stages, clock)
        }

        let types = Self.types(intent)
        if types { pauseAlwaysOn(true) }
        let command = CommandInfo(mode: mode, tier: result.tier, spokenTarget: CommandRouter.spokenTarget(text))
        let outcome = await actions.run(intent, context: context, command: command)
        if types { pauseAlwaysOn(false) }
        for (k, v) in outcome.stages { stages["action." + k] = v }
        lastCommandAt = Date()
        return done(heard: text, intent: describe, tier: result.tier, ok: outcome.ok, note: outcome.note, stages: stages, clock)
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
                      stages: [String: Double], _ clock: Stopwatch, quiet: Bool = false) -> ActivityRecord {
        var stages = stages
        stages["total"] = clock.ms
        let record = ActivityRecord(heard: heard, intent: intent, tier: tier, ok: ok, note: note, stages: stages)
        try? log?.append(record)
        if showFeedback, !quiet {
            feedback?.show(ok ? "→ \(intent)" : "✗ \(note)", ok: ok)
        }
        return record
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
