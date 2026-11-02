import Foundation

/// What the speech detector reports.
public enum SpeechEvent: Sendable, Equatable {
    /// Speech started. Start to listen. The speech engine keeps 250 ms of audio before `begin`, so the first word is kept.
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
    /// Frames above the threshold in a row before `start`. 3 frames of 20 ms is 60 ms.
    public var startFrames: Int = 3
    /// Quiet after speech that ends the turn. Commands have short pauses, for example after "Slack Ravi,".
    public var endSilenceMs: Double = 550
    /// A turn with less speech than this is dropped.
    public var minimumSpeechMs: Double = 250
    /// A turn stops at this length, for example when a TV plays.
    public var maximumTurnMs: Double = 15000
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
    private var speechMs: Double = 0
    private var turnMs: Double = 0
    /// After a forced stop, wait for quiet before the next turn. So a TV does not make turn after turn.
    private var waitForQuiet = false

    public init(config: DetectorConfig = DetectorConfig()) { self.config = config }

    /// The level that counts as speech now.
    public var thresholdDb: Double { max(floorDb + config.marginDb, config.minimumSpeechDb) }

    /// Feeds the level of one frame, in dB full scale. Returns an event, or nil.
    public mutating func feed(db: Double) -> SpeechEvent? {
        let level = db.isFinite ? max(db, -120) : -120
        let loud = level >= thresholdDb
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
            turnMs = speechMs
            quietMs = 0
            loudRun = 0
            return .start
        }

        turnMs += config.frameMs
        if loud { speechMs += config.frameMs; quietMs = 0 } else { quietMs += config.frameMs }

        if turnMs >= config.maximumTurnMs {
            inTurn = false
            waitForQuiet = true
            quietMs = 0
            return .drop("longer than \(Int(config.maximumTurnMs / 1000)) s")
        }
        if quietMs >= config.endSilenceMs {
            inTurn = false
            quietMs = 0
            if speechMs < config.minimumSpeechMs { return .drop("speech shorter than \(Int(config.minimumSpeechMs)) ms") }
            return .end
        }
        return nil
    }

    /// Ends a turn from the outside. Returns `.drop` if a turn was open.
    public mutating func reset() -> SpeechEvent? {
        defer { inTurn = false; loudRun = 0; quietMs = 0; waitForQuiet = false }
        return inTurn ? .drop("input stopped") : nil
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
    public static func db<C: Collection>(_ samples: C) -> Double where C.Element == Float {
        guard !samples.isEmpty else { return -120 }
        var sum: Double = 0
        for s in samples { sum += Double(s) * Double(s) }
        let rms = (sum / Double(samples.count)).squareRoot()
        return rms > 0 ? max(20 * log10(rms), -120) : -120
    }
}
