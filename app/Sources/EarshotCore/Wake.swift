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

    public init(phrase: String, prerollSeconds: Double, phraseEndSeconds: Double = 0, voiceScore: Double?, isOwner: Bool,
                inTurnAfterSeconds: Double? = nil) {
        self.phrase = phrase; self.prerollSeconds = prerollSeconds; self.phraseEndSeconds = phraseEndSeconds
        self.voiceScore = voiceScore; self.isOwner = isOwner; self.inTurnAfterSeconds = inTurnAfterSeconds
    }

    /// The end of the phrase in seconds from the start of the turn: negative if the phrase ended before the turn
    /// started (the speech engine heard it in the preroll).
    public var phraseEndInTurn: Double { (inTurnAfterSeconds ?? 0) - phraseEndSeconds }
}

/// Partial matches of the wake phrase that did not fire (D-11). Only a count and the best part of the phrase:
/// no audio and no text.
public struct NearMisses: Sendable, Equatable {
    /// The number of near misses.
    public var count: Int
    /// The largest part of the phrase pieces that matched, 0 to 1. 1 means all pieces matched, but the acoustic
    /// score was below the threshold.
    public var best: Double

    public init(count: Int, best: Double) { self.count = count; self.best = best }

    /// Adds other near misses to these.
    public mutating func add(_ other: NearMisses) { count += other.count; best = max(best, other.best) }
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
}

public extension WakeListener {
    func takeNearMisses() -> NearMisses? { nil }
}

/// A speech engine that can start the next turn further back than its usual 250 ms preroll (D-11).
/// The wake phrase fires about 0.3 to 0.5 s after the phrase ends, so the engine must reach back to the start of
/// the phrase. Else it loses the first words of the command.
public protocol PrerollControl: AnyObject {
    /// The next `begin` gives the engine this much audio from before it, up to the audio that the engine keeps
    /// (3 s). Later turns use the usual preroll again.
    func setNextPreroll(seconds: Double)
}

/// The owner's voice and the tokens of the wake phrase, from the enrolment in the management window.
/// It holds no audio. It stays on the Mac in `voice.json` in the store folder (R-MD-1).
/// The voice counts for any phrase. The learned tokens count only for the phrase of the enrolment.
public struct VoiceProfile: Codable, Equatable, Sendable {
    /// The wake phrase that the owner said in the enrolment.
    public var phrase: String
    /// The speaker embedding: the normalized mean of the enrolment embeddings.
    public var embedding: [Float]
    /// The word pieces that the spotter heard for each enrolment phrase. The spotter listens for each of them.
    /// The model hears a made-up name such as "earshot" as other words ("your shot"), so the spelled pieces alone
    /// almost never fire. Empty if the spelled phrase fired on the enrolment: then extra forms only add false wakes.
    public var keywordTokens: [[String]]
    /// The number of enrolment phrases.
    public var samples: Int
    /// The lowest score of one enrolment phrase against the mean. A low value means a noisy enrolment.
    public var selfScore: Double
    public var createdAt: Date

    public init(phrase: String, embedding: [Float], keywordTokens: [[String]], samples: Int, selfScore: Double,
                createdAt: Date = Date()) {
        self.phrase = phrase; self.embedding = embedding; self.keywordTokens = keywordTokens
        self.samples = samples; self.selfScore = selfScore; self.createdAt = createdAt
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
