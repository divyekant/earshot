import Foundation

// The wake phrase and the owner's voice for always-on mode (R-ON-1, R-ON-2, R-ON-3, D-11).
// EarshotWake listens for the phrase and checks the voice. EarshotInput uses it through `WakeListener`.

/// What the wake listener found when the phrase ended.
public struct WakeHit: Sendable, Equatable {
    /// The phrase as the owner set it, for example "hey jarvis".
    public var phrase: String
    /// The audio from the start of the phrase to now, in seconds, with a small margin.
    /// The speech engine starts this far back, so that it hears the whole phrase and every word after it.
    public var prerollSeconds: Double
    /// The time from the end of the phrase to now, in seconds. The spotter fires about 0.3 to 0.5 s after the phrase.
    /// The trigger uses it to see if the owner already said more words after the phrase.
    public var phraseEndSeconds: Double
    /// The voice score (cosine similarity to the enrolled voice, -1 to 1). Nil if no voice is enrolled.
    public var voiceScore: Double?
    /// True if the voice of the phrase reaches the gate of the voice check, or if no voice is enrolled (E6). Then the
    /// turn starts, and the voice of the whole turn decides at its end.
    public var isOwner: Bool
    /// Nil if the wake started the turn. If the owner said the phrase again in a follow-up turn, the time from the
    /// start of that turn to the wake, in seconds.
    public var inTurnAfterSeconds: Double?
    /// The score of the audio templates (0 is the same sound, 1 is unrelated), or nil if the spelled spotter woke
    /// earshot. For the log.
    public var matchScore: Double?
    /// The worst 200 ms of the template match, or nil. For the log.
    public var matchWorst: Double?

    public init(phrase: String, prerollSeconds: Double, phraseEndSeconds: Double = 0, voiceScore: Double?, isOwner: Bool,
                inTurnAfterSeconds: Double? = nil, matchScore: Double? = nil, matchWorst: Double? = nil) {
        self.phrase = phrase; self.prerollSeconds = prerollSeconds; self.phraseEndSeconds = phraseEndSeconds
        self.voiceScore = voiceScore; self.isOwner = isOwner; self.inTurnAfterSeconds = inTurnAfterSeconds
        self.matchScore = matchScore; self.matchWorst = matchWorst
    }

    /// The end of the phrase in seconds from the start of the turn: negative if the phrase ended before the turn
    /// started (the speech engine heard it in the preroll).
    public var phraseEndInTurn: Double { (inTurnAfterSeconds ?? 0) - phraseEndSeconds }
}

/// The limits of the owner voice check (R-ON-3, D-11). A longer clip gives a surer score, so the check of a whole
/// turn uses a higher limit than the check of a short clip (E6: 26 real speakers, `docs/experiments/E6-voice-check.md`).
/// - The phrase alone starts a turn if its score is `gate` or more. A lower score is another voice: nothing starts.
/// - At the end of the turn, the voice of the whole turn decides. Up to `shortSeconds` of speech, it must score
///   `short` or more. From `turnSeconds`, it must score `turn` or more. Between them, the limit goes up in a line.
///   A step at one length cut the owner's pass rate at that length (E6: 97 % to 92 % near, 58 % to 37 % far).
public struct VoiceRule: Sendable, Equatable {
    /// The lowest score of the phrase alone that starts a turn.
    public var gate: Double
    /// The limit for a clip of `shortSeconds` of speech or less.
    public var short: Double
    /// The limit for a clip of `turnSeconds` of speech or more.
    public var turn: Double
    /// The speech length, in seconds, up to which `short` applies.
    public var shortSeconds: Double
    /// The speech length, in seconds, from which `turn` applies.
    public var turnSeconds: Double
    /// A follow-up turn that misses the limit passes if its voice scores this much or more against the voice of the
    /// owner's last turn that passed (E6, section 8). The last turn has the same microphone, room and way of speech.
    /// Live test 2026-11-03: two go-on parts of the owner's dictation, right after earshot typed, scored 0.23 and
    /// 0.25 against the profile, which holds the wake phrase only.
    public var lastTurn: Double
    /// The check against the last turn needs this much speech, in seconds. A shorter clip, for example "send" alone,
    /// must pass the profile (D-12).
    public var lastTurnMinSeconds: Double
    /// A wake turn adds its voice to the profile (`VoiceProfile.learning`) only if its score is this much over its
    /// limit. A turn near the limit is not sure enough to learn from.
    public var learnMargin: Double
    /// A wake turn adds its voice to the profile only with this much speech, in seconds: the phrase and a command.
    public var learnMinSeconds: Double

