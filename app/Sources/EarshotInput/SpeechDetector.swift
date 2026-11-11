import EarshotCore
import Foundation

/// What the speech detector reports.
public enum SpeechEvent: Sendable, Equatable {
    /// Speech started. Start to listen. The speech engine keeps 450 ms of audio before `begin`, so the first word is kept.
    case start
    /// The turn ended: speech, then `endSilence` of quiet. Stop, and use the text.
    case end
    /// The sound was too short to be a command, for example a cough or a door. Stop, and drop the text.
    case drop(String)
}

/// The tuning of the always-on audio gate. The defaults come from tests with `say` voices and room noise.
public struct DetectorConfig: Sendable, Equatable {
    /// The length of one audio frame.
    public var frameMs: Double = 20
    /// Speech must be this many dB above the noise floor.
    public var marginDb: Double = 12
    /// Speech must be louder than this, in dB full scale. Quiet rooms have a floor near -70 dB.
    public var minimumSpeechDb: Double = -50
    /// In a turn, a frame counts as quiet only if it is at most this many dB above the noise floor. A frame between
    /// the quiet level and the speech level (a soft word end, a quieter microphone) does not count toward the end
    /// silence. The two levels come from Hex (anomalyco/hex, `SpeechFrames::is_quiet`, MIT): with one level, Hex
    /// cut dictations when speech was only 8 dB above room noise (Hex issue 458).
    public var quietMarginDb: Double = 4
    /// In a turn, a frame below this level in dB full scale is always quiet. It is lower than `minimumSpeechDb`, so
    /// speech from a quiet microphone keeps the turn open (Hex issue 841).
    public var quietMinimumDb: Double = -70
    /// A frame between the two levels can also be noise that changes (keys, a TV), not speech. So frames that are not
    /// speech also end the turn after the end silence plus this time, as a fallback.
    public var softEndExtraMs: Double = 1000
    /// With a turn model (`pauseChecks`): after this much time with no speech frame, the trigger asks the model if
    /// the turn is done. The 300 ms comes from Hex's Smart Turn experiment (anomalyco/hex f748282, MIT).
    public var pauseCheckMs: Double = 300
    /// No check before this much speech in the turn (Hex: 200 ms). After the wake phrase, only the speech after
    /// the phrase counts: the model hears "hey atlas" alone as a finished turn (live test 2026-11-03, P 0.96-0.99).
    public var pauseCheckMinimumSpeechMs: Double = 200
    /// After the wake phrase, the command starts only after this much speech (in total, not in a row). Less
    /// speech is a sound, a breath or the end of the phrase: the turn keeps the grace time for the command.
    public var commandStartMs: Double = 200
    /// Frames above the threshold in a row before `start`. 3 frames of 20 ms is 60 ms.
    public var startFrames: Int = 3
    /// Quiet after speech that ends the turn. Commands have short pauses, for example after "Slack Ravi,".
    public var endSilenceMs: Double = 550
    /// A turn with less speech than this is dropped.
    public var minimumSpeechMs: Double = 250
    /// A turn stops at this length, for example when a TV plays. The turn is dropped.
    public var maximumTurnMs: Double = 15000
    /// The length limit of a dictation turn. At this limit the turn ends with its text: it is not dropped.
    public var dictationMaximumTurnMs: Double = 60000
    /// How fast the noise floor follows a quieter level (0...1 for each frame). It follows a louder level 20 times slower.
    public var floorFallRate: Double = 0.2

    public init() {}
}

/// Detects speech from the level of each audio frame (R-ON-1).
///
/// It is an energy detector with a noise floor that adapts. It needs no model file, so there is no setup.
/// DESIGN.md 3.1 proposes Silero VAD and Smart Turn. They can replace this type later behind the same events.
/// It has no AppKit or audio code, so that the tests can run it.
public struct SpeechDetector: Sendable {
    public let config: DetectorConfig
    /// The noise floor in dB full scale.
    public private(set) var floorDb: Double = -60
    public private(set) var inTurn = false

    private var loudRun = 0
    private var quietMs: Double = 0
    /// The time since the last speech frame, quiet or not (for `DetectorConfig.softEndExtraMs`).
    private var softMs: Double = 0
    private var speechMs: Double = 0
    private var turnMs: Double = 0
    /// After a forced stop, wait for quiet before the next turn. So a TV does not make turn after turn.
    private var waitForQuiet = false
    /// A turn that the wake phrase opened, with no speech after the phrase yet. It waits `graceMs` for the command.
    public private(set) var awaitingCommand = false
    private var graceMs: Double = 0
    /// The end silence of the open turn, if not `config.endSilenceMs`. Dictation turns use a longer pause, so a
    /// natural pause does not cut a sentence in two. The wake trigger sets it at the start of a turn.
    public var endSilenceOverrideMs: Double?
    /// True if the open turn holds dictated text. It uses `config.dictationMaximumTurnMs`, and the limit ends the turn
    /// with its text. The wake trigger sets it at the start of a turn, with `endSilenceOverrideMs`.
    public var dictationTurn = false
    /// How the last turn ended, for the log. Nil before the first end, and after a drop.
    public private(set) var lastEnd: TurnEnd?
    /// Speech since the command started, for the pause check. The wake phrase does not count.
    private var checkSpeechMs: Double = 0
    /// Speech after the wake phrase while the turn waits for the command.
    private var commandLoudMs: Double = 0
    /// True if the trigger has a turn model. Then each pause gives one check (`takePauseCheck`).
    public var pauseChecks = false
    /// The end silence of this pause, after the turn model heard a pause inside the turn. Nil: the usual end silence.
    private var pauseWaitMs: Double?
    /// True if this pause had its check.
    private var pauseChecked = false
    /// True if a pause check is due and the trigger did not take it yet.
    private var pauseCheckDue = false

