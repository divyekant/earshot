import CoreML
import EarshotCore
import Foundation

/// The wake phrase models of always-on mode, loaded: the keyword spotter and the voice model (R-ON-1, R-ON-3, D-11).
/// Load it one time. It uses about 20 MB of files and about 60 to 80 MB of memory.
///
/// All model runs go through one lock, because a Core ML model must not run on two threads at the same time.
/// The wake listener runs on the input queue, and the enrolment runs on a task. The lock keeps them apart.
public final class WakeModels: @unchecked Sendable {
    /// The spotter with the default phrase. Each listener makes its own keyword graph from it.
    let base: WakeWordDetector
    let voice: VoiceModel
    private let lock = NSLock()
    /// The time of the load, in ms. For the log.
    public let loadMs: Double

    /// The keyword settings of the spotter. Test 3 (2026-11-02, synthetic voices): the spelled phrase with
    /// threshold 0.25 and boost 1.0 had no false wakes. Tokens learned from the owner's phrases need
    /// threshold 0.2 and boost 1.5 to fire.
    static let spelledThreshold = 0.25
    static let spelledBoost = 1.0
    static let learnedThreshold = 0.2
    static let learnedBoost = 1.5

    init(base: WakeWordDetector, voice: VoiceModel, loadMs: Double) {
        self.base = base; self.voice = voice; self.loadMs = loadMs
    }

    /// True if both model packs are in the store folder and checked.
    public static func isDownloaded(store: URL) -> Bool { WakeModelPacks.all.allSatisfy { $0.isReady(in: store) } }

    /// Downloads the missing model files (about 17.7 MB, one time), checks them, and loads the models.
    /// - Parameter progress: the part of the download done, 0 to 1.
    public static func load(store: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> WakeModels {
        let spotterBytes = Double(WakeModelPacks.spotter.totalBytes)
        let total = Double(WakeModelPacks.totalBytes)
        let spotterFolder = try await WakeModelPacks.spotter.ensure(in: store) { part in
            progress?(part * spotterBytes / total)
        }
        let voiceFolder = try await WakeModelPacks.voice.ensure(in: store) { part in
            progress?((spotterBytes + part * (total - spotterBytes)) / total)
        }
        let start = DispatchTime.now().uptimeNanoseconds
        let base = try WakeWordDetector.load(from: spotterFolder, keywords: [
            KeywordSpec(phrase: WakePhrase.defaultPhrase, acThreshold: spelledThreshold, boost: spelledBoost),
        ])
        let voice = try VoiceModel(folder: voiceFolder)
        // Run each model one time, so that the first wake does not pay the first-run cost.
        try base.warmUp()
        _ = try voice.embed([Float](repeating: 0, count: 16000))
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        return WakeModels(base: base, voice: voice, loadMs: ms)
    }

    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    /// The word pieces of the phrase as the spotter spells it, for example ["▁HE", "Y", "▁JA", "R", "VI", "S"].
    public func spelledPieces(_ phrase: String) -> [String] {
        let text = WakePhrase.words(phrase).joined(separator: " ")
        return base.bpeTokenizer.encode(text).compactMap { base.vocabulary.idToToken[$0] }
    }

    /// The keywords for the spotter: the spelled phrase, and the pieces that the spotter heard in the owner's
    /// enrolment, if the spelled phrase did not fire on it.
    static func keywords(phrase: String, spelled: [String], learned: [[String]]) -> [KeywordSpec] {
        var specs: [KeywordSpec] = []
        if !spelled.isEmpty {
            specs.append(KeywordSpec(phrase: phrase, acThreshold: spelledThreshold, boost: spelledBoost, tokens: spelled))
        }
        for pieces in learned where !pieces.isEmpty && pieces != spelled {
            specs.append(KeywordSpec(phrase: phrase, acThreshold: learnedThreshold, boost: learnedBoost, tokens: pieces))
        }
        return specs
    }

    /// Makes a listener for the phrase.
    /// The voice of the profile counts for any phrase. Its learned pieces count only for the phrase of the enrolment.
    /// - Parameter profile: nil if the owner did not teach earshot the voice. Then every voice can wake earshot.
    public func listener(phrase: String, profile: VoiceProfile?, voiceThreshold: Double) throws -> WakeListener {
        let spelled = spelledPieces(phrase)
        let learned = profile.map { $0.matches(phrase: phrase) ? $0.keywordTokens : [] } ?? []
        let specs = Self.keywords(phrase: phrase, spelled: spelled, learned: learned)
        guard !specs.isEmpty else { throw WakeError("The wake phrase has no words.") }
        return try PhraseListener(models: self, phrase: phrase, keywords: specs, profile: profile,
                                  voiceThreshold: voiceThreshold, nearMissLength: spelled.count)
    }

    /// Makes the owner's voice profile from the enrolment phrases (16 kHz mono, one phrase in each clip).
    /// The profile keeps no audio: only the mean embedding and the word pieces.
    public func enrol(phrase: String, clips: [[Float]]) throws -> Enrolment {
        let spoken = clips.map { SpeechTrim.trim($0) }.filter { $0.count >= 16000 / 4 }
        guard spoken.count >= 3 else {
            throw WakeError("earshot heard speech in \(spoken.count) of \(clips.count) phrases. Say the phrase again, near the Mac.")
        }
        return try locked {
            let spelled = spelledPieces(phrase)
            guard !spelled.isEmpty else { throw WakeError("The wake phrase has no words.") }
            let spelledOnly = try base.rebuildContextGraph(keywords: Self.keywords(phrase: phrase, spelled: spelled, learned: []))
            let reader = TokenReader(detector: base)
            var hits = 0
            var learned: [[String]] = []
            var embeddings: [[Float]] = []
            for clip in spoken {
                let padded = [Float](repeating: 0, count: 4800) + clip + [Float](repeating: 0, count: 9600)
                if !(try spelledOnly.detect(audio: padded)).isEmpty { hits += 1 }
                let pieces = try reader.pieces(clip)
                if pieces.count >= 3, pieces.count <= spelled.count + 6, pieces != spelled, !learned.contains(pieces) {
                    learned.append(pieces)
                }
                embeddings.append(try voice.embed(clip))
            }
            // A phrase of known words fires spelled. Then extra pieces only add false wakes (Test 3).
            let keep = hits >= spoken.count - 1 ? [] : learned
            let mean = Self.mean(embeddings)
            let selfScore = embeddings.map { VoiceModel.cosine($0, mean) }.min() ?? 0
            let profile = VoiceProfile(phrase: phrase, embedding: mean, keywordTokens: keep, samples: spoken.count,
                                       selfScore: selfScore)
            return Enrolment(profile: profile, spelledHits: hits, heardPieces: learned)
        }
    }

    /// The voice score of a clip against a profile: the cosine similarity, -1 to 1.
    public func voiceScore(_ samples: [Float], profile: VoiceProfile) throws -> Double {
        let clip = SpeechTrim.trim(samples)
        let embedding = try locked { try voice.embed(clip.isEmpty ? samples : clip) }
        return VoiceModel.cosine(embedding, profile.embedding)
    }

    static func mean(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for v in vectors where v.count == sum.count { for i in 0..<v.count { sum[i] += v[i] } }
        return VoiceModel.normalized(sum)
    }
}

/// The result of an enrolment, for the management window.
public struct Enrolment: Sendable {
    public let profile: VoiceProfile
    /// The phrases in which the spelled phrase fired. If it is low, earshot listens for the heard pieces too.
    public let spelledHits: Int
    /// The word pieces that the spotter heard, for each distinct phrase. For the log.
    public let heardPieces: [[String]]