    /// The gate stays at 0.35, not 0.10 (the E6 bench value): in the live run of 2026-11-03, room sounds matched the
    /// phrase templates every 4 to 6 s for 2 minutes, with voice scores of 0.17 to 0.29. A lower gate would start a
    /// turn for many of them. The owner's wakes on the same microphone scored 0.58 to 0.73.
    /// The bench for `lastTurn` (E6, section 8): at 0.45 and 1.0 s, the owner passes more often far from the
    /// microphone (66 % to 95 % at 2.8 s), and other voices pass 0.1 to 0.5 points more often.
    public init(gate: Double = 0.35, short: Double = 0.35, turn: Double = 0.42, shortSeconds: Double = 1.0,
                turnSeconds: Double = 2.0, lastTurn: Double = 0.45, lastTurnMinSeconds: Double = 1.0,
                learnMargin: Double = 0.05, learnMinSeconds: Double = 1.5) {
        self.gate = gate; self.short = short; self.turn = turn
        self.shortSeconds = shortSeconds; self.turnSeconds = max(turnSeconds, shortSeconds)
        self.lastTurn = lastTurn; self.lastTurnMinSeconds = lastTurnMinSeconds
        self.learnMargin = learnMargin; self.learnMinSeconds = learnMinSeconds
    }

    /// True if a wake turn with this score, limit and speech length is sure enough to add its voice to the profile.
    public func learns(score: Double, limit: Double, seconds: Double) -> Bool {
        score >= limit + learnMargin && seconds >= learnMinSeconds
    }

    /// The limit for a clip with this much speech, in seconds.
    public func limit(seconds: Double) -> Double {
        if seconds <= shortSeconds { return short }
        if seconds >= turnSeconds { return turn }
        return short + (turn - short) * (seconds - shortSeconds) / (turnSeconds - shortSeconds)
    }
}

/// The voice check at the end of an always-on turn (R-ON-3, D-11, D-12). It holds no audio and no text.
public struct TurnVoice: Sendable, Equatable {
    /// The turn that the check is for.
    public enum Kind: String, Sendable { case wake, followUp }
    public var kind: Kind
    /// The score that decided: the score of the turn, or of the phrase if the check of the turn did not run.
    public var score: Double
    /// The speech that the voice model scored, in seconds: the turn with its quiet parts cut. 0 if the phrase decided.
    public var seconds: Double
    /// The audio of the turn, in seconds.
    public var audioSeconds: Double
    /// The limit that the score had to reach.
    public var limit: Double
    /// True if the voice is the owner's. An always-on "send" needs it (D-12).
    public var passed: Bool
    /// True if the score of the turn decided. False if the score of the phrase decided.
    public var byTurn: Bool
    /// The time of the check, in milliseconds.
    public var ms: Double
    /// The level of the speech that the model scored, in dB of full scale. Nil if it is not known.
    public var level: Double?
    /// The score against the voice of the owner's last turn that passed (`VoiceRule.lastTurn`). Nil if there was no
    /// such turn in the follow-up window, or for a wake turn.
    public var lastTurnScore: Double?
    /// The limit for `lastTurnScore`.
    public var lastTurnLimit: Double
    /// True if the turn missed `limit` and passed by `lastTurnScore`.
    public var byLastTurn: Bool
    /// The number of learned turns in the profile after this turn, if this turn added its voice to it. Else nil.
    public var learnedTurns: Int?

    public init(kind: Kind, score: Double, seconds: Double, audioSeconds: Double, limit: Double, passed: Bool,
                byTurn: Bool = true, ms: Double = 0, level: Double? = nil, lastTurnScore: Double? = nil,
                lastTurnLimit: Double = 0, byLastTurn: Bool = false, learnedTurns: Int? = nil) {
        self.kind = kind; self.score = score; self.seconds = seconds; self.audioSeconds = audioSeconds
        self.limit = limit; self.passed = passed; self.byTurn = byTurn; self.ms = ms
        self.level = level; self.lastTurnScore = lastTurnScore; self.lastTurnLimit = lastTurnLimit
        self.byLastTurn = byLastTurn; self.learnedTurns = learnedTurns
    }

