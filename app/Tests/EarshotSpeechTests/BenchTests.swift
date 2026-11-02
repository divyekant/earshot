import EarshotCore
import Foundation
import XCTest
@testable import EarshotSpeech

/// Measures the engines on audio files that `say` makes. It needs no microphone.
/// It runs only with EARSHOT_SPEECH_BENCH=1, because the Parakeet load takes about 14 s.
/// Run: EARSHOT_SPEECH_BENCH=1 swift test --filter BenchTests
final class BenchTests: XCTestCase {
    static let phrases = [
        "open slack", "message aditi on whatsapp", "type hello there", "scroll down", "go back",
        "click the second result", "open messages", "show numbers", "search for swift concurrency",
        "send", "open notes", "click sign in",
    ]

    var enabled: Bool { ProcessInfo.processInfo.environment["EARSHOT_SPEECH_BENCH"] == "1" }

    func makeAudio() throws -> [(String, URL)] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("earshot-speech-bench")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [(String, URL)] = []
        for (i, phrase) in Self.phrases.enumerated() {
            let url = dir.appendingPathComponent("p\(i).aiff")
            if !FileManager.default.fileExists(atPath: url.path) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                p.arguments = ["-o", url.path, phrase]
                try p.run()
                p.waitUntilExit()
            }
            out.append((phrase, url))
        }
        return out
    }

    func report(_ name: String, _ rows: [(String, Utterance)]) {
        let times = rows.map(\.1.ms).sorted()
        let median = times[(times.count - 1) / 2]
        let p90 = times[max(0, Int((0.9 * Double(times.count)).rounded(.up)) - 1)]
        let exact = rows.filter { normalize($0.1.text) == normalize($0.0) }.count
        print("BENCH \(name): \(rows.count) files, exact \(exact)/\(rows.count), median \(fmt(median)) ms, p90 \(fmt(p90)) ms")
        for (phrase, u) in rows { print("BENCH \(name)   \(fmt(u.ms)) ms  \"\(phrase)\" -> \"\(u.text)\"") }
    }

    func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }.split(separator: " ").joined(separator: " ")
    }

    func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

    func testParakeetBench() async throws {
        try XCTSkipUnless(enabled, "set EARSHOT_SPEECH_BENCH=1")
        guard let model = ParakeetModelLocator().find(configured: "") else { throw XCTSkip("no Parakeet model file in the Hex folder") }
        let files = try makeAudio()
        let engine = ParakeetEngine(modelPath: model, useMicrophone: false)
        let t0 = SpeechClock.nowNs()
        try await engine.prepare()
        print("BENCH parakeet: load and warm-up \(fmt(SpeechClock.ms(since: t0))) ms")
        var rows: [(String, Utterance)] = []
        for (phrase, url) in files { rows.append((phrase, try await engine.transcribe(file: url))) }
        report("parakeet", rows)
        XCTAssertGreaterThan(rows.filter { !$0.1.text.isEmpty }.count, files.count / 2)
    }

    func testAppleBench() async throws {
        try XCTSkipUnless(enabled, "set EARSHOT_SPEECH_BENCH=1")
        let files = try makeAudio()
        let engine = AppleSpeechEngine()
        let t0 = SpeechClock.nowNs()
        try await engine.prepareModel()
        print("BENCH apple: model check and load \(fmt(SpeechClock.ms(since: t0))) ms")
        var rows: [(String, Utterance)] = []
        for (phrase, url) in files { rows.append((phrase, try await engine.transcribe(file: url))) }
        report("apple", rows)
        XCTAssertGreaterThan(rows.filter { !$0.1.text.isEmpty }.count, files.count / 2)
    }
}
