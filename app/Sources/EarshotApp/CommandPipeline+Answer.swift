import EarshotActions
import EarshotCore
import EarshotRouter
import EarshotUI
import Foundation

/// A note that can stay on screen for a set time. FeedbackNote is one. The tests give a fake one.
protocol TimedFeedback {
    func show(_ text: String, ok: Bool, seconds: Double)
}

extension FeedbackNote: TimedFeedback {}

// The answer to a "not sure" note for one command (gap item 5, R-FB-1).
// The note shows at most two choices. For `choiceAnswerSeconds` after it, the next turn can say "yes" or "the first
// one" (choice 1), "the second one" (choice 2), or "no". Other words are a new command. No new verb: the answer
// words act only on a note that waits, the same as the answer to a chain that stopped (I-28).
extension CommandPipeline {
    /// One choice of the note.
    struct Choice: Equatable {
        var intent: Intent
        /// The text of the note, for example "→ Slack · Nadia Brook".
        var describe: String
        /// For a click or a typing into a field: the element of the screen of the note. The answer turn reads the
        /// screen again and finds the same element there.
        var element: ScreenElement?
    }

    /// The choices of a "not sure" note, and what the answer needs. Memory only. It holds the message text of a chat
    /// choice for at most `choiceAnswerSeconds`.
    struct PendingChoice {
        var choices: [Choice]
        /// The input mode of the command. A send needs the hold key in both turns.
        var mode: InputMode
        /// The owner said "and send" after the text (RouteResult.sendAfter).
        var sendAfter: Bool
        /// The words of the target, for the press rules (SafetyPolicy.mayPress).
        var spokenTarget: String
        /// The front app of the note. A click choice needs the same app in front.
        var bundleID: String?
        /// The router's reason, for the log.
        var why: String
        var until: Date
    }

    /// The answer time. The note stays on screen for the same time.
    static let choiceAnswerSeconds: TimeInterval = 10
    static let choiceCount = 2

    /// The answer of the owner to a note.
    enum ChoiceAnswer: Equatable {
        /// The index of the choice, from 0.
        case pick(Int)
        case no
    }

    /// The choices to offer: the router's intent first, then its alternatives. Never a send, never nothing, and never a
    /// press on a risky element (R-NV-5). None on a sign-in, code or payment page.
    static func choices(_ result: RouteResult, rows: [AppEntry], screen: ScreenSnapshot?, sensitive: Bool) -> [Choice] {
        guard !sensitive else { return [] }
        var out: [Choice] = []
        for intent in [result.intent] + result.alternatives where out.count < choiceCount && !out.contains(where: { $0.intent == intent }) {
            var element: ScreenElement?
            switch intent {
            case .none, .send: continue
            case .click(let id), .typeInto(let id, _):
                // A menu item has no screen element. Its id is its path, so it stays the same.
                if MenuElements.path(id) == nil {
                    guard let e = screen?.elements.first(where: { $0.id == id }) else { continue }
                    if e.risky || SafetyPolicy.isRisky(e) { continue }
                    element = e
                }
            default: break
            }
            out.append(Choice(intent: intent, describe: IntentText.describe(intent, apps: rows, screen: screen), element: element))
        }
        return out
    }

    /// The note of a "not sure" command, with its choices, and what the owner can say.
    static func choiceNote(_ why: String, _ choices: [Choice]) -> String {
        let head = "not sure: \(why)"
        switch choices.count {
        case 0: return head
        case 1: return head + " · say \"yes\" for: \(choices[0].describe), or \"no\""
        default:
            let list = choices.enumerated().map { "\($0.offset + 1): \($0.element.describe)" }
            return ([head] + list).joined(separator: " · ") + " · say \"the first one\", \"the second one\" or \"no\""
        }
    }

    /// Words that do not change the answer.
    static let answerFillers: Set<String> = ["ok", "okay", "uh", "um", "hey", "please", "the", "number", "option", "choice",
                                             "then", "now", "thanks", "thank", "you"]
    static let firstWords: Set<String> = ["yes", "yeah", "yep", "yup", "sure", "first", "1st", "1", "one", "top"]
    static let secondWords: Set<String> = ["second", "2nd", "2", "two", "other"]
    static let noWords: Set<String> = ["no", "nope", "neither", "none", "cancel", "stop", "nevermind", "nah"]

    /// The answer in the words, or nil if the words are not an answer (then they are a new command).
    /// "Yes", "the first one", "number one" → choice 1. "The second one", "the other one" → choice 2. "No" → no.
    static func choiceAnswer(_ text: String) -> ChoiceAnswer? {
        var words = SafetyPolicy.normalize(text).split(separator: " ").map(String.init).filter { !answerFillers.contains($0) }
        // "never mind", "do it", "go ahead", "that one", "the first one".
        let phrase = words.joined(separator: " ")
        if ["never mind", "no thanks"].contains(phrase) { return .no }
        if ["do it", "go ahead", "go for it", "yes do it", "yes please do it"].contains(phrase) { return .pick(0) }
        if words.count > 1, words.last == "one" { words.removeLast() }
        // "yes, the second one": the ordinal decides.
        if words.count == 2, ["yes", "yeah", "yep"].contains(words[0]) { words.removeFirst() }
        guard words.count == 1, let w = words.first else { return nil }
        if firstWords.contains(w) { return .pick(0) }
        if secondWords.contains(w) { return .pick(1) }
        if noWords.contains(w) { return .no }
        return nil
    }

