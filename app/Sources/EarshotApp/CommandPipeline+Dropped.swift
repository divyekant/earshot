import EarshotCore
import EarshotInput
import EarshotRouter
import Foundation

// Gap item 7 (2026-11-11): a turn that got a start sound never ends with no cue.
// A wake turn passed the phrase gate and played the start sound. Then the voice check of the whole turn dropped it
// (`WakeTrigger.otherVoice`). Before, earshot did nothing that the owner could see or hear. Now it plays a short cue
// and shows a short note, and it keeps the words in memory for `keptSeconds`. One hold-key press with no words then
// types them. Rejected wakes and dropped follow-up turns stay silent: they played no start sound (dk, #92).

/// The words of a dropped wake turn. Only in memory: never in the log and never on disk.
struct KeptText: Equatable {
    var text: String
    var until: Date
}

extension CommandPipeline {
    /// The time in which a hold-key press can type the kept words.
    static let keptSeconds: TimeInterval = 20

    /// The note of the cue.
    static let notMatchedNote = "your voice did not match · press the hold key, say nothing, to type the words"
    static let notMatchedNoWordsNote = "your voice did not match"

    /// True if a dropped turn gets the cue: a wake turn (it played the start sound) that the voice check dropped.
    /// A "too short" follow-up, a rejected wake and a turn that the hold key took over get no cue.
    static func cuesDrop(_ why: String, wake: WakeHit?) -> Bool {
        wake != nil && why.hasPrefix(WakeTrigger.otherVoice)
    }

    /// Ends a wake turn that the voice check dropped: keeps its words (without the wake phrase) for `keptSeconds`,
    /// shows the note and plays the cue. Nothing runs. The log record comes from `droppedTurn`, with no text.
    func dropWakeTurn(_ wake: WakeHit?) async {
        let heard = await cancel()
        let text = heard.map {
            Self.removePhrase($0.text.trimmingCharacters(in: .whitespacesAndNewlines), words: $0.words, wake: wake,
                              phrase: wakePhrase).text
        } ?? ""
        keptText = text.isEmpty ? nil : KeptText(text: text, until: now().addingTimeInterval(Self.keptSeconds))
        if showFeedback { feedback?.show("✗ " + (text.isEmpty ? Self.notMatchedNoWordsNote : Self.notMatchedNote), ok: false) }
        if playSounds { playSound?(.notMatched) }
    }

    /// The kept words if they are still in time. It clears them: they are for the next turn only.
    func takeKeptText() -> KeptText? {
        defer { keptText = nil }
        guard let kept = keptText, now() <= kept.until else { return nil }
        return kept
    }

    /// Types the kept words into the focused text field, with the rules of hold-key dictation: never into a password
    /// field or on a sign-in, code or payment page. It never sends and never presses Return: a trailing "and send" is
    /// not typed, and the note says to say "send". The log keeps the word count, not the words.
    func typeKept(_ kept: KeptText, stages: [String: Double], _ clock: Stopwatch) async -> ActivityRecord {
        var stages = stages
        let words = kept.text.split(whereSeparator: \.isWhitespace).count
        let count = "(\(words) word\(words == 1 ? "" : "s"))"
        let why = "the words of a wake turn that the voice check dropped"
        if let ms = await restoreFront() { stages["front.restore"] = ms }
        let screenClock = Stopwatch()
        let seen = await actions.screen()
        stages["screen"] = screenClock.ms
        let screen = seen?.bundleID == ownBundleID ? nil : seen
        let sensitive = screen.map { SafetyPolicy.sensitive(url: $0.url, elements: $0.elements) != nil } ?? false
        guard !sensitive, Self.dictationField(screen) != nil else {
            let reason = sensitive ? "a sign-in, code or payment page" : "no focused text field"
            return done(heard: count, intent: "none", tier: .rules, ok: false, note: "type: \(reason)", stages: stages,
                        clock, why: why)
        }
        let body = CommandRouter.withoutTrailingSend(kept.text)
        let front = frontBundleID().flatMap { $0 == ownBundleID ? nil : $0 }
        let rows = apps().filter { $0.approved && $0.enabled }
        let context = RouteContext(apps: rows, names: [], frontBundleID: front, screen: screen)
        pauseAlwaysOn(true)
        let outcome = await actions.run(.typeText(body ?? kept.text), context: context,
                                        command: CommandInfo(mode: .hold, tier: .rules))
        pauseAlwaysOn(false)
        for (k, ms) in outcome.stages { stages["action." + k] = ms }
        var note = outcome.note
        if body != nil, outcome.ok { note += " · not sent: say \"send\" to send" }
        return done(heard: count, intent: "Type \(words) word\(words == 1 ? "" : "s")", tier: .rules, ok: outcome.ok,
                    note: note, stages: stages, clock, why: why)
    }
}
