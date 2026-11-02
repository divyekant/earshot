import EarshotCore
import Foundation

/// Listens for the wake phrase in 16 kHz mono audio, and checks the voice of the phrase (R-ON-1, R-ON-3, D-11).
/// It keeps the last 6 s of audio in memory for the voice check and drops older audio. It saves no audio.
/// One queue calls it (the input queue of the wake trigger).
final class PhraseListener: WakeListener {
    let phrase: String
    let voiceThreshold: Double
    private let models: WakeModels
    private let session: WakeWordSession
    private let profile: VoiceProfile?

    static let rate = 16000
    /// One encoder frame of the spotter is 40 ms.
    static let samplesPerFrame = 640
    /// The spotter marks a word piece a little after the sound starts. Start the phrase this much earlier.
    static let leadSamples = 4800
    /// Audio after the last word piece that still belongs to the phrase, for the voice check.
    static let tailSamples = 3200
    /// A small margin for the speech engine, so that it surely starts before the phrase.
    static let prerollMargin = 0.15
    static let keepSamples = 6 * 16000

    private var ring: [Float] = []
    /// The sample index of `ring[0]`, counted from the start of the session.
    private var ringStart = 0
    /// The samples fed since the start of the session.
    private var total = 0

    init(models: WakeModels, phrase: String, keywords: [KeywordSpec], profile: VoiceProfile?,
         voiceThreshold: Double) throws {
        self.models = models
        self.phrase = phrase
        self.profile = profile
        self.voiceThreshold = voiceThreshold
        let detector = try models.locked { try models.base.rebuildContextGraph(keywords: keywords) }
        session = try detector.createSession()
    }

    func feed(_ samples: [Float]) -> WakeHit? {
        guard !samples.isEmpty else { return nil }
        ring.append(contentsOf: samples)
        total += samples.count
        if ring.count > Self.keepSamples * 2 {
            let drop = ring.count - Self.keepSamples
            ring.removeFirst(drop)
            ringStart += drop
        }
        let detections: [KeywordDetection]
        do {
            detections = try models.locked { try session.pushAudio(samples) }
        } catch {
            NSLog("earshot wake: the spotter failed: %@", "\(error)")
            return nil
        }
        guard let detection = detections.first else { return nil }
        return hit(for: detection)
    }

    /// Makes the hit: the phrase span, the voice score and the preroll for the speech engine.
    func hit(for detection: KeywordDetection) -> WakeHit {
        let stamps = detection.streamTimestamps ?? []
        let span = Self.span(stamps: stamps, total: total, ringStart: ringStart)
        var score: Double?
        if let profile, span.clipEnd > span.start {
            let clip = Array(ring[(span.start - ringStart)..<(span.clipEnd - ringStart)])
            score = try? models.voiceScore(clip, profile: profile)
        }
        let isOwner = profile == nil || (score ?? -1) >= voiceThreshold
        return WakeHit(phrase: phrase,
                       prerollSeconds: Double(total - span.start) / Double(Self.rate) + Self.prerollMargin,
                       phraseEndSeconds: Double(max(0, total - span.end)) / Double(Self.rate),
                       voiceScore: score, isOwner: isOwner)
    }

    /// The phrase in sample indexes: the start, the end of the last word piece, and the end of the voice clip.
    /// With no time stamps, it takes the last 2 s.
    static func span(stamps: [Int], total: Int, ringStart: Int) -> (start: Int, end: Int, clipEnd: Int) {
        guard let first = stamps.first, let last = stamps.last, last >= first else {
            return (max(ringStart, total - 2 * rate), total, total)
        }
        let start = max(ringStart, 0, first * samplesPerFrame - leadSamples)
        let end = min(total, max(start, (last + 1) * samplesPerFrame))
        let clipEnd = min(total, max(end + tailSamples, start + rate / 2))
        return (min(start, total), end, clipEnd)
    }

    func voiceScore(_ samples: [Float]) -> Double? {
        guard let profile else { return nil }
        return try? models.voiceScore(samples, profile: profile)
    }

    func reset() {
        ring.removeAll(keepingCapacity: true)
        ringStart = 0
        total = 0
        do { try models.locked { try session.reset() } } catch {
            NSLog("earshot wake: the spotter reset failed: %@", "\(error)")
        }
    }
}
