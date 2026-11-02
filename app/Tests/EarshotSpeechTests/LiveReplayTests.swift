import AVFoundation
import EarshotCore
import Foundation
import XCTest
@testable import EarshotSpeech

/// Replays `say` audio files through the live turn path (begin, feed in real time, end), with no microphone
/// and no key presses. It measures the speech stage after key release, split into tail, wait and decode,
/// after different idle times. It runs only with EARSHOT_SPEECH_BENCH=1.
/// Run: EARSHOT_SPEECH_BENCH=1 swift test --filter LiveReplayTests
final class LiveReplayTests: XCTestCase {
    var enabled: Bool { ProcessInfo.processInfo.environment["EARSHOT_SPEECH_BENCH"] == "1" }
    let phrases = ["slack me running late", "open messages", "click the second result"]
    let chunkSeconds = 0.1

    func say(_ phrase: String, _ i: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("earshot-speech-replay")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("r\(i).aiff")
        if !FileManager.default.fileExists(atPath: url.path) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            p.arguments = ["-o", url.path, phrase]
            try p.run()
            p.waitUntilExit()
        }
        return url
    }

    func line(_ label: String, _ t: SpeechTiming?, _ text: String) {
        guard let t else { print("REPLAY \(label): no timing"); return }
        print(String(format: "REPLAY %@: total %.1f ms = tail %.1f + wait %.1f + decode %.1f | audio %.0f ms, idle %.0f ms, warmed %@ | \"%@\"",
                     label, t.totalMs, t.tailMs, t.waitMs, t.decodeMs, t.audioMs, t.idleMs, t.warmed ? "yes" : "no", text))
    }

    func testParakeetReplay() async throws {
        try XCTSkipUnless(enabled, "set EARSHOT_SPEECH_BENCH=1")
        guard let model = ParakeetModelLocator().find(configured: "") else { throw XCTSkip("no Parakeet model file") }
        let engine = ParakeetEngine(modelPath: model, useMicrophone: false)
        engine.reason = "bench"
        try await engine.prepare()
        let audio = try phrases.enumerated().map { try AudioUtil.readSamples16k(say($0.element, $0.offset)) }
        let chunk = Int(16000 * chunkSeconds)
        for warm in [false, true] {
            engine.warmAfterIdleSeconds = warm ? 2.0 : nil
            for idle in [0.0, 5.0, 20.0] {
                for (i, pcm) in audio.enumerated() {
                    if i == 0, idle > 0 { try await Task.sleep(nanoseconds: UInt64(idle * 1e9)) }
                    engine.beginWithoutMicrophone()
                    var at = 0
                    while at < pcm.count {
                        engine.feed(Array(pcm[at..<min(at + chunk, pcm.count)]))
                        at += chunk
                        try await Task.sleep(nanoseconds: UInt64(chunkSeconds * 1e9))
                    }
                    let u = try await engine.end()
                    line("parakeet warm=\(warm) idle=\(Int(idle))s #\(i)", engine.lastTiming, u.text)
                }
            }
        }
    }

    /// 20 commands in a row, 1 s apart. The speech stage must not grow over the session.
    func testParakeetTwentyCommands() async throws {
        try XCTSkipUnless(enabled, "set EARSHOT_SPEECH_BENCH=1")
        guard let model = ParakeetModelLocator().find(configured: "") else { throw XCTSkip("no Parakeet model file") }
        let engine = ParakeetEngine(modelPath: model, useMicrophone: false)
        try await engine.prepare()
        let pcm = try AudioUtil.readSamples16k(say(phrases[0], 0))
        let chunk = Int(16000 * chunkSeconds)
        var totals: [Double] = []
        for i in 0..<20 {
            engine.beginWithoutMicrophone()
            var at = 0
            while at < pcm.count {
                engine.feed(Array(pcm[at..<min(at + chunk, pcm.count)]))
                at += chunk
                try await Task.sleep(nanoseconds: UInt64(chunkSeconds * 1e9))
            }
            let u = try await engine.end()
            line("parakeet run20 #\(i)", engine.lastTiming, u.text)
            totals.append(engine.lastTiming?.totalMs ?? 0)
            XCTAssertEqual(engine.lastTiming?.audioMs ?? 0, Double(pcm.count) / 16 + TailPad.seconds * 1000, accuracy: 1,
                           "the audio of one command must not include earlier commands")
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let first = totals.prefix(5).sorted()[2], last = totals.suffix(5).sorted()[2]
        print(String(format: "REPLAY run20: median of first 5 %.1f ms, of last 5 %.1f ms", first, last))
        XCTAssertLessThan(last, first * 2 + 20, "the speech stage grew over 20 commands")
    }

    func testAppleReplay() async throws {
        try XCTSkipUnless(enabled, "set EARSHOT_SPEECH_BENCH=1")
        let engine = AppleSpeechEngine()
        engine.reason = "bench"
        let format = try await engine.prepareModel()
        for idle in [0.0, 5.0] {
            for (i, phrase) in phrases.enumerated() {
                if i == 0, idle > 0 { try await Task.sleep(nanoseconds: UInt64(idle * 1e9)) }
                let whole = try read(say(phrase, i), as: format)
                let feed = try engine.beginWithoutMicrophone()
                let chunk = AVAudioFrameCount(format.sampleRate * chunkSeconds)
                var at: AVAudioFrameCount = 0
                while at < whole.frameLength {
                    if let part = slice(whole, from: at, count: min(chunk, whole.frameLength - at)) { feed(part) }
                    at += chunk
                    try await Task.sleep(nanoseconds: UInt64(chunkSeconds * 1e9))
                }
                let u = try await engine.end()
                line("apple idle=\(Int(idle))s #\(i)", engine.lastTiming, u.text)
            }
        }
    }

    func read(_ url: URL, as format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        let converter = AVAudioConverter(from: file.processingFormat, to: format)!
        return AudioUtil.convert(buf, with: converter, to: format, endOfStream: true)!
    }

    func slice(_ b: AVAudioPCMBuffer, from start: AVAudioFrameCount, count: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: count) else { return nil }
        out.frameLength = count
        let bpf = Int(b.format.streamDescription.pointee.mBytesPerFrame)
        let src = UnsafeMutableAudioBufferListPointer(b.mutableAudioBufferList)
        let dst = UnsafeMutableAudioBufferListPointer(out.mutableAudioBufferList)
        for (s, d) in zip(src, dst) {
            guard let sp = s.mData, let dp = d.mData else { continue }
            memcpy(dp, sp.advanced(by: Int(start) * bpf), Int(count) * bpf)
        }
        return out
    }
}