    public init(config: DetectorConfig = DetectorConfig()) { self.config = config }

    /// The level that counts as speech now.
    public var thresholdDb: Double { max(floorDb + config.marginDb, config.minimumSpeechDb) }
    /// In a turn, a frame at or below this level is quiet. Between this level and `thresholdDb`, a frame keeps the turn
    /// open but does not count as speech.
    public var quietDb: Double { max(floorDb + config.quietMarginDb, config.quietMinimumDb) }

    /// Feeds the level of one frame, in dB full scale. Returns an event, or nil.
    public mutating func feed(db: Double) -> SpeechEvent? {
        let level = db.isFinite ? max(db, -120) : -120
        let loud = level >= thresholdDb
        let quietDbBefore = quietDb
        adaptFloor(level, loud: loud)

        if !inTurn {
            if waitForQuiet {
                if !loud { quietMs += config.frameMs }
                else { quietMs = 0 }
                if quietMs >= config.endSilenceMs { waitForQuiet = false; quietMs = 0 }
                return nil
            }
            loudRun = loud ? loudRun + 1 : 0
            guard loudRun >= config.startFrames else { return nil }
            inTurn = true
            speechMs = Double(loudRun) * config.frameMs
            checkSpeechMs = speechMs
            turnMs = speechMs
            quietMs = 0
            softMs = 0
            pauseChecked = false; pauseCheckDue = false; pauseWaitMs = nil
            loudRun = 0
            return .start
        }

        turnMs += config.frameMs
        if awaitingCommand {
            // After the wake phrase: wait for the command. A short pause after the phrase is normal. A short sound
            // (the start sound's echo, a breath) does not start the command: the speech in total must reach
            // `commandStartMs`. Live test 2026-11-03: a pause after the phrase lost the command 7 times.
            if loud { commandLoudMs += config.frameMs }
            if commandLoudMs >= config.commandStartMs {
                awaitingCommand = false
                checkSpeechMs = commandLoudMs
                quietMs = 0
                softMs = 0
                loudRun = 0
            } else {
                quietMs = loud ? 0 : quietMs + config.frameMs
                if quietMs >= graceMs {
                    // No command after the phrase. End, not drop: the command can be in the audio before the
                    // wake ("hey jarvis, stop" said fast). The speech engine has it, and an empty text does nothing.
                    lastEnd = TurnEnd(rule: .grace, endSilenceMs: graceMs, silenceMs: quietMs, turnMs: turnMs)
                    inTurn = false
                    awaitingCommand = false
                    quietMs = 0
                    return .end
                }
            }
            if turnMs >= config.maximumTurnMs { return forcedStop() }
            return nil
        }
        // Measure against the floor before this frame moved it. The floor moves little in one frame.
        let quiet = level <= quietDbBefore
        if loud {
            speechMs += config.frameMs; checkSpeechMs += config.frameMs; quietMs = 0; softMs = 0
            pauseChecked = false; pauseCheckDue = false; pauseWaitMs = nil
        } else {
            softMs += config.frameMs
            quietMs = quiet ? quietMs + config.frameMs : 0
            if pauseChecks, !pauseChecked, softMs >= config.pauseCheckMs,
               checkSpeechMs >= config.pauseCheckMinimumSpeechMs {
                pauseChecked = true
                pauseCheckDue = true
            }
        }

        if dictationTurn {
            if turnMs >= config.dictationMaximumTurnMs {
                lastEnd = TurnEnd(rule: .limit, endSilenceMs: endSilenceOverrideMs ?? config.endSilenceMs,
                                  silenceMs: softMs, turnMs: turnMs)
                inTurn = false
                quietMs = 0
                softMs = 0
                return .end
            }
        } else if turnMs >= config.maximumTurnMs { return forcedStop() }
        let endSilence = pauseWaitMs ?? endSilenceOverrideMs ?? config.endSilenceMs
        if quietMs >= endSilence || softMs >= endSilence + config.softEndExtraMs {
            lastEnd = TurnEnd(rule: quietMs >= endSilence ? .quiet : .soft, endSilenceMs: endSilence,
                              silenceMs: softMs, turnMs: turnMs)
            inTurn = false
            quietMs = 0
            softMs = 0
            if speechMs < config.minimumSpeechMs { lastEnd = nil; return .drop("speech shorter than \(Int(config.minimumSpeechMs)) ms") }
            return .end
        }
        return nil
    }

