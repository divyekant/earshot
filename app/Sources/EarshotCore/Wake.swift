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
    /// True if the voice matches the enrolled voice, or if no voice is enrolled.
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
    /// The voice score of a whole turn, for a turn in the follow-up window. Nil if no voice is enrolled.
    func voiceScore(_ samples: [Float]) -> Double?
    /// The lowest score that counts as the owner's voice.
    var voiceThreshold: Double { get }
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
    func turnScore(_ samples: [Float]) -> Double? { nil }
}

/// One check of the turn model at a pause (R-ON-1, I-2). For the log: numbers only, no audio and no text.
public struct TurnCheck: Sendable, Equatable {
    public enum Decision: String, Sendable {
        /// The model heard the end of the turn. The turn ends now.
        case end
        /// The model heard a pause inside the turn. The turn waits up to the fallback silence.
        case wait
        /// No model, or the model failed. The usual end silence counts.
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

    public init(phrase: String, embedding: [Float], keywordTokens: [[String]], samples: Int, selfScore: Double,
                createdAt: Date = Date(), templates: [WakeTemplate]? = nil) {
        self.phrase = phrase; self.embedding = embedding; self.keywordTokens = keywordTokens
        self.samples = samples; self.selfScore = selfScore; self.createdAt = createdAt; self.templates = templates
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
    /// The owner's voice profile, or nil if the owner did not teach earshot the voice.
    public var voiceProfile: VoiceProfile? { load(VoiceProfile.self, VoiceProfile.fileName) }

    /// Saves the profile. Nil deletes the file.
    public func saveVoiceProfile(_ profile: VoiceProfile?) throws {
        if let profile { try save(profile, VoiceProfile.fileName); return }
        let url = folder.appendingPathComponent(VoiceProfile.fileName)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