    /// One part of a log line, for example "turn voice 0.51 (speech 1.84 s, audio 2.60 s, level -31 dB, needs 0.42,
    /// 9 ms)", then ", last turn 0.68 (needs 0.45, passed)" if the check against the last turn ran.
    public var summary: String {
        guard byTurn else {
            return String(format: "phrase voice %.2f (turn not checked, audio %.2f s, needs %.2f)", score, audioSeconds, limit)
        }
        let levelText = level.map { String(format: ", level %.0f dB", $0) } ?? ""
        var text = String(format: "turn voice %.2f (speech %.2f s, audio %.2f s", score, seconds, audioSeconds)
            + levelText + String(format: ", needs %.2f, %.0f ms)", limit, ms)
        if let last = lastTurnScore {
            text += String(format: ", last turn %.2f (needs %.2f", last, lastTurnLimit) + (byLastTurn ? ", passed)" : ")")
        }
        if let learned = learnedTurns { text += ", learned (\(learned) turn\(learned == 1 ? "" : "s"))" }
        return text
    }
}

/// The result of one voice check of a turn (E6). It holds no audio.
public struct VoiceCheck: Sendable, Equatable {
    /// The cosine similarity to the profile, -1 to 1.
    public var score: Double
    /// The speech that the model scored, in seconds, after the quiet parts are cut.
    public var seconds: Double
    /// The voice embedding of the turn, to compare the next follow-up turn with it. Empty if it is not known.
    public var embedding: [Float]
    /// The level of the scored speech, in dB of full scale. Nil if it is not known.
    public var level: Double?

    public init(score: Double, seconds: Double, embedding: [Float] = [], level: Double? = nil) {
        self.score = score; self.seconds = seconds; self.embedding = embedding; self.level = level
    }

    /// The cosine similarity, -1 to 1, of this voice and another embedding. Nil if one of them is empty, or if
    /// the lengths are not the same.
    public func similarity(to other: [Float]) -> Double? {
        guard !embedding.isEmpty, embedding.count == other.count else { return nil }
        var dot = 0.0, a = 0.0, b = 0.0
        for i in embedding.indices {
            let x = Double(embedding[i]), y = Double(other[i])
            dot += x * y; a += x * x; b += y * y
        }
        guard a > 0, b > 0 else { return nil }
        return dot / (a.squareRoot() * b.squareRoot())
    }
}

/// Partial matches of the wake phrase that did not fire (D-11). Only a count and the best part of the phrase, or the
/// lowest template score: no audio and no text.
public struct NearMisses: Sendable, Equatable {
    /// The number of near misses.
    public var count: Int
    /// The spelled spotter: the largest part of the phrase pieces that matched, 0 to 1. 1 means all pieces matched,
    /// but the acoustic score was below the threshold. 0 for the audio templates.
    public var best: Double
    /// The audio templates: the lowest score of the near misses (the wake limit is lower). Nil for the spotter.
    public var bestScore: Double?

    public init(count: Int, best: Double, bestScore: Double? = nil) {
        self.count = count; self.best = best; self.bestScore = bestScore
    }

    /// Adds other near misses to these.
    public mutating func add(_ other: NearMisses) {
        count += other.count
        best = max(best, other.best)
        if let score = other.bestScore { bestScore = min(bestScore ?? score, score) }
    }
}

/// A speech engine that can take words to expect, such as the wake phrase (D-11). Apple speech then spells them
/// right more often. An engine that cannot use them ignores them.
public protocol PhraseHintControl: AnyObject {
    func setPhraseHints(_ phrases: [String])
}

