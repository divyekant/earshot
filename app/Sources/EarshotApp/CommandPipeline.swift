import EarshotActions
import EarshotCore
import EarshotInput
import EarshotRouter
import EarshotSpeech
import EarshotUI
import Foundation

// T7: the command path. Speech → (always-on: strip the wake phrase) → router → (app search) → actions → note and log.
// The pipeline uses protocols, so that the unit tests can give fake engines and runners.

/// The action module as the pipeline uses it. EarshotActionRunner is the real one.
protocol CommandActions: AnyObject {
    func screen() async -> ScreenSnapshot?
    func run(_ intent: Intent, context: RouteContext, command: CommandInfo) async -> ActionOutcome
    /// The screenshot fallback (D-10). EarshotActionRunner has it in VisionFallback.swift.
    func visionTarget(_ command: String, mode: InputMode, picker: ScreenPicker, budgetMs: Int) async -> VisionTarget
}

extension CommandActions {
    func visionTarget(_ command: String, mode: InputMode, picker: ScreenPicker, budgetMs: Int) async -> VisionTarget {
        VisionTarget(elementID: nil, label: "", note: "no screenshot fallback", stages: [:])
    }
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
    /// The wake phrase of always-on mode (settings.wakePhrase). The pipeline removes it from the start of the text.
    var wakePhrase = WakePhrase.defaultPhrase
    /// The wake of the open always-on turn, for the log (D-11). Nil for a hold-key turn and a follow-up turn.
    var pendingWake: WakeHit?
    /// The number of chat apps whose names were not ready within the names budget in this command.
    var namesNotReady: () -> Int = { 0 }
    /// The cached menu items of an app as screen elements (MenuCache.cached). It must not read: a menu read takes up to 1 s.
    var menus: (String) -> [ScreenElement] = { _ in [] }
    /// The screenshot picker (D-10). Nil is off, the default (ScreenPickerFactory.make).
    var picker: ScreenPicker?
    /// The longest wait for the screenshot fallback (settings.jevScreenBudgetMs).
    var jevScreenBudgetMs = 1500
    /// The speech engine's line for the log of the current command (engine, why, audio length).
    private var speechSummary = ""

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
        speechSummary = ""  // a speech error must not show the line of the last command
        var stages: [String: Double] = [:]
        let wake = mode == .alwaysOn ? pendingWake : nil
        pendingWake = nil
        var text: String
        do {
            text = try await engine.end().text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return done(heard: "", intent: "none", tier: .none, ok: false, note: "speech error: \(error)", stages: stages, clock)
        }
        stages["speech"] = clock.ms
        // The parts of the speech stage (T1): tail, wait for the model, decode, and the audio length.
        speechSummary = ""
        if let timing = (engine as? SpeechTimingReporting)?.lastTiming {
            stages.merge(timing.stages) { _, new in new }
            stages["speech.audio"] = (timing.audioMs * 10).rounded() / 10
            speechSummary = timing.summary
        }
        if mode == .alwaysOn {
            // The trigger opens an always-on turn only on the wake phrase, or in the follow-up window in the owner's
            // voice (D-11). So the text is for earshot. The speech engine starts before the phrase: remove it.
            if let wake { speechSummary = Self.wakeSummary(wake) + (speechSummary.isEmpty ? "" : " · " + speechSummary) }
            text = WakePhrase.strip(text, phrase: wakePhrase)
        }
        guard !text.isEmpty else { return done(heard: "", intent: "none", tier: .none, ok: false, note: "no words", stages: stages, clock, quiet: true) }

        let rows = apps().filter { $0.approved && $0.enabled }
        // The names and the screen read do not depend on each other, so they run side by side.
        // Each keeps its own timer. "context" is the wall time of both together.
        let contextClock = Stopwatch()
        async let namesTimed: ([NameEntry], Double) = { let c = Stopwatch(); let n = await allNames(); return (n, c.ms) }()
        async let screenTimed: (ScreenSnapshot?, Double) = { let c = Stopwatch(); let s = await actions.screen(); return (s, c.ms) }()
        let (known, namesMs) = await namesTimed
        let (screen, screenMs) = await screenTimed
        stages["names"] = namesMs
        let notReady = namesNotReady()
        stages["screen"] = screenMs
        stages["context"] = contextClock.ms
        let front = frontBundleID()
        var context = RouteContext(apps: rows, names: known, frontBundleID: front, screen: withMenus(screen, front: front))