    /// The "not sure" result of one command: the note with the choices, and the answer waits for
    /// `choiceAnswerSeconds`. The note stays on screen for the same time.
    func notSure(_ text: String, _ result: RouteResult, mode: InputMode, sensitive: Bool, context: RouteContext,
                 rows: [AppEntry], stages: [String: Double], _ clock: Stopwatch, why: String) -> ActivityRecord {
        let choices = Self.choices(result, rows: rows, screen: context.screen, sensitive: sensitive)
        let describe = IntentText.describe(result.intent, apps: rows, screen: context.screen)
        guard !choices.isEmpty else {
            pendingChoice = nil
            return done(heard: text, intent: describe, tier: result.tier, ok: false, note: Self.choiceNote(result.why, []),
                        stages: stages, clock, why: why)
        }
        pendingChoice = PendingChoice(choices: choices, mode: mode, sendAfter: CommandRouter.withoutTrailingSend(text) != nil,
                                      spokenTarget: CommandRouter.spokenTarget(text),
                                      bundleID: context.screen?.bundleID ?? context.frontBundleID, why: result.why,
                                      until: now().addingTimeInterval(Self.choiceAnswerSeconds))
        return done(heard: text, intent: describe, tier: result.tier, ok: false, note: Self.choiceNote(result.why, choices),
                    stages: stages, clock, why: why, noteSeconds: Self.choiceAnswerSeconds)
    }

    /// The answer to a note that waits. Nil if no note waits, if the time is over, if an always-on turn is not in the
    /// owner's checked voice, or if the words are not an answer: the normal path then takes the words. Each turn
    /// clears the note, so an answer counts one time only.
    func answerChoice(_ text: String, started: Date, mode: InputMode, ownerVoice: Bool, context: RouteContext,
                      rows: [AppEntry], stages: [String: Double], _ clock: Stopwatch) async -> ActivityRecord? {
        guard let pending = pendingChoice else { return nil }
        pendingChoice = nil
        guard started <= pending.until, mode != .alwaysOn || ownerVoice, let answer = Self.choiceAnswer(text) else { return nil }
        let why = "your answer to: not sure (\(pending.why))"
        guard case .pick(let i) = answer else {
            return done(heard: text, intent: "none", tier: .rules, ok: true, note: "OK, nothing done", stages: stages, clock, why: why)
        }
        guard i < pending.choices.count else {
            return done(heard: text, intent: "none", tier: .rules, ok: false,
                        note: "there is only one choice: say the command again", stages: stages, clock, why: why)
        }
        let choice = pending.choices[i]
        guard let intent = Self.refresh(choice, pending: pending, screen: context.screen) else {
            return done(heard: text, intent: choice.describe, tier: .fuzzy, ok: false,
                        note: "the screen changed: say the command again", stages: stages, clock, why: why)
        }
        var stages = stages
        // The tier is never .rules: a choice never presses a risky element (SafetyPolicy.mayPress) and never sends.
        let command = CommandInfo(mode: mode, tier: .fuzzy, spokenTarget: pending.spokenTarget)
        let types = Self.types(intent)
        if types { pauseAlwaysOn(true) }
        let outcome = await actions.run(intent, context: context, command: command)
        if types { pauseAlwaysOn(false) }
        for (k, ms) in outcome.stages { stages["action." + k] = ms }
        if types, outcome.ok { noteTyped(mode: mode) }
        var (ok, note) = (outcome.ok, outcome.note)
        // "… and send": a send needs the hold key in the command and in the answer (R-NV-5). In always-on mode the
        // owner says "send" on its own (D-12): sendAfterTyping only types and says so.
        if pending.sendAfter, types, outcome.ok {
            let sendMode: InputMode = pending.mode == .hold && mode == .hold ? .hold : .alwaysOn
            (ok, note) = await sendAfterTyping(mode: sendMode, note: note, context: context, stages: &stages)
        }
        return done(heard: text, intent: choice.describe, tier: .fuzzy, ok: ok, note: note, stages: stages, clock, why: why)
    }

    /// The intent of a choice on the screen of the answer turn. A click or a typing into a field finds the same
    /// element (role and label) again, in the same front app: the element ids of a new read can change. Nil if the
    /// element is not there, or if it is risky now.
    static func refresh(_ choice: Choice, pending: PendingChoice, screen: ScreenSnapshot?) -> Intent? {
        guard let old = choice.element else { return choice.intent }
        guard let screen, screen.bundleID == pending.bundleID else { return nil }
        let same = screen.elements.filter { $0.role == old.role && $0.label == old.label }
        let near = same.min { abs($0.x - old.x) + abs($0.y - old.y) < abs($1.x - old.x) + abs($1.y - old.y) }
        guard let e = near, !e.risky, !SafetyPolicy.isRisky(e) else { return nil }
        switch choice.intent {
        case .click: return .click(elementID: e.id)
        case .typeInto(_, let text): return .typeInto(elementID: e.id, text: text)
        default: return choice.intent
        }
    }
}
