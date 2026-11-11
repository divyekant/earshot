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
    /// On the CI runner, `say` sometimes writes a file with only silence (seen on 2026-11-11 in PR #109 and #110:
    /// "heard speech in 0 of 5 phrases", then green on a re-run of the same commit). Then it tries again, up to 3
    /// times. Silence after 3 tries means that the runner cannot make speech: the test skips, it does not fail.
    private func say(_ text: String, rate: Int = 180, voice: String? = nil) throws -> [Float] {
        for _ in 0..<3 {
            let clip = try sayOnce(text, rate: rate, voice: voice)
            if clip.contains(where: { abs($0) > 0.001 }) { return clip }
            print("say: silent clip for \"\(text)\" at rate \(rate); trying again")
        }
        throw XCTSkip("the say command made only silence 3 times")
    }

    private func sayOnce(_ text: String, rate: Int, voice: String?) throws -> [Float] {
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
        print("enrolment: \(Int(ms)) ms for 5 clips; templates \(enrolment.templatesKept) of 5; take scores "
              + enrolment.takeScores.map { String(format: "%.2f", $0) }.joined(separator: " ")
              + String(format: "; self score %.2f", profile.selfScore))
        XCTAssertEqual(profile.embedding.count, 256)
        XCTAssertEqual(profile.samples, 5)
        XCTAssertGreaterThan(profile.selfScore, 0.3)
        XCTAssertGreaterThanOrEqual(enrolment.templatesKept, 3)
        XCTAssertEqual(profile.templates?.count, enrolment.templatesKept)
        XCTAssertTrue(profile.keywordTokens.isEmpty, "the templates replace the learned piece strings")

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

    /// E5 on CI: the audio templates of 5 `say` takes against the spelled spotter, for a known phrase, a name and a
    /// made-up word. It prints the hits, the false wakes and the scores for the pull request.
    func testTemplatesAgainstTheSpotter() async throws {
        let models = try await loadModels()
        let negatives = try ["Open Notes and close the door.", "Hey, are you there?", "Her shot was great, nice job.",
                             "They travel a lot, hey, it is nice.", "Can you open the calendar for me?"].map { try say($0) }
        var templateHits = 0, spotterHits = 0, commands = 0, templateFalse = 0, spotterFalse = 0
        var scores: [Double] = [], lags: [Double] = []
        for phrase in ["hey jarvis", "hey atlas", "hey zorbix"] {
            let cap = phrase.prefix(1).uppercased() + phrase.dropFirst()
            let takes = try [150, 170, 190, 210, 230].map { try say(cap, rate: $0) }
            let enrolment = try models.enrol(phrase: phrase, clips: takes)
            XCTAssertGreaterThanOrEqual(enrolment.templatesKept, 3, phrase)
            let profile = enrolment.profile
            var th = 0, sh = 0
            for (rate, command) in [(165, "open Notes"), (185, "scroll down"), (205, "what time is it"), (225, "open Slack")] {
                let clip = try say("\(cap), \(command).", rate: rate)
                commands += 1
                let listener = try models.listener(phrase: phrase, profile: profile, voiceThreshold: -1)
                XCTAssertNotNil((listener as? PhraseListener)?.matcher, "a taught phrase uses the templates")
                if let hit = hits(listener, clip).first {
                    th += 1
                    scores.append(hit.matchScore ?? -1)
                    lags.append(hit.phraseEndSeconds)
                    XCTAssertGreaterThan(hit.prerollSeconds, hit.phraseEndSeconds, "the preroll reaches the phrase start")
                }
                let spotter = try models.listener(phrase: phrase, profile: nil, voiceThreshold: -1)
                if !hits(spotter, clip).isEmpty { sh += 1 }
            }
            var tf = 0, sf = 0
            for clip in negatives {
                let listener = try models.listener(phrase: phrase, profile: profile, voiceThreshold: -1)
                let spotter = try models.listener(phrase: phrase, profile: nil, voiceThreshold: -1)
                tf += hits(listener, clip).count
                sf += hits(spotter, clip).count
            }
            let silent = try models.listener(phrase: phrase, profile: profile, voiceThreshold: -1)
            XCTAssertTrue(hits(silent, [Float](repeating: 0, count: 48000)).isEmpty, "silence never wakes")
            print("templates \"\(phrase)\": hits \(th)/4 (spotter \(sh)/4), false wakes \(tf)/\(negatives.count) "
                  + "(spotter \(sf)/\(negatives.count)), take scores "
                  + enrolment.takeScores.map { String(format: "%.2f", $0) }.joined(separator: " "))
            templateHits += th; spotterHits += sh; templateFalse += tf; spotterFalse += sf
        }
        print("templates against the spotter: hits \(templateHits)/\(commands) against \(spotterHits)/\(commands); "
              + "false wakes \(templateFalse) against \(spotterFalse); match scores "
              + scores.map { String(format: "%.2f", $0) }.joined(separator: " ") + "; seconds from the phrase end to the wake "
              + lags.map { String(format: "%.2f", $0) }.joined(separator: " "))
        XCTAssertGreaterThanOrEqual(templateHits, commands * 3 / 4)
        XCTAssertGreaterThanOrEqual(templateHits, spotterHits)
        XCTAssertLessThanOrEqual(templateFalse, 1)
    }

    /// The encoder and the template match, against the encoder and the keyword decoder, on 10 s of audio.
    func testTemplateListenerSpeed() async throws {
        let models = try await loadModels()
        let takes = try [150, 170, 190, 210, 230].map { try say("Hey Atlas", rate: $0) }
        let profile = try models.enrol(phrase: "hey atlas", clips: takes).profile
        let audio = (0..<(16000 * 10)).map { Float(sin(Double($0) * 0.05) * 0.01) }
        func time(_ listener: WakeListener) -> Double {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = hits(listener, audio)
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        }
        let templateListener = try models.listener(phrase: "hey atlas", profile: profile, voiceThreshold: 0.35)
        let spotterListener = try models.listener(phrase: "hey atlas", profile: nil, voiceThreshold: 0.35)
        let templates = time(templateListener)
        let spotter = time(spotterListener)
        print(String(format: "listener speed for 11.5 s of audio: templates %.0f ms (%.1f %% of one core), spotter %.0f ms (%.1f %%)",
                     templates, templates / 115, spotter, spotter / 115))
        XCTAssertLessThan(templates, 11_500 * 0.25, "the template listener must use well under one core")
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

    // E6: the voice check of a whole turn. The same voice passes the turn limit, a pause inside the turn is cut, and
    // the check is short: it runs before the turn ends, so its time is part of the command path. The print gives the
    // numbers for the pull request.
    func testTurnVoiceCheckSpeedAndScores() async throws {
        let models = try await loadModels()
        let takes = try [150, 170, 190, 210, 230].map { try say("Hey Atlas", rate: $0) }
        let profile = try models.enrol(phrase: "hey atlas", clips: takes).profile
        let pause = [Float](repeating: 0, count: 16000)
        let phrase = try say("Hey Atlas")
        let command = try say("open the notes app and make a new note")
        let turn = phrase + pause + command + [Float](repeating: 0, count: 16000 / 2)
        var times: [Double] = []
        var last: VoiceCheck?
        for _ in 0..<7 {
            let start = DispatchTime.now().uptimeNanoseconds
            last = try models.voiceCheck(turn, profile: profile)
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
        }
        let check = try XCTUnwrap(last)
        let phraseOnly = try models.voiceScore(phrase, profile: profile)
        let other = try? models.voiceCheck(try say("open the notes app and make a new note", voice: "Zarvox"), profile: profile)
        let sorted = times.sorted()
        print(String(format: "turn voice check: same voice %.2f on %.2f s of speech (audio %.2f s), phrase alone %.2f, "
                     + "other voice %.2f; check median %.1f ms, max %.1f ms", check.score, check.seconds,
                     Double(turn.count) / 16000, phraseOnly, other?.score ?? -1, sorted[sorted.count / 2], sorted.last ?? 0))
        XCTAssertLessThan(check.seconds, Double(turn.count) / 16000 - 0.9, "the 1 s pause is cut to 300 ms")
        XCTAssertGreaterThan(check.score, VoiceRule().limit(seconds: check.seconds), "the same voice passes the turn limit")
        XCTAssertLessThan(sorted[sorted.count / 2], 100, "a check must be short: it runs before the turn ends")

        // E6, section 8: a go-on part of the same voice, against the voice of the turn before it.
        let goOnClip = try say("and then the brown dog sat down on the mat")
        let goOn = try models.voiceCheck(goOnClip, profile: profile)
        let goOnLast = try XCTUnwrap(goOn.similarity(to: check.embedding))
        let otherLast = other.flatMap { $0.similarity(to: check.embedding) } ?? -1
        print(String(format: "last-turn check: same voice %.2f (profile %.2f) on %.2f s, other voice %.2f, level %.0f dB",
                     goOnLast, goOn.score, goOn.seconds, otherLast, goOn.level ?? 0))
        XCTAssertEqual(check.embedding.count, 256)
        XCTAssertGreaterThan(goOnLast, otherLast, "the same voice is nearer to its last turn than another voice")

        // E6, section 8.2: the profile learns the wake turn, so free speech of the same voice scores higher.
        let taught = profile.learning(check.embedding)
        let goOnTaught = try models.voiceCheck(goOnClip, profile: taught)
        let otherTaught = try? models.voiceCheck(try say("open the notes app and make a new note", voice: "Zarvox"),
                                                 profile: taught)
        print(String(format: "learned turn: same voice %.2f (was %.2f), other voice %.2f (was %.2f)",
                     goOnTaught.score, goOn.score, otherTaught?.score ?? -1, other?.score ?? -1))
        XCTAssertGreaterThan(goOnTaught.score, goOn.score)
    }

    // R-ON-1, I-2: the turn model gives a probability for a whole sentence and for a sentence cut in the middle, and
    // a check is fast enough for the audio queue. The print gives the numbers for the pull request.
    func testTurnModelSpeedAndScores() async throws {
        let models = try await loadModels()
        guard models.hasTurnModel else { throw XCTSkip("the turn model did not load") }
        let whole = try say("Open the notes app.")
        let cut = Array(try say("Send a message to the team and").prefix(16000 * 3 / 2))
        let silence = [Float](repeating: 0, count: 16000 * 3 / 10)
        var times: [Double] = []
        var scores: [Double] = []
        for audio in [whole + silence, cut + silence] {
            for _ in 0..<5 {
                let start = DispatchTime.now().uptimeNanoseconds
                let p = try XCTUnwrap(models.turnScore(audio))
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                XCTAssertTrue((0...1).contains(p))
                scores.append(p)
            }
        }
        let sorted = times.sorted()
        print(String(format: "turn model: P whole %.2f, P cut %.2f; check median %.1f ms, max %.1f ms",
                     scores[0], scores[5], sorted[sorted.count / 2], sorted.last ?? 0))
        XCTAssertLessThan(sorted[sorted.count / 2], 50, "a check must be short: it runs in the audio queue")
    }
}