        let routeClock = Stopwatch()
        var result = await router.route(text, context: context)
        stages["route"] = routeClock.ms

        // A name that no known chat explains: ask the app's own search once, then route again (E1).
        // Only when the route is not sure or is not a chat, and never for the owner's own chat: the search types
        // into the app, and in the first live test it searched Slack for the message words ("running late").
        if let heard = heardName(text, context), let appID = heard.appID, Self.needsAppSearch(text, result, appID: appID) {
            let searchClock = Stopwatch()
            let found = await names.search(appID: appID, term: heard.name)
            stages["search"] = searchClock.ms
            if !found.isEmpty {
                context.names += found
                result = await router.route(text, context: context)
            }
        }

        let describe = IntentText.describe(result.intent, apps: rows, screen: context.screen)
        // For the log only: what earshot saw, and, for a miss, what else it considered.
        var why = result.why
        why += " · " + Self.screenSummary(context.screen, front: context.frontBundleID)
        if notReady > 0 { why += " · names: \(notReady) app\(notReady == 1 ? "" : "s") not ready" }
        let sensitive = context.screen.map { SafetyPolicy.sensitive(url: $0.url, elements: $0.elements) != nil } ?? false
        if (result.intent == .none || result.confidence < SafetyPolicy.minimumConfidence), !sensitive {
            let top = result.alternatives.prefix(3).map { IntentText.describe($0, apps: rows, screen: context.screen) }
            why += String(format: " · confidence %.2f", result.confidence) + (top.isEmpty ? "" : " · considered: " + top.joined(separator: " | "))
        }
        // The screenshot fallback (D-10): one picture to Jev, only for a hold-key press with no sure target that the
        // rules did not block. The click path checks the label again at the tier .jev, so a risky label stays blocked.
        if let picker, mode == .hold, !sensitive, Self.mayAskScreen(text, result) {
            let v = await actions.visionTarget(text, mode: mode, picker: picker, budgetMs: jevScreenBudgetMs)
            for (k, ms) in v.stages { stages["vision." + k] = ms }
            if let id = v.elementID {
                why += " · Jev (screen): \(v.label) (\(v.note))"
                let command = CommandInfo(mode: .hold, tier: .jev, spokenTarget: CommandRouter.spokenTarget(text))
                let outcome = await actions.run(.click(elementID: id), context: context, command: command)
                for (k, ms) in outcome.stages { stages["action." + k] = ms }
                return done(heard: text, intent: "Click \"\(v.label)\" (screen)", tier: .jev, ok: outcome.ok, note: outcome.note,
                            stages: stages, clock, why: why)
            }
            why += " · Jev (screen): \(v.note)"
        }
        if result.confidence < SafetyPolicy.minimumConfidence {
            let options = result.alternatives.prefix(2).map { IntentText.describe($0, apps: rows, screen: context.screen) }
            let note = (["not sure: \(result.why)"] + options.map { "maybe \($0)" }).joined(separator: " · ")
            return done(heard: text, intent: describe, tier: result.tier, ok: false, note: note, stages: stages, clock, why: why)
        }

        let intent = result.intent
        if mode == .alwaysOn, intent == .send {
            // A false wake must never send (R-ON-5, R-NV-5). The action rules block it too (ActionRules.sendBlock).
            return done(heard: text, intent: describe, tier: result.tier, ok: false, note: "send needs the hold key",
                        stages: stages, clock, why: why)
        }
        if intent == .none {
            return done(heard: text, intent: "none", tier: result.tier, ok: false, note: "not a command", stages: stages, clock, why: why)
        }