/// Listens for the wake phrase in 16 kHz mono audio, and checks the voice.
/// One queue calls it. It is not thread-safe.
public protocol WakeListener: AnyObject {
    /// Feeds 16 kHz mono samples, in order. Returns a hit when the phrase ends.
    func feed(_ samples: [Float]) -> WakeHit?
    /// The voice score of a clip. Nil if no voice is enrolled.
    func voiceScore(_ samples: [Float]) -> Double?
    /// The voice check of a whole turn: the score, the speech length after the quiet parts are cut, and the voice
    /// embedding of the turn. Nil if no voice is enrolled.
    func voiceCheck(_ samples: [Float]) -> VoiceCheck?
    /// The lowest score of the phrase that starts a turn (the gate of `VoiceRule`). `WakeHit.isOwner` uses it.
    var voiceThreshold: Double { get }
    /// Adds the voice of a wake turn that passed well to the profile in use (`VoiceProfile.learning`). Returns the
    /// new profile, to save it. Nil if the listener does not learn: no profile, or a profile of another microphone.
    func learn(_ turn: [Float]) -> VoiceProfile?
    /// Starts again with no audio, for example after a turn.
    func reset()
    /// The near misses since the last call, or nil if there were none. Then it starts to count again.
    func takeNearMisses() -> NearMisses?
    /// The probability (0 to 1) that the speaker finished the turn, from the sound of the last 8 s of the turn
    /// (Smart Turn v3.2). Nil if the turn model is not loaded or failed: then the end silence alone ends the turn.
    func turnScore(_ samples: [Float]) -> Double?
}

public extension WakeListener {
    func takeNearMisses() -> NearMisses? { nil }
    func learn(_ turn: [Float]) -> VoiceProfile? { nil }
    func turnScore(_ samples: [Float]) -> Double? { nil }
    /// The score of `voiceScore`, with the length of all the samples and no embedding.
    func voiceCheck(_ samples: [Float]) -> VoiceCheck? {
        voiceScore(samples).map { VoiceCheck(score: $0, seconds: Double(samples.count) / 16000) }
    }
}

/// How an always-on turn ended (R-ON-1, I-2). For the log: numbers only, no audio and no text.
public struct TurnEnd: Sendable, Equatable {
    public enum Rule: String, Sendable {
        /// Quiet frames at the room level for the end silence.
        case quiet
        /// No speech frame for the end silence plus `softEndExtraMs` (noise that changes, or a soft voice).
        case soft
        /// The turn model heard the end of the turn at a pause.
        case model
        /// The wake phrase with no command after it, for the grace time.
        case grace
        /// The longest turn (15 s for a command turn, 60 s for dictation).
        case limit
    }
    public var rule: Rule
    /// The end silence that applied to this turn, in ms (550, 1200 for dictation, or the wait after the model).
    public var endSilenceMs: Double
    /// The quiet time at the end (frames with no speech), in ms.
    public var silenceMs: Double
    /// The length of the turn, in ms.
    public var turnMs: Double

    public init(rule: Rule, endSilenceMs: Double, silenceMs: Double, turnMs: Double) {
        self.rule = rule; self.endSilenceMs = endSilenceMs; self.silenceMs = silenceMs; self.turnMs = turnMs
    }
}

/// One check of the turn model at a pause (R-ON-1, I-2). For the log: numbers only, no audio and no text.
public struct TurnCheck: Sendable, Equatable {
    public enum Decision: String, Sendable {
        /// The model heard the end of the turn. The turn ends now.
        case end
        /// The model heard a pause inside the turn. The turn waits up to the fallback silence.
        case wait
        /// No model, the model failed, or a sure end in a dictation turn. The usual end silence counts.
        case none
    }
    /// The probability that the turn is done, or nil if no model ran.
    public var probability: Double?
    /// The quiet time at the check, in ms.
    public var silenceMs: Double
    public var decision: Decision
    /// The time of the model run, in ms.
    public var runMs: Double
    /// True if the turn holds dictated text.
    public var dictation: Bool

    public init(probability: Double?, silenceMs: Double, decision: Decision, runMs: Double, dictation: Bool) {
        self.probability = probability; self.silenceMs = silenceMs; self.decision = decision
        self.runMs = runMs; self.dictation = dictation
    }
}

/// A speech engine that can start the next turn further back than its usual 450 ms preroll (D-11).
/// The wake phrase fires about 0.3 to 0.5 s after the phrase ends, so the engine must reach back to the start of
/// the phrase. Else it loses the first words of the command.
public protocol PrerollControl: AnyObject {
    /// The next `begin` gives the engine this much audio from before it, up to the audio that the engine keeps
    /// (3 s). Later turns use the usual preroll again.
    func setNextPreroll(seconds: Double)
}

