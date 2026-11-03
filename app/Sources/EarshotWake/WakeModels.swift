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
    /// The turn model, or nil if it did not download or load (R-ON-1, I-2).
    let turn: TurnModel?
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

    /// True if the turn model is loaded.
    public var hasTurnModel: Bool { turn != nil }

    init(base: WakeWordDetector, voice: VoiceModel, turn: TurnModel? = nil, loadMs: Double) {
        self.base = base; self.voice = voice; self.turn = turn; self.loadMs = loadMs
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
        // The turn model is extra (16.8 MB, one time). A failure leaves always-on with the end silence alone.
        let turn = await loadTurnModel(store: store)
        return WakeModels(base: base, voice: voice, turn: turn, loadMs: ms)
    }

    /// Downloads, checks and loads the turn model, or returns nil.
    static func loadTurnModel(store: URL) async -> TurnModel? {
        do {
            let folder = try await WakeModelPacks.turn.ensure(in: store)
            let model = try TurnModel(folder: folder)
            try model.warmUp()
            return model
        } catch {
            NSLog("earshot wake: the turn model did not load: %@", "\(error)")
            return nil
        }
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
    /// The voice of the profile counts for any phrase. Its templates and learned pieces count only for the phrase of
    /// the enrolment. With templates (E5), the listener finds the phrase by its sound. Else the spelled spotter listens.
    /// - Parameter profile: nil if the owner did not teach earshot the voice. Then every voice can wake earshot.
    public func listener(phrase: String, profile: VoiceProfile?, voiceThreshold: Double) throws -> WakeListener {
        let templates = (profile?.templates(for: phrase) ?? []).map(WakeTemplates.unpack).filter { !$0.isEmpty }
        if templates.count >= TemplateMatcher.minTemplates {
            return try PhraseListener(models: self, phrase: phrase, templates: templates, profile: profile,
                                      voiceThreshold: voiceThreshold)
        }
        let spelled = spelledPieces(phrase)
        let learned = profile.map { $0.matches(phrase: phrase) ? $0.keywordTokens : [] } ?? []
        let specs = Self.keywords(phrase: phrase, spelled: spelled, learned: learned)
        guard !specs.isEmpty else { throw WakeError("The wake phrase has no words.") }
        return try PhraseListener(models: self, phrase: phrase, keywords: specs, profile: profile,
                                  voiceThreshold: voiceThreshold, nearMissLength: spelled.count)
    }

    /// Makes the owner's voice profile from the enrolment phrases (16 kHz mono, one phrase in each clip).
    /// The profile keeps no audio: only the mean voice embedding and the audio templates of the phrase (E5).
    /// A take that does not match the other takes gives no template. At least 3 templates must stay.
    public func enrol(phrase: String, clips: [[Float]]) throws -> Enrolment {
        let rate = 16000
        let takes = clips.compactMap { (clip: [Float]) -> (clip: [Float], speech: Range<Int>)? in
            guard let speech = SpeechTrim.span(clip), SpeechTrim.padded(clip, speech: speech).count >= rate / 4 else {
                return nil
            }
            return (clip: clip, speech: speech)
        }
        guard takes.count >= 3 else {
            throw WakeError("earshot heard speech in \(takes.count) of \(clips.count) phrases. Say the phrase again, near the Mac.")
        }
        guard !WakePhrase.words(phrase).isEmpty else { throw WakeError("The wake phrase has no words.") }
        return try locked {
            let reader = TokenReader(detector: base)
            var embeddings: [[Float]] = []
            var allFrames: [[[Float]]] = []
            var templates: [[[Float]]] = []
            for take in takes {
                let piece = SpeechTrim.padded(take.clip, speech: take.speech)
                let start = SpeechTrim.paddedStart(speech: take.speech)
                let frames = try reader.frames(piece, lead: WakeTemplates.leadSamples, tail: WakeTemplates.tailSamples)
                let speech = (take.speech.lowerBound - start)..<(take.speech.upperBound - start)
                allFrames.append(frames)
                templates.append(WakeTemplates.cut(frames, speech: speech))
                embeddings.append(try voice.embed(piece))
            }
            // Each take against the other takes: a take that the others would not wake on is left out.
            let scores = templates.indices.map { j -> Double in
                let others = templates.indices.filter { $0 != j }.map { templates[$0] }
                return TemplateMatcher(templates: others).lowestScore(allFrames[j])
            }
            let kept = templates.indices.filter { scores[$0] <= TemplateMatcher.defaultLimit && templates[$0].count >= 2 }
            guard kept.count >= TemplateMatcher.minTemplates else {
                throw WakeError("The phrases sound too different from each other (\(kept.count) of \(templates.count) match). "
                                + "Say the phrase the same way each time, in a quiet room, and teach earshot again.")
            }
            let mean = Self.mean(embeddings)
            let selfScore = embeddings.map { VoiceModel.cosine($0, mean) }.min() ?? 0
            let profile = VoiceProfile(phrase: phrase, embedding: mean, keywordTokens: [], samples: embeddings.count,
                                       selfScore: selfScore, templates: kept.map { WakeTemplates.pack(templates[$0]) })
            return Enrolment(profile: profile, takeScores: scores, templatesKept: kept.count)
        }
    }

    /// The voice check of a whole turn against a profile (E6): the cosine similarity, -1 to 1, and the speech that the
    /// model scored, in seconds. The quiet parts are cut first (`SpeechTrim.condensed`).
    public func voiceCheck(_ samples: [Float], profile: VoiceProfile) throws -> (score: Double, seconds: Double) {
        let clip = SpeechTrim.condensed(samples)
        let input = clip.isEmpty ? samples : clip
        let embedding = try locked { try voice.embed(input) }
        return (VoiceModel.cosine(embedding, profile.embedding), Double(input.count) / 16000)
    }

    /// The voice score of a clip against a profile: the cosine similarity, -1 to 1.
    public func voiceScore(_ samples: [Float], profile: VoiceProfile) throws -> Double {
        let clip = SpeechTrim.trim(samples)
        let embedding = try locked { try voice.embed(clip.isEmpty ? samples : clip) }
        return VoiceModel.cosine(embedding, profile.embedding)
    }

    /// The probability that the turn is done (Smart Turn v3.2), or nil if the model is not loaded or failed.
    public func turnScore(_ samples: [Float]) -> Double? {
        guard let turn, !samples.isEmpty else { return nil }
        do { return try locked { try turn.probability(samples) } } catch {
            NSLog("earshot wake: the turn model failed: %@", "\(error)")
            return nil
        }
    }

    static func mean(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for v in vectors where v.count == sum.count { for i in 0..<v.count { sum[i] += v[i] } }
        return VoiceModel.normalized(sum)
    }
}