        let types = Self.types(intent)
        if types { pauseAlwaysOn(true) }
        let command = CommandInfo(mode: mode, tier: result.tier, spokenTarget: CommandRouter.spokenTarget(text))
        let outcome = await actions.run(intent, context: context, command: command)
        if types { pauseAlwaysOn(false) }
        for (k, v) in outcome.stages { stages["action." + k] = v }
        return done(heard: text, intent: describe, tier: result.tier, ok: outcome.ok, note: outcome.note, stages: stages, clock, why: why)
    }

    /// The log line of a wake: the voice score, or that no voice is enrolled.
    static func wakeSummary(_ wake: WakeHit) -> String {
        let voice = wake.voiceScore.map { String(format: "voice %.2f", $0) } ?? "voice not checked (not taught)"
        return String(format: "wake \"%@\", %@, preroll %.2f s", wake.phrase, voice, wake.prerollSeconds)
    }

    /// Logs a wake phrase in a voice that is not the owner's (R-ON-3). Nothing ran. The record has no text,
    /// because the speech engine did not run.
    @discardableResult
    func rejectedWake(_ wake: WakeHit, threshold: Double) -> ActivityRecord {
        let score = wake.voiceScore.map { String(format: "%.2f", $0) } ?? "none"
        let note = String(format: "wake phrase in another voice (score %@, needs %.2f)", score, threshold)
        let record = ActivityRecord(heard: "", intent: "none", tier: .none, ok: false, note: note, stages: [:])
        try? log?.append(record)
        return record
    }

    /// True if the screenshot fallback may run for this route: a press by the router's verb parse, no sure target
    /// (no intent, or an unsure click), and no block. A "blocked: …" route never goes to the screenshot. Never for
    /// send, typing, a chat or an app.
    static func mayAskScreen(_ text: String, _ result: RouteResult) -> Bool {
        guard CommandRouter.isPress(text), !result.why.contains("blocked") else { return false }
        switch result.intent {
        case .none: return true
        case .click: return result.confidence < SafetyPolicy.minimumConfidence
        default: return false
        }
    }

    /// The Test tab: route typed text, and run the actions only if `runActions` is true. A typed command counts as a
    /// hold-key command, because the owner typed it on purpose.
    func test(_ text: String, runActions: Bool) async -> TestReport {
        speechSummary = ""  // a typed command has no speech
        let rows = apps().filter { $0.approved && $0.enabled }
        var context = RouteContext(apps: rows, names: await allNames(), frontBundleID: frontBundleID())
        context.screen = withMenus(await actions.screen(), front: context.frontBundleID)
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
        var logNote = why.isEmpty || note.contains(why) ? note : "\(note) · route: \(why)"
        if !speechSummary.isEmpty { logNote += " · speech: \(speechSummary)" }
        let record = ActivityRecord(heard: heard, intent: intent, tier: tier, ok: ok, note: logNote, stages: stages)
        try? log?.append(record)
        if showFeedback, !quiet {
            feedback?.show(ok ? "→ \(intent)" : "✗ \(note)", ok: ok)
        }
        return record
    }

    /// The screen with the menu items of its app added, so that menu commands use the same matcher (R-MT-1).
    /// With no screen read, a snapshot of the menu items alone.
    func withMenus(_ screen: ScreenSnapshot?, front: String?) -> ScreenSnapshot? {
        guard let app = screen?.bundleID ?? front else { return screen }
        let items = menus(app)
        guard !items.isEmpty else { return screen }
        var s = screen ?? ScreenSnapshot(bundleID: app, windowTitle: "", elements: [])
        s.elements += items
        return s
    }

    /// One line about the screen for the log: the front app, the host (no path, no query) and the element count.
    /// A sign-in, code or payment page shows only "sensitive".
    static func screenSummary(_ screen: ScreenSnapshot?, front: String?) -> String {
        guard let s = screen else { return "screen: none, front \(front ?? "unknown")" }
        if SafetyPolicy.sensitive(url: s.url, elements: s.elements) != nil { return "screen: \(s.bundleID), sensitive" }
        let host = s.url.flatMap { URL(string: $0)?.host }.map { " \($0)" } ?? ""
        let menu = s.elements.filter(MenuElements.isMenu).count
        return "screen: \(s.bundleID)\(host), \(s.elements.count - menu) elements" + (menu > 0 ? ", \(menu) menu items" : "")
    }

    /// The app search rule (E1, first live test).
    /// The search runs only in the chat app that the words name (`appID` comes from `heardName`, never from the
    /// router's guess), when the route opens that same app or a chat in it, and not for garbled words (confidence
    /// below 0.3). A sure chat route needs no search. It never runs for the owner's own chat.
    /// Live test: a garbled Chrome command ran a 5 s search in Slack, because the app came from the router's weak guess.
    static let minimumSearchConfidence = 0.3

    static func needsAppSearch(_ text: String, _ result: RouteResult, appID: String) -> Bool {
        guard !namesSelf(text), result.confidence >= minimumSearchConfidence else { return false }
        switch result.intent {
        case .openChat(let id, _, _): return id == appID && result.confidence < CommandRouter.sureConfidence
        case .openApp(let id): return id == appID
        default: return false
        }
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