/// A speech engine that can change the real audio it still records after the end of the next turn
/// (`TailPad.captureSeconds`, 200 ms for the hold key). An always-on turn ends after a pause that the detector
/// already heard, so it needs no more audio: the pipeline sets 0 and saves the wait (R-ON-1, R-SP-1).
public protocol CaptureControl: AnyObject {
    /// The next `end` waits this long for audio, then adds the tail silence. Later turns use the usual value again.
    func setNextCapture(seconds: Double)
}

/// The sound pattern of one teach take: the encoder frames of the spotter model for the spoken part of the phrase
/// (D-11, E5). It is not audio: earshot cannot play it back. It stays on the Mac in `voice.json` (R-MD-1).
public struct WakeTemplate: Codable, Equatable, Sendable {
    /// The number of frames (40 ms each).
    public var frames: Int
    /// The values in each frame (320 for the spotter model).
    public var width: Int
    /// The values as 16-bit floats (IEEE 754 half precision, little endian), frame after frame.
    public var half: Data

    public init(frames: Int, width: Int, half: Data) {
        self.frames = frames; self.width = width; self.half = half
    }

    /// True if the data has the size of the frames.
    public var isValid: Bool { frames > 0 && width > 0 && half.count == frames * width * 2 }
}

/// The owner's voice and the tokens of the wake phrase, from the enrolment in the management window.
/// It holds no audio. It stays on the Mac in `voice.json` in the store folder (R-MD-1).
/// The voice counts for any phrase. The learned tokens and the templates count only for the phrase of the enrolment.
public struct VoiceProfile: Codable, Equatable, Sendable {
    /// The wake phrase that the owner said in the enrolment.
    public var phrase: String
    /// The speaker embedding: the normalized mean of the enrolment embeddings.
    public var embedding: [Float]
    /// The word pieces that the spotter heard for each enrolment phrase, from a profile before the templates (E5).
    /// The spelled spotter listens for each of them. The model hears a made-up name such as "earshot" as other words
    /// ("your shot"), so the spelled pieces alone almost never fire. Empty in a profile with templates.
    public var keywordTokens: [[String]]
    /// The number of enrolment phrases.
    public var samples: Int
    /// The lowest score of one enrolment phrase against the mean. A low value means a noisy enrolment.
    public var selfScore: Double
    public var createdAt: Date
    /// The audio templates of the phrase (D-11, E5). With them, earshot finds the phrase by its sound, not by its
    /// spelling. Nil in a profile from before the templates: then the spelled spotter listens until the owner teaches
    /// earshot again.
    public var templates: [WakeTemplate]?
    /// The ID of the microphone of the enrolment (the Core Audio device UID), or nil in an older profile.
    /// The voice and the templates match best on the same microphone (E6, live run 2026-11-03).
    public var micID: String?
    /// The name of that microphone, for the management window.
    public var micName: String?
    /// The voice embeddings of the owner's last wake turns that passed the check well, oldest first, at most
    /// `maxLearnedTurns` (E6, section 8.2). The enrolment holds the wake phrase only, so it matches the owner's free
    /// speech less well. These turns add free speech to the check of a whole turn. Nil in an older profile.
    public var learnedTurns: [[Float]]?

    /// The most wake turns that a profile learns. The oldest goes first.
    public static let maxLearnedTurns = 10

    public init(phrase: String, embedding: [Float], keywordTokens: [[String]], samples: Int, selfScore: Double,
                createdAt: Date = Date(), templates: [WakeTemplate]? = nil, micID: String? = nil, micName: String? = nil,
                learnedTurns: [[Float]]? = nil) {
        self.phrase = phrase; self.embedding = embedding; self.keywordTokens = keywordTokens
        self.samples = samples; self.selfScore = selfScore; self.createdAt = createdAt; self.templates = templates
        self.micID = micID; self.micName = micName; self.learnedTurns = learnedTurns
    }

