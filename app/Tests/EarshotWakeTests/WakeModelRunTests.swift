import AVFoundation
import EarshotCore
import Foundation
import XCTest
@testable import EarshotWake

// D-11: the real models, with speech from the macOS `say` command. They need the model files (about 18 MB).
// Set EARSHOT_WAKE_MODELS to a folder: the test downloads the files there one time. CI sets it.
// The audio stays on the machine. The test prints the times for the pull request.
final class WakeModelRunTests: XCTestCase {
    static var models: WakeModels?

    private func loadModels() async throws -> WakeModels {
        guard let path = ProcessInfo.processInfo.environment["EARSHOT_WAKE_MODELS"], !path.isEmpty else {
            throw XCTSkip("set EARSHOT_WAKE_MODELS to a folder to run the wake model tests")
        }
        if let models = Self.models { return models }
        let store = URL(fileURLWithPath: path, isDirectory: true)
        do {
            let models = try await WakeModels.load(store: store)
            print("wake models: load and warm-up \(Int(models.loadMs)) ms")
            Self.models = models
            return models
        } catch let error as URLError {
            throw XCTSkip("no network for the model download: \(error.localizedDescription)")
        }
    }

    /// Speech from `say`, as 16 kHz mono samples. Skips the test if `say` does not work here.
    private func say(_ text: String, rate: Int = 180, voice: String? = nil) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("earshot-wake-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = (voice.map { ["-v", $0] } ?? []) + ["-r", "\(rate)", "-o", url.path, text]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("the say command did not make audio")
        }
        return try Self.read16k(url)
    }

    static func read16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
        try file.read(into: input)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: source, to: target),
              let out = AVAudioPCMBuffer(pcmFormat: target,
                                         frameCapacity: AVAudioFrameCount(Double(file.length) * 16000 / source.sampleRate + 1024))
        else { return [] }
        var given = false
        var error: NSError?
        _ = converter.convert(to: out, error: &error) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        guard let data = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
    }

    /// Feeds the clip, with quiet before and after, in blocks of 100 ms, as the microphone does.
    private func hits(_ listener: WakeListener, _ clip: [Float]) -> [WakeHit] {
        let audio = [Float](repeating: 0, count: 8000) + clip + [Float](repeating: 0, count: 16000)
        var out: [WakeHit] = []
        var i = 0
        while i < audio.count {
            let end = min(audio.count, i + 1600)
            if let hit = listener.feed(Array(audio[i..<end])) { out.append(hit) }
            i = end
        }
        return out
    }

    func testSpelledPieces() async throws {
        let models = try await loadModels()
        // The same pieces as sherpa-onnx text2token gave for this model in Test 1.
        XCTAssertEqual(models.spelledPieces("hey earshot"), ["▁HE", "Y", "▁E", "AR", "S", "HO", "T"])
        XCTAssertFalse(models.spelledPieces("hey jarvis").isEmpty)
    }

    func testSilenceNeverWakes() async throws {
        let models = try await loadModels()
        let listener = try models.listener(phrase: "hey jarvis", profile: nil, voiceThreshold: 0.45)
        XCTAssertTrue(hits(listener, [Float](repeating: 0, count: 48000)).isEmpty)
        let reader = TokenReader(detector: models.base)
        XCTAssertTrue(try models.locked { try reader.pieces([Float](repeating: 0, count: 16000)) }.isEmpty)
    }

    func testPhraseWakesAndOtherTalkDoesNot() async throws {
        let models = try await loadModels()
        var woke = 0
        var lags: [Double] = []
        for rate in [160, 185, 210] {
            let clip = try say("Hey Jarvis, open Notes.", rate: rate)
            let listener = try models.listener(phrase: "hey jarvis", profile: nil, voiceThreshold: 0.45)
            if let hit = hits(listener, clip).first {
                woke += 1
                XCTAssertTrue(hit.isOwner, "no profile: every voice counts")
                XCTAssertNil(hit.voiceScore)
                XCTAssertGreaterThan(hit.prerollSeconds, 0.5)
                lags.append(hit.phraseEndSeconds)
            }
        }
        print("wake: \"hey jarvis\" woke on \(woke) of 3 say clips; seconds from the phrase end to the wake: \(lags)")
        XCTAssertGreaterThanOrEqual(woke, 2)

        for text in ["Open Notes and close the door.", "Hey, are you there?", "Her shot was great, nice job."] {
            let listener = try models.listener(phrase: "hey jarvis", profile: nil, voiceThreshold: 0.45)
            XCTAssertTrue(hits(listener, try say(text)).isEmpty, text)
        }
    }

    func testEnrolmentAndVoiceCheck() async throws {
        let models = try await loadModels()
        let clips = try [150, 170, 190, 210, 230].map { try say("Hey Jarvis", rate: $0) }
        let start = DispatchTime.now().uptimeNanoseconds
        let enrolment = try models.enrol(phrase: "hey jarvis", clips: clips)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        let profile = enrolment.profile
        print("enrolment: \(Int(ms)) ms for 5 clips; spelled fired \(enrolment.spelledHits) of 5; self score "
              + String(format: "%.2f", profile.selfScore) + "; heard \(enrolment.heardPieces)")
        XCTAssertEqual(profile.embedding.count, 256)
        XCTAssertEqual(profile.samples, 5)
        XCTAssertGreaterThan(profile.selfScore, 0.3)

        // The same voice says the phrase in a command: the voice check passes.
        let listener = try models.listener(phrase: "hey jarvis", profile: profile, voiceThreshold: 0.3)
        let clip = try say("Hey Jarvis, open Notes.", rate: 180)
        let embedStart = DispatchTime.now().uptimeNanoseconds
        let score = try models.voiceScore(clip, profile: profile)
        let embedMs = Double(DispatchTime.now().uptimeNanoseconds - embedStart) / 1e6
        print(String(format: "voice: same voice score %.2f, one check %.0f ms", score, embedMs))
        XCTAssertGreaterThan(score, 0.3)
        if let hit = hits(listener, clip).first {
            print(String(format: "wake with profile: voice score %.2f, owner %@", hit.voiceScore ?? -1, hit.isOwner ? "yes" : "no"))
            XCTAssertNotNil(hit.voiceScore)
        }
    }

    /// D-11: the spotter's auto reset every 1.5 s cleared the beam in the middle of a phrase. The bench feeds the same
    /// clips at 6 offsets, so that the phrase falls on each part of the reset grid, with the upstream rule and with the
    /// hold. It prints the hits and the false wakes of both rules for the pull request.
    func testResetHoldBench() async throws {
        let models = try await loadModels()
        let offsets = stride(from: 0, to: 16000 * 3 / 2, by: 4000).map { $0 }   // 0 to 1.25 s, in 0.25 s steps
        func count(_ clips: [[Float]], hold: Int) throws -> Int {
            var n = 0
            for clip in clips {
                for offset in offsets {
                    let listener = try models.listener(phrase: "hey jarvis", profile: nil, voiceThreshold: 0.45)
                    (listener as? PhraseListener)?.resetHoldFrames = hold
                    if !hits(listener, [Float](repeating: 0, count: offset) + clip).isEmpty { n += 1 }
                }
            }
            return n
        }
        var positives: [[Float]] = []
        for text in ["Hey Jarvis, open Notes.", "Okay, so, hey Jarvis, open Notes."] {
            for rate in [170, 210] { positives.append(try say(text, rate: rate)) }
        }
        let negatives = try ["Open Notes and close the door.", "Hey, are you there?", "Her shot was great, nice job.",
                             "Hey, I was thinking about the jar of jam.", "They travel a lot, hey, it is nice."].map { try say($0) }
        let hold = WakeWordSession.defaultResetHoldFrames
        let heldHits = try count(positives, hold: hold), upstreamHits = try count(positives, hold: 0)
        let heldFalse = try count(negatives, hold: hold), upstreamFalse = try count(negatives, hold: 0)
        let p = positives.count * offsets.count, n = negatives.count * offsets.count
        print("reset hold bench: hits \(heldHits)/\(p) with the hold (\(hold) frames), \(upstreamHits)/\(p) with the upstream reset; "
              + "false wakes \(heldFalse)/\(n) with the hold, \(upstreamFalse)/\(n) with the upstream reset")
        XCTAssertGreaterThanOrEqual(heldHits, upstreamHits, "the hold must not lose a wake")
        XCTAssertLessThanOrEqual(heldFalse, upstreamFalse, "the hold must not add a false wake")
    }

    func testSpotterSpeed() async throws {
        let models = try await loadModels()
        let listener = try models.listener(phrase: "hey jarvis", profile: nil, voiceThreshold: 0.45)
        let audio = (0..<(16000 * 10)).map { Float(sin(Double($0) * 0.05) * 0.01) }
        let start = DispatchTime.now().uptimeNanoseconds
        _ = hits(listener, audio)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        print(String(format: "spotter: %.0f ms for 11.5 s of audio (%.1f %% of one core)", ms, ms / 115))
        XCTAssertLessThan(ms, 11_500 * 0.25, "the spotter must use well under one core")
    }
}
