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
    /// The wake of the open always-on turn, for the log and to remove the phrase by time (D-11). Nil for a hold-key
    /// turn, and for a follow-up turn in which the owner did not say the phrase again.
    var pendingWake: WakeHit?
    /// The voice score of the follow-up turn that ends now (WakeTrigger.lastFollowUpVoiceScore). Nil if no check ran.
    var followUpVoiceScore: Double?
    /// The last typing that worked: the time and the front app. In always-on mode, "send" alone may follow it
    /// within `sendAfterTypingSeconds`, in the same app (the owner's choice, D-12, R-ON-5).
    private(set) var lastTyped: (at: Date, app: String?)?
    static let sendAfterTypingSeconds: TimeInterval = 5
    /// After earshot typed in always-on mode, a turn that starts within this time goes on with the text.
    static let continueTypingSeconds: TimeInterval = 3
    /// True if the last typing was in always-on mode.
    private var lastTypedAlwaysOn = false
    /// True if the next turn is expected to hold dictated text (armed, or right after typing in always-on). The app
    /// gives it to the trigger, so that turn gets the long end silence (WakeTrigger.dictationEndSilenceMs).
    private(set) var expectsText = false
    /// A short sound for each result, if `playSounds`. The app plays a system sound (NSSound).
    var playSound: ((FeedbackSound) -> Void)?
    var playSounds = true
    /// The result sound of the last record, if one played. The app mutes the always-on detector for its length.
    private(set) var lastSound: FeedbackSound?
    /// True if typing worked in this turn. When earshot waits for the owner's words next (after "type", or after a
    /// typing), it plays no result sound and mutes nothing: the note on screen is the cue, and the owner may go on
    /// talking at once (go-on typing, the text after "type", or "send").
    private var typedThisTurn = false
    /// True if a send worked in this turn, for the "sent" sound.
    private var sentThisTurn = false
    /// The start of the open turn (begin()). The armed window and the send window test the start of the next turn,
    /// so a long sentence that starts in time still counts (live test: a 9.7 s sentence after "type" was lost).
    private var turnStartedAt: Date?
    /// The number of chat apps whose names were not ready within the names budget in this command.
    var namesNotReady: () -> Int = { 0 }
    /// The cached menu items of an app as screen elements (MenuCache.cached). It must not read: a menu read takes up to 1 s.
    var menus: (String) -> [ScreenElement] = { _ in [] }
    /// If earshot's own window is in front, brings back the app that was in front before it, and returns the time
    /// in ms. Nil if earshot was not in front (FrontTracker.restore).
    var restoreFront: () async -> Double? = { nil }
    /// earshot's own bundle id. earshot's own window is never a target of a voice command.
    var ownBundleID: String?
    /// After a bare "type" (RouteResult.awaitsText), the end of the window in which the next turn types its words
    /// into the focused field (the owner's choice, R-NV-4). One turn only. Nil when not armed.
    private(set) var armedUntil: Date?
    static let armedSeconds: TimeInterval = 5
    /// The clock, for the tests.
    var now: () -> Date = Date.init
    /// The screenshot picker (D-10). Nil is off, the default (ScreenPickerFactory.make).
    var picker: ScreenPicker?
    /// The longest wait for the screenshot fallback (settings.jevScreenBudgetMs).
    var jevScreenBudgetMs = 1500
    /// The speech engine's line for the log of the current command (engine, why, audio length).
    private var speechSummary = ""
    /// The turn model checks of the open always-on turn, for its log note (R-ON-1, I-2).
    private var turnChecks: [String] = []

    init(engine: SpeechEngine, router: Router, actions: CommandActions, names: NameFinder,
         apps: @escaping () -> [AppEntry], allNames: @escaping () async -> [NameEntry],
         frontBundleID: @escaping () -> String?) {
        self.engine = engine; self.router = router; self.actions = actions; self.names = names
        self.apps = apps; self.allNames = allNames; self.frontBundleID = frontBundleID
    }

    /// The input opened a turn (key down, or speech start in always-on).
    func begin() -> String? {
        turnStartedAt = now()
        turnChecks = []
        do { try engine.begin(); return nil } catch { return "speech did not start: \(error)" }
    }

    /// The input dropped the turn. The text is not used.
    func cancel() async {
        turnStartedAt = nil
        turnChecks = []
        _ = try? await engine.end()
    }

    /// The input closed the turn (key up, or end of speech). Runs the whole command, and returns the log record.
    @discardableResult
    func finish(mode: InputMode) async -> ActivityRecord {
        let clock = Stopwatch()
        // A finish with no begin (the tests, the Test tab) starts now.
        let started = turnStartedAt ?? now()
        turnStartedAt = nil
        expectsText = false
        sentThisTurn = false
        typedThisTurn = false
        speechSummary = ""  // a speech error must not show the line of the last command
        var stages: [String: Double] = [:]
        let wake = mode == .alwaysOn ? pendingWake : nil
        pendingWake = nil
        let followScore = followUpVoiceScore
        followUpVoiceScore = nil
        let checks = turnChecks
        turnChecks = []
        // The voice of an always-on turn was checked: a wake in the owner's voice, or a follow-up with a score.
        let ownerVoice = mode == .alwaysOn && (wake.map { $0.voiceScore != nil && $0.isOwner } ?? (followScore != nil))
        var text: String
        var words: [TimedWord] = []
        do {
            let heard = try await engine.end()
            text = heard.text.trimmingCharacters(in: .whitespacesAndNewlines)
            words = heard.words
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
            let removed = Self.removePhrase(text, words: words, wake: wake, phrase: wakePhrase)
            text = removed.text
            if let wake {
                speechSummary = Self.wakeSummary(wake) + ", phrase removed " + removed.how
                    + (speechSummary.isEmpty ? "" : " · " + speechSummary)
            }
            if !checks.isEmpty {
                speechSummary += (speechSummary.isEmpty ? "" : " · ") + "turn: " + checks.joined(separator: "; ")
            }
        }
        guard !text.isEmpty else { return done(heard: "", intent: "none", tier: .none, ok: false, note: "no words", stages: stages, clock, quiet: true) }

        let rows = apps().filter { $0.approved && $0.enabled }
        // The names and the screen read do not depend on each other, so they run side by side.
        // Each keeps its own timer. "context" is the wall time of both together.
        // Live test: the Manage window was in front, so "type …" found no text field. Act on the app before it.
        if let ms = await restoreFront() { stages["front.restore"] = ms }
        let contextClock = Stopwatch()
        async let namesTimed: ([NameEntry], Double) = { let c = Stopwatch(); let n = await allNames(); return (n, c.ms) }()
        async let screenTimed: (ScreenSnapshot?, Double) = { let c = Stopwatch(); let s = await actions.screen(); return (s, c.ms) }()
        let (known, namesMs) = await namesTimed
        let (seen, screenMs) = await screenTimed
        let screen = seen?.bundleID == ownBundleID ? nil : seen
        stages["names"] = namesMs
        let notReady = namesNotReady()
        stages["screen"] = screenMs
        stages["context"] = contextClock.ms
        let front = frontBundleID().flatMap { $0 == ownBundleID ? nil : $0 }
        var context = RouteContext(apps: rows, names: known, frontBundleID: front, screen: withMenus(screen, front: front))

        // A bare "type" armed this turn: its words go into the focused field, unless its first sentence is a command.
        // A command word later in the text is text. One turn only. A voice that the wake check dropped never
        // reaches this point, so it does not disarm.
        if let until = armedUntil {
            armedUntil = nil
            if started <= until, !CommandRouter.startsWithCommand(text, context: context) {
                return await typeArmed(text, mode: mode, context: context, rows: rows, stages: stages, clock)
            }
        }
        // After earshot typed in always-on mode, a turn that starts within `continueTypingSeconds` in the same app,
        // with no command in its first sentence, goes on with the text (one space before it, never Return).
        if mode == .alwaysOn, lastTypedAlwaysOn, let t = lastTyped, t.app != nil, t.app == front,
           started <= t.at.addingTimeInterval(Self.continueTypingSeconds),
           !CommandRouter.startsWithCommand(text, context: context) {
            return await typeArmed(text, mode: mode, context: context, rows: rows, stages: stages, clock, continues: true)
        }

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

        // A bare "type": wait for the text in the next turn (hold key, or the owner's voice in always-on mode).
        if result.awaitsText {
            armedUntil = now().addingTimeInterval(Self.armedSeconds)
            expectsText = true
            stages["dictation.armed"] = Self.armedSeconds * 1000
            return done(heard: text, intent: "type: waiting for the text", tier: result.tier, ok: true,
                        note: "say the text to type", stages: stages, clock, why: result.why)
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
        // Dictation (the owner's choice): plain words with no command word go into the focused text field.
        // Only with the hold key. Never into a password field or on a sign-in, code or payment page. Never Return.
        if mode == .hold, result.intent == .none, !sensitive, Self.dictationField(context.screen) != nil,
           !CommandRouter.hasCommandWord(text, context: context) {
            why += " · dictation into the focused field"
            // A trailing "and send" is never text (router contract): type the rest, then send with the hold key.
            let body = CommandRouter.withoutTrailingSend(text)
            pauseAlwaysOn(true)
            let outcome = await actions.run(.typeText(body ?? text), context: context, command: CommandInfo(mode: .hold, tier: .rules))
            pauseAlwaysOn(false)
            for (k, ms) in outcome.stages { stages["action." + k] = ms }
            if outcome.ok { noteTyped(mode: .hold) }
            var (ok, note) = (outcome.ok, outcome.note)
            if body != nil, outcome.ok { (ok, note) = await sendAfterTyping(mode: .hold, note: note, context: context, stages: &stages) }
            return done(heard: text, intent: IntentText.describe(.typeText(body ?? text), apps: rows, screen: context.screen),
                        tier: .rules, ok: ok, note: note, stages: stages, clock, why: why)
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
        // A false wake must never send (R-ON-5, R-NV-5). In always-on mode, "send" alone sends only in the checked
        // voice of the owner, within 5 s after earshot typed in the same app (D-12). The action rules check it again.
        var ownerSend = false
        if mode == .alwaysOn, intent == .send {
            if let block = Self.alwaysOnSendBlock(ownerVoice: ownerVoice, lastTyped: lastTyped, now: started, front: front) {
                return done(heard: text, intent: describe, tier: result.tier, ok: false, note: block, stages: stages, clock, why: why)
            }
            ownerSend = true
        }
        if intent == .none {
            return done(heard: text, intent: "none", tier: result.tier, ok: false, note: "not a command", stages: stages, clock, why: why)
        }

        let types = Self.types(intent)
        if types { pauseAlwaysOn(true) }
        let command = CommandInfo(mode: mode, tier: result.tier, spokenTarget: CommandRouter.spokenTarget(text),
                                  ownerSendAfterTyping: ownerSend)
        let outcome = await actions.run(intent, context: context, command: command)
        if types { pauseAlwaysOn(false) }
        for (k, v) in outcome.stages { stages["action." + k] = v }
        if intent == .send { lastTyped = nil; sentThisTurn = outcome.ok }
        if types, outcome.ok { noteTyped(mode: mode) }
        var (ok, note) = (outcome.ok, outcome.note)
        // "type X and send" (RouteResult.sendAfter): the router removed the send words. Type, then send.
        if result.sendAfter, types, outcome.ok {
            (ok, note) = await sendAfterTyping(mode: mode, note: note, context: context, stages: &stages)
        }
        return done(heard: text, intent: describe, tier: result.tier, ok: ok, note: note, stages: stages, clock, why: why)
    }

    /// Removes the wake phrase from the text of an always-on turn (D-11).
    /// - With a wake and word times, it cuts by time: the words before the end of the phrase go, whatever the speech
    ///   engine wrote for the phrase ("Yeah, let's" for "hey atlas"). Then the text strip removes what the cut left of
    ///   a phrase, but it may not take a loose last word: the phrase was before the cut.
    /// - Else, the text strip alone (Parakeet and dictation have no word times; a follow-up turn has no wake).
    /// - Returns: the text, and how the phrase went, for the log ("by time at 0.42 s", "by text").
    static func removePhrase(_ text: String, words: [TimedWord], wake: WakeHit?, phrase: String) -> (text: String, how: String) {
        if let wake, let rest = WakePhrase.cut(words, phraseEnd: wake.phraseEndInTurn) {
            let how = String(format: "by time at %.2f s", wake.phraseEndInTurn)
            return (WakePhrase.strip(rest, phrase: phrase, afterWake: false), how)
        }
        return (WakePhrase.strip(text, phrase: phrase, afterWake: wake != nil), "by text")
    }

    /// Logs the partial matches of the wake phrase that did not fire (D-11), for the next test of the phrase.
    /// The record has only a count and the best part of the phrase: no audio and no text.
    @discardableResult
    func nearMisses(_ misses: NearMisses) -> ActivityRecord {
        let note: String
        if let score = misses.bestScore {
            note = String(format: "wake phrase near misses: %ld, best template score %.2f", misses.count, score)
        } else {
            note = String(format: "wake phrase near misses: %ld, best %.0f %% of the phrase pieces", misses.count, misses.best * 100)
        }
        let record = ActivityRecord(heard: "", intent: "none", tier: .none, ok: false, note: note, stages: [:])
        try? log?.append(record)
        return record
    }

    /// Keeps one check of the turn model at a pause (R-ON-1, I-2): numbers only, no audio and no text. The record of
    /// the turn shows the checks in its speech note, so each check does not make a record of its own. The log gives
    /// the threshold for the owner's own turns.
    func turnCheck(_ check: TurnCheck) {
        turnChecks.append(Self.turnCheckSummary(check))
    }

    /// The log text of one turn check, for example "P 0.82 after 300 ms quiet: end, model 3.5 ms".
    static func turnCheckSummary(_ check: TurnCheck) -> String {
        let p = check.probability.map { String(format: "%.2f", $0) } ?? "none"
        return String(format: "P %@ after %.0f ms quiet: %@%@, model %.1f ms",
                      p, check.silenceMs, check.decision.rawValue, check.dictation ? " (dictation)" : "", check.runMs)
    }

    /// The log line of a wake: the voice score, or that no voice is enrolled.
    static func wakeSummary(_ wake: WakeHit) -> String {
        var voice = wake.voiceScore.map { String(format: "voice %.2f", $0) } ?? "voice not checked (not taught)"
        if let score = wake.matchScore {
            voice += String(format: ", match %.2f, worst part %.2f", score, wake.matchWorst ?? -1)
        }
        if let after = wake.inTurnAfterSeconds {
            return String(format: "wake \"%@\" again in a follow-up turn at %.2f s, %@", wake.phrase, after, voice)
        }
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
        // The phrase matched: say so, so that the owner knows earshot heard it (live test, 19:06).
        if showFeedback { feedback?.show("✗ not sure it was your voice: say \"\(wakePhrase), …\"", ok: false) }
        if playSounds { playSound?(.failed) }
        return record
    }

    /// Types the words of an armed turn into the focused field. The log keeps the word count, not the words.
    /// `continues`: the text goes on after the last typing (always-on), so it gets one space before it.
    private func typeArmed(_ text: String, mode: InputMode, context: RouteContext, rows: [AppEntry], stages: [String: Double],
                           _ clock: Stopwatch, continues: Bool = false) async -> ActivityRecord {
        var stages = stages
        let words = text.split(whereSeparator: \.isWhitespace).count
        let heard = "(\(words) word\(words == 1 ? "" : "s"))"
        let sensitive = context.screen.map { SafetyPolicy.sensitive(url: $0.url, elements: $0.elements) != nil } ?? false
        guard !sensitive, Self.dictationField(context.screen) != nil else {
            let why = sensitive ? "a sign-in, code or payment page" : "no focused text field"
            return done(heard: heard, intent: "none", tier: .rules, ok: false, note: "type: \(why)", stages: stages, clock)
        }
        // A trailing "and send" is never text (router contract).
        let body = CommandRouter.withoutTrailingSend(text)
        pauseAlwaysOn(true)
        // The real mode of the turn, so that a mode rule of the action module also holds here.
        let typed = (continues ? " " : "") + (body ?? text)
        let outcome = await actions.run(.typeText(typed), context: context, command: CommandInfo(mode: mode, tier: .rules))
        pauseAlwaysOn(false)
        for (k, ms) in outcome.stages { stages["action." + k] = ms }
        if outcome.ok { noteTyped(mode: mode) }
        var (ok, note) = (outcome.ok, outcome.note)
        if body != nil, outcome.ok { (ok, note) = await sendAfterTyping(mode: mode, note: note, context: context, stages: &stages) }
        return done(heard: heard, intent: "Type \(words) word\(words == 1 ? "" : "s")", tier: .rules, ok: ok,
                    note: note, stages: stages, clock, why: continues ? "goes on with the last typing" : "armed by \"type\"")
    }

    /// Records a typing that worked, with the front app, for an always-on "send" alone (D-12).
    private func noteTyped(mode: InputMode) {
        lastTyped = (now(), frontBundleID().flatMap { $0 == ownBundleID ? nil : $0 })
        lastTypedAlwaysOn = mode == .alwaysOn
        typedThisTurn = true
        if mode == .alwaysOn { expectsText = true }
    }

    /// After "… and send": with the hold key, send now through the normal send rules. In always-on mode, type
    /// only: the owner says "send" on its own (D-12).
    private func sendAfterTyping(mode: InputMode, note: String, context: RouteContext,
                                 stages: inout [String: Double]) async -> (Bool, String) {
        guard mode == .hold else { return (true, note + " · say \"send\" on its own to send") }
        let out = await actions.run(.send, context: context, command: CommandInfo(mode: .hold, tier: .rules, spokenTarget: "send"))
        for (k, ms) in out.stages { stages["send." + k] = ms }
        lastTyped = nil
        sentThisTurn = out.ok
        return (out.ok, note + " · " + out.note)
    }

    /// The reason to block an always-on "send", or nil (D-12, R-ON-5). It sends only if all are true:
    /// the voice of the turn was checked as the owner's, earshot typed within `sendAfterTypingSeconds`, and the front
    /// app is the app of the typing.
    static func alwaysOnSendBlock(ownerVoice: Bool, lastTyped: (at: Date, app: String?)?, now: Date, front: String?) -> String? {
        let rule = "send needs the hold key, or \"send\" alone in your voice within 5 s after earshot typed"
        guard ownerVoice else { return rule + " (voice not checked)" }
        guard let t = lastTyped else { return rule }
        guard now.timeIntervalSince(t.at) <= sendAfterTypingSeconds else { return rule + " (too late)" }
        guard t.app != nil, t.app == front else { return rule + " (another app is in front)" }
        return nil
    }

    /// The focused text field for dictation: ScreenSnapshot.focusedID (set only for an editable field), and not a
    /// password field.
    static func dictationField(_ screen: ScreenSnapshot?) -> ScreenElement? {
        guard let s = screen, let id = s.focusedID, let e = s.elements.first(where: { $0.id == id }),
              e.subrole != "AXSecureTextField" else { return nil }
        return e
    }

    /// Logs a follow-up turn that earshot dropped because the voice is not the owner's (R-ON-3). Nothing ran.
    /// The record has no text: the words were not the owner's.
    @discardableResult
    func droppedFollowUp(_ why: String, seconds: Double? = nil) -> ActivityRecord {
        let length = seconds.map { String(format: ", audio %.2f s", $0) } ?? ""
        let record = ActivityRecord(heard: "", intent: "none", tier: .none, ok: false, note: "follow-up dropped: \(why)\(length)",
                                    stages: [:])
        try? log?.append(record)
        // The owner may have spoken: say so, and how to go on (dk: "I do not know if send works").
        if showFeedback { feedback?.show("✗ not sure it was your voice: say \"\(wakePhrase), …\"", ok: false) }
        if playSounds { playSound?(.failed) }
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
        lastSound = nil
        if playSounds, !quiet, !(ok && !sentThisTurn && (typedThisTurn || expectsText)) {
            let sound: FeedbackSound = ok ? (sentThisTurn ? .sent : .done) : .failed
            playSound?(sound)
            lastSound = sound
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
        // Live test: "Yeah, let's open the Slack" was a sure openApp, but the extra words ran a 2.1 s search
        // that typed into Slack. Search only when the route is not sure, the same as for a chat.
        case .openApp(let id): return id == appID && result.confidence < CommandRouter.sureConfidence
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

/// The result sounds (dk: "you need to tell me" if a send worked). The app maps them to system sounds.
enum FeedbackSound: String, CaseIterable {
    /// `start`: earshot starts to listen (hold key down, or the wake phrase), as Hex does (dk).
    case start, done, sent, failed

    /// A macOS system sound name (/System/Library/Sounds). No sound files ship with earshot.
    /// The start sound is the shortest one (Tink, 0.56 s), so it is over before most words.
    var systemName: String {
        switch self {
        case .start: return "Tink"
        case .done: return "Morse"
        case .sent: return "Glass"
        case .failed: return "Basso"
        }
    }

    /// The start sound is quiet: the microphone hears it at the start of a hold-key turn.
    var volume: Float { self == .start ? 0.3 : 1 }
}