    /// The embedding for the check of a whole turn: the mean of the enrolment phrases and the learned turns, each
    /// with the same weight. With no learned turns, it is `embedding`. The phrase alone (the gate) uses `embedding`.
    public var turnEmbedding: [Float] {
        let turns = (learnedTurns ?? []).filter { $0.count == embedding.count }
        guard !turns.isEmpty else { return embedding }
        var sum = embedding.map { $0 * Float(max(1, samples)) }
        for turn in turns { for i in sum.indices { sum[i] += turn[i] } }
        return sum
    }

    /// The profile with one more learned turn. The oldest goes after `maxLearnedTurns`.
    public func learning(_ turn: [Float]) -> VoiceProfile {
        guard turn.count == embedding.count else { return self }
        var copy = self
        copy.learnedTurns = Array(((learnedTurns ?? []) + [turn]).suffix(Self.maxLearnedTurns))
        return copy
    }

    /// The templates for this phrase, or an empty list if the profile has none or belongs to another phrase.
    public func templates(for other: String) -> [WakeTemplate] {
        guard matches(phrase: other) else { return [] }
        return (templates ?? []).filter(\.isValid)
    }

    /// The file name in the store folder.
    public static let fileName = "voice.json"

    /// True if the profile belongs to this phrase. A new phrase keeps the voice, but loses the learned tokens.
    public func matches(phrase other: String) -> Bool { WakePhrase.words(phrase) == WakePhrase.words(other) }
}

/// The owner's voice profiles: one for each microphone (E6). The owner teaches earshot one time on each microphone.
/// It holds no audio. It stays on the Mac in `voice.json` (R-MD-1).
public struct VoiceBook: Codable, Equatable, Sendable {
    /// The profiles, oldest first. At most `maxProfiles`.
    public var profiles: [VoiceProfile]
    /// The most profiles that the book keeps. A new microphone after that replaces the oldest profile.
    public static let maxProfiles = 4

    public init(profiles: [VoiceProfile] = []) { self.profiles = profiles }

    /// The newest profile, or nil.
    public var newest: VoiceProfile? { profiles.max { $0.createdAt < $1.createdAt } }

    /// The profile for the microphone: the profile taught on it, else the newest profile. Nil if the book is empty.
    public func profile(forMic id: String?) -> VoiceProfile? {
        if let id, let same = profiles.filter({ $0.micID == id }).max(by: { $0.createdAt < $1.createdAt }) { return same }
        return newest
    }

    /// True if a profile was taught on this microphone.
    public func hasProfile(forMic id: String?) -> Bool {
        guard let id else { return false }
        return profiles.contains { $0.micID == id }
    }

    /// The book with the new profile. It replaces the profile of the same microphone, and the oldest profiles
    /// after `maxProfiles`.
    public func adding(_ profile: VoiceProfile) -> VoiceBook {
        var kept = profiles.filter { $0.micID != profile.micID }
        kept.append(profile)
        kept.sort { $0.createdAt < $1.createdAt }
        return VoiceBook(profiles: Array(kept.suffix(Self.maxProfiles)))
    }
}

/// The wake phrase text rules.
public enum WakePhrase {
    /// The default phrase. Two words fire less often by mistake than one word. Known words work best: the spotter
    /// hears the made-up name "earshot" as "your shot" (Test 3, 2026-11-02: "hey jarvis" woke on 86 % of the owner
    /// phrases and on none of 800 other phrases).
    public static let defaultPhrase = "hey jarvis"
    /// The number of enrolment phrases.
    public static let enrolmentSamples = 5