    /// One line for the management window.
    public var summary: String {
        var text = "earshot knows your voice (\(profile.samples) phrases)."
        if profile.keywordTokens.isEmpty {
            text += " It heard the phrase in \(spelledHits) of \(profile.samples)."
        } else {
            text += " The phrase is not a known word, so earshot also listens for how you say it"
            text += " (\(profile.keywordTokens.count) forms). Sound-alike words can wake it."
        }
        if profile.selfScore < 0.5 {
            text += " The phrases differ a lot. Teach it again in a quiet room for a better match."
        }
        return text
    }
}

/// Cuts the quiet audio at the start and the end of a clip.
enum SpeechTrim {
    /// - Returns: the part from the first to the last loud 20 ms frame, with 150 ms more at each end.
    ///   Empty if no frame is loud.
    static func trim(_ samples: [Float], rate: Int = 16000) -> [Float] {
        let frame = rate / 50
        guard samples.count >= frame else { return [] }
        var levels: [Double] = []
        var i = 0
        while i + frame <= samples.count {
            var sum: Double = 0
            for s in samples[i..<(i + frame)] { sum += Double(s) * Double(s) }
            let rms = (sum / Double(frame)).squareRoot()
            levels.append(rms > 0 ? 20 * log10(rms) : -120)
            i += frame
        }
        let floor = levels.sorted()[levels.count / 10]
        let threshold = max(floor + 12, -50)
        guard let first = levels.firstIndex(where: { $0 >= threshold }),
              let last = levels.lastIndex(where: { $0 >= threshold }) else { return [] }
        let pad = rate * 15 / 100
        let start = max(0, first * frame - pad)
        let end = min(samples.count, (last + 1) * frame + pad)
        return Array(samples[start..<end])
    }
}
