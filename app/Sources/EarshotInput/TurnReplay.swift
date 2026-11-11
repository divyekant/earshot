import EarshotCore
import Foundation

/// Runs the end-of-turn rules again on the kept levels of a turn (E7). It needs no audio: the detector gets the level
/// of each frame from the record, and the turn model gives the kept probabilities, in the same order.
/// With the config of the live turn, the replay gives the same end as the live turn. With another config, it shows
/// what a change of the rules would do to the owner's real turns.
public enum TurnReplay {
    /// The result of a replay.
    public struct Result: Equatable, Sendable {
        /// The event that ended the turn, or nil if the kept levels end first.
        public var event: SpeechEvent?
        /// How the turn ended, as the detector reports it. Nil after a drop.
        public var end: TurnEnd?
        /// The index in `levels` of the frame that ended the turn.
        public var endFrame: Int?
        /// The answers of the turn model that the replay used.
        public var checks: Int
    }

    /// Replays the end of a wake turn or a follow-up turn. A rejected wake has no turn: the result is empty.
    /// - Parameters:
    ///   - config: the rules. The default is the config of the live trigger.
    ///   - turnScore: the answer of the turn model at the pause with this number (0, 1, …). The default gives the
    ///     kept probabilities. Nil from it means no model: the end silence counts.
    public static func end(of record: TurnRecord, config: WakeConfig = WakeConfig(),
                           turnScore: ((Int) -> Double?)? = nil) -> Result {
        var result = Result(event: nil, end: nil, endFrame: nil, checks: 0)
        guard record.kind != .rejectedWake else { return result }
        let score = turnScore ?? { index in index < record.checks.count ? record.checks[index].probability : nil }
        var detector = SpeechDetector(config: config.detector)
        detector.pauseChecks = true
        detector.setFloor(record.floorDb)
        let levels = record.levels
        // The frames before the turn only move the noise floor. A follow-up turn starts with its first loud frames.
        let speechFrom = record.kind == .followUp ? max(0, record.turnStart - config.detector.startFrames + 1) : record.turnStart
        for db in levels.prefix(min(speechFrom, levels.count)) { if let db { detector.track(db: db) } }
        if record.kind == .wake {
            detector.endSilenceOverrideMs = record.dictation ? config.dictationEndSilenceMs : nil
            detector.dictationTurn = record.dictation
            detector.open(heardSpeech: record.openHeardSpeech ?? false, quietMs: record.openQuietMs ?? 0,
                          graceMs: config.graceMs)
        }
        var started = record.kind == .wake
        var index = speechFrom
        while index < levels.count {
            defer { index += 1 }
            guard let db = levels[index] else { continue }
            var event = detector.feed(db: db)
            if !started {
                if event == .start {
                    started = true
                    detector.endSilenceOverrideMs = record.dictation ? config.dictationEndSilenceMs : nil
                    detector.dictationTurn = record.dictation
                }
                continue
            }
            if event == nil, detector.takePauseCheck() {
                let answer = score(result.checks)
                result.checks += 1
                if let answer { event = WakeTrigger.answer(answer, config: config, detector: &detector).0 }
            }
            if let event {
                result.event = event
                result.end = event == .end ? detector.lastEnd : nil
                result.endFrame = index
                return result
            }
        }
        return result
    }
}