    /// The words of a phrase: lower case, letters and digits only.
    public static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map { $0.replacingOccurrences(of: "'", with: "") }
            .filter { !$0.isEmpty }
    }

    /// Removes the wake phrase, and any words before it, from the start of a transcript.
    /// The speech engine starts before the phrase, so the text can begin with the phrase, a part of the word
    /// before it, or a misheard form ("Hey, ear shot.", "hey Ershot", "Here, at least" for "hey atlas").
    /// If no form of the phrase is in the first words, the text stays as it is.
    /// - Parameter afterWake: true if the spotter heard the phrase at the start of this turn. Then the last word
    ///   of the phrase alone may also be a loose match. In a follow-up turn the phrase is often not there, so only
    ///   the full phrase may be a loose match there.
    public static func strip(_ text: String, phrase: String, afterWake: Bool = false) -> String {
        let target = words(phrase).joined()
        guard !target.isEmpty else { return text }
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let normal = tokens.map { words($0).joined() }
        // The last word of the phrase alone, for a transcript that lost the first word ("earshot, open Slack").
        let lastWord = words(phrase).last ?? target
        var best: (end: Int, cost: Double)?
        for start in 0..<min(3, normal.count) {
            // The phrase is the first words, or follows one short word ("So", "Yeah"). Apple speech can write a
            // known phrase as other words there: in the live trial of 2026-11-02, 7 of 15 commands began with
            // "Here, at least" or "He at least" for "hey atlas". So allow a loose match at the start only.
            let early = start == 0 || (start == 1 && normal[0].count <= 4)
            for end in start..<min(start + 4, normal.count) {
                let joined = normal[start...end].joined()
                guard !joined.isEmpty else { continue }
                for candidate in Set([target, lastWord]) where candidate.count >= 4 || candidate == target {
                    let full = candidate == target
                    // The last word alone: only at the start, so "search for atlas" keeps its last word.
                    if !full && start > 1 { continue }
                    let loose = early && (full || afterWake)
                    let distance = editDistance(joined, candidate)
                    let allowed = loose ? max(1, candidate.count / 2) : max(1, candidate.count / 4)
                    guard distance <= allowed else { continue }
                    // Prefer the full phrase, then fewer skipped words, then a closer match.
                    let cost = Double(distance) / Double(candidate.count) + Double(start) * 0.2
                        + (candidate == target ? 0 : 0.3)
                    if best == nil || cost < best!.cost { best = (end, cost) }
                }
            }
        }
        guard let best else { return text }
        let rest = tokens.dropFirst(best.end + 1).joined(separator: " ")
        return rest.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
            .isEmpty ? "" : String(rest.drop(while: { $0.isPunctuation || $0.isWhitespace }))
    }

    /// A piece that starts less than this before the phrase end from the spotter stays as a command word.
    /// The phrase end from the spotter tends to be late: the spotter marks a piece when it decides, and the speech
    /// engine starts a little after the wake. So a word said right after the phrase can start before the estimate.
    public static let cutMarginSeconds = 0.15

    /// Removes the wake phrase by time (D-11): the first pieces that start before the end of the phrase, less a margin.
    /// The start of a piece is its sure edge. An engine can let the end of a word run until the next word starts.
    /// - Parameters:
    ///   - words: the pieces of the transcript with their times, from the start of the turn.
    ///   - phraseEnd: the end of the phrase, in seconds from the start of the turn (`WakeHit.phraseEndInTurn`).
    /// - Returns: the text after the phrase. Nil if there are no times, or if no piece is before the phrase end.
    ///   Then use `strip`, which matches the text.
    public static func cut(_ words: [TimedWord], phraseEnd: Double, margin: Double = cutMarginSeconds) -> String? {
        guard !words.isEmpty else { return nil }
        let rest = words.drop(while: { $0.start < phraseEnd - margin })
        guard rest.count < words.count else { return nil }
        let text = rest.map(\.text).joined()
        let clean = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(clean.drop(while: { $0.isPunctuation || $0.isWhitespace }))
    }

    /// The Levenshtein distance of two short strings.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

extension Store {
    /// The owner's voice profiles. Empty if the owner did not teach earshot the voice.
    /// A `voice.json` from before the book holds one profile: the book then has that profile.
    public var voiceBook: VoiceBook {
        if let book = load(VoiceBook.self, VoiceProfile.fileName) { return book }
        if let one = load(VoiceProfile.self, VoiceProfile.fileName) { return VoiceBook(profiles: [one]) }
        return VoiceBook()
    }

    /// The newest voice profile, or nil if the owner did not teach earshot the voice.
    public var voiceProfile: VoiceProfile? { voiceBook.newest }

    /// Adds the profile to the book: it replaces the profile of the same microphone. Nil deletes all profiles.
    public func saveVoiceProfile(_ profile: VoiceProfile?) throws {
        if let profile { try save(voiceBook.adding(profile), VoiceProfile.fileName); return }
        let url = folder.appendingPathComponent(VoiceProfile.fileName)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