    /// The quiet time of the open turn (frames with no speech), in ms.
    public var pauseMs: Double { softMs }

    /// True once for each pause that needs a check of the turn model. The trigger then calls `answerPauseCheck` or
    /// `endTurnNow`.
    public mutating func takePauseCheck() -> Bool {
        defer { pauseCheckDue = false }
        return pauseCheckDue && inTurn
    }

    /// The turn model heard a pause inside the turn: this pause ends the turn only after `waitMs` of quiet.
    public mutating func answerPauseCheck(waitMs: Double) {
        guard inTurn else { return }
        pauseWaitMs = max(waitMs, endSilenceOverrideMs ?? config.endSilenceMs)
    }

    /// The turn model heard the end of the turn: ends the open turn now. Returns nil if no turn is open.
    public mutating func endTurnNow() -> SpeechEvent? {
        guard inTurn, !awaitingCommand else { return nil }
        lastEnd = TurnEnd(rule: .model, endSilenceMs: pauseWaitMs ?? endSilenceOverrideMs ?? config.endSilenceMs,
                          silenceMs: softMs, turnMs: turnMs)
        inTurn = false
        quietMs = 0
        softMs = 0
        pauseWaitMs = nil
        pauseCheckDue = false
        if speechMs < config.minimumSpeechMs { return .drop("speech shorter than \(Int(config.minimumSpeechMs)) ms") }
        return .end
    }

    private mutating func forcedStop() -> SpeechEvent {
        inTurn = false
        awaitingCommand = false
        waitForQuiet = true
        quietMs = 0
        return .drop("longer than \(Int(config.maximumTurnMs / 1000)) s")
    }

    /// Ends a turn from the outside. Returns `.drop` if a turn was open.
    public mutating func reset() -> SpeechEvent? {
        defer { inTurn = false; awaitingCommand = false; loudRun = 0; quietMs = 0; softMs = 0; waitForQuiet = false; dictationTurn = false
            pauseChecked = false; pauseCheckDue = false; pauseWaitMs = nil }
        return inTurn ? .drop("input stopped") : nil
    }

    /// Feeds the level of one frame, but only to follow the noise floor. It opens no turn.
    /// The wake trigger uses it while it waits for the wake phrase.
    /// - Returns: true if the frame counts as speech.
    @discardableResult
    public mutating func track(db: Double) -> Bool {
        let level = db.isFinite ? max(db, -120) : -120
        let loud = level >= thresholdDb
        adaptFloor(level, loud: loud)
        return loud
    }

    /// Sets the noise floor, for a replay of a kept turn (E7). The live detector never calls it.
    public mutating func setFloor(_ db: Double) { floorDb = db }

    /// Opens a turn from the outside, after the wake phrase (D-11). The phrase counts as speech, so a short
    /// command after it is not dropped.
    /// - Parameters:
    ///   - heardSpeech: true if the owner already spoke after the phrase. Then the normal end silence ends the turn.
    ///   - quietMs: the quiet time since the last speech.
    ///   - graceMs: if the owner did not speak after the phrase, the turn waits this long for the command.
    public mutating func open(heardSpeech: Bool, quietMs: Double, graceMs: Double) {
        inTurn = true
        waitForQuiet = false
        awaitingCommand = !heardSpeech
        self.graceMs = graceMs
        commandLoudMs = 0
        checkSpeechMs = 0
        self.quietMs = max(0, quietMs)
        softMs = self.quietMs
        pauseChecked = false; pauseCheckDue = false; pauseWaitMs = nil
        speechMs = config.minimumSpeechMs
        turnMs = 0
        loudRun = 0
    }

    private mutating func adaptFloor(_ level: Double, loud: Bool) {
        if level < floorDb {
            floorDb += (level - floorDb) * config.floorFallRate
        } else if !inTurn || !loud {
            // Rise slowly, and not with speech. So steady noise (a fan) lifts the floor, but a voice does not.
            floorDb += (level - floorDb) * config.floorFallRate / 20
        }
    }

    /// The level in dB full scale of float samples (RMS).
    /// The mean of the frame (its DC offset) is removed first. Some microphones have a DC offset that is louder than
    /// the speech, and then every frame has the same level (Hex issue 841).
    public static func db<C: Collection>(_ samples: C) -> Double where C.Element == Float {
        guard !samples.isEmpty else { return -120 }
        let count = Double(samples.count)
        var total: Double = 0
        for s in samples { total += Double(s) }
        let mean = total / count
        var sum: Double = 0
        for s in samples { let v = Double(s) - mean; sum += v * v }
        let rms = (sum / count).squareRoot()
        return rms > 0 && rms.isFinite ? max(20 * log10(rms), -120) : -120
    }
}
