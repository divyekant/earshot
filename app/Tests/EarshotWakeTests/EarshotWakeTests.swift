import EarshotCore
import Foundation
import XCTest
@testable import EarshotWake

// D-11: the parts of the wake phrase module that need no model file.
final class WakePartsTests: XCTestCase {
    func testHalfRoundTrip() {
        let values: [Float] = [0, 1, -1, 0.5, 3.140625, -1000, 65504]
        var raw = [UInt16](repeating: 0, count: values.count)
        raw.withUnsafeMutableBytes { Half.store(values, count: values.count, to: $0.baseAddress!) }
        let back = raw.withUnsafeBytes { Half.load($0.baseAddress!, count: values.count) }
        XCTAssertEqual(back, values, "these values are exact in 16-bit floats")
        XCTAssertEqual(raw[1], 0x3C00, "1.0 in IEEE 754 half precision")
    }

    func testTrimCutsTheQuietEnds() {
        let quiet = [Float](repeating: 0.0005, count: 8000)
        let tone = (0..<8000).map { Float(sin(Double($0) * 0.1) * 0.1) }
        let clip = quiet + tone + quiet
        let trimmed = SpeechTrim.trim(clip)
        // The tone, plus 150 ms at each end, to the 20 ms frame.
        XCTAssertEqual(Double(trimmed.count), 8000 + 2 * 2400, accuracy: 640)
        XCTAssertTrue(SpeechTrim.trim(quiet).isEmpty, "no speech: nothing")
        XCTAssertTrue(SpeechTrim.trim([]).isEmpty)
    }

    func testSpanFromTimeStamps() {
        // Word pieces at encoder frames 10 to 20 (40 ms each): 0.4 s to 0.84 s.
        let span = PhraseListener.span(stamps: [10, 14, 20], total: 32000, ringStart: 0)
        XCTAssertEqual(span.start, 10 * 640 - 4800, "300 ms before the first piece")
        XCTAssertEqual(span.end, 21 * 640)
        XCTAssertEqual(span.clipEnd, 21 * 640 + 3200)
    }

    func testSpanStaysInTheKeptAudio() {
        let span = PhraseListener.span(stamps: [2, 9], total: 200_000, ringStart: 100_000)
        XCTAssertEqual(span.start, 100_000, "the audio before the ring is gone")
        XCTAssertGreaterThanOrEqual(span.clipEnd, span.end)
        let none = PhraseListener.span(stamps: [], total: 50_000, ringStart: 0)
        XCTAssertEqual(none.start, 50_000 - 32_000, "no time stamps: the last 2 s")
        XCTAssertEqual(none.end, 50_000)
    }

    func testKeywordsSpelledAndLearned() {
        let spelled = ["▁HE", "Y", "▁E", "AR", "S", "HO", "T"]
        let learned = [["▁HE", "Y", "▁YOUR", "▁SHOT"], spelled, []]
        let specs = WakeModels.keywords(phrase: "hey earshot", spelled: spelled, learned: learned)
        XCTAssertEqual(specs.map(\.tokens), [spelled, ["▁HE", "Y", "▁YOUR", "▁SHOT"]], "no copy of the spelled form")
        XCTAssertEqual(specs[0].acThreshold, WakeModels.spelledThreshold)
        XCTAssertEqual(specs[1].boost, WakeModels.learnedBoost)
        XCTAssertTrue(WakeModels.keywords(phrase: "", spelled: [], learned: []).isEmpty)
    }

    func testArgmax() {
        XCTAssertEqual(TokenReader.argmax([0.1, 3, -2, 2.9]), 1)
        XCTAssertEqual(TokenReader.argmax([5]), 0)
        XCTAssertNil(TokenReader.argmax([]))
    }

    func testCosineAndMean() {
        XCTAssertEqual(VoiceModel.cosine([1, 0], [1, 0]), 1, accuracy: 1e-6)
        XCTAssertEqual(VoiceModel.cosine([1, 0], [0, 1]), 0, accuracy: 1e-6)
        XCTAssertEqual(VoiceModel.cosine([1, 0], [1]), 0, "different lengths")
        let mean = WakeModels.mean([[1, 0], [0, 1]])
        XCTAssertEqual(mean[0], Float(0.5).squareRoot(), accuracy: 1e-6)
        XCTAssertEqual(mean[1], Float(0.5).squareRoot(), accuracy: 1e-6)
    }

    func testEnrolmentSummary() {
        let known = Enrolment(profile: VoiceProfile(phrase: "hey jarvis", embedding: [1], keywordTokens: [], samples: 5,
                                                    selfScore: 0.8), spelledHits: 5, heardPieces: [])
        XCTAssertTrue(known.summary.contains("5 of 5"), known.summary)
        let madeUp = Enrolment(profile: VoiceProfile(phrase: "hey earshot", embedding: [1], keywordTokens: [["▁A", "B", "C"]],
                                                     samples: 5, selfScore: 0.3), spelledHits: 0, heardPieces: [])
        XCTAssertTrue(madeUp.summary.contains("Sound-alike"), madeUp.summary)
        XCTAssertTrue(madeUp.summary.contains("quiet room"), madeUp.summary)
    }
}

// D-11: the model download is pinned and checked.
final class ModelFilesTests: XCTestCase {
    func testManifest() {
        for pack in WakeModelPacks.all {
            XCTAssertEqual(pack.revision.count, 40, pack.name)
            for file in pack.files {
                XCTAssertEqual(file.sha256.count, 64, file.path)
                XCTAssertTrue(file.sha256.allSatisfy { $0.isHexDigit }, file.path)
                XCTAssertGreaterThan(file.size, 0, file.path)
                XCTAssertTrue(pack.url(of: file).absoluteString.hasPrefix("https://huggingface.co/\(pack.repo)/resolve/\(pack.revision)/"))
            }
        }
        let names = Set(WakeModelPacks.spotter.files.map(\.path))
        for needed in ["encoder.mlmodelc/model.mil", "decoder.mlmodelc/model.mil", "joiner.mlmodelc/model.mil", "tokens.txt",
                       "bpe.model", "config.json"] {
            XCTAssertTrue(names.contains(needed), needed)
        }
        XCTAssertEqual(Double(WakeModelPacks.totalBytes), 17.7e6, accuracy: 0.1e6)
    }

    func testFolderAndReady() throws {
        let store = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: store) }
        let pack = WakeModelPacks.voice
        XCTAssertEqual(pack.folder(in: store).lastPathComponent, "wespeaker-resnet34-lm-b358f33")
        XCTAssertFalse(pack.isReady(in: store))
    }

    func testCheckFindsABadFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("x")
        try Data("abc".utf8).write(to: url)
        let good = ModelFile(path: "x", size: 3, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertNoThrow(try ModelPack.check(url, against: good, pack: "test"))
        let badSum = ModelFile(path: "x", size: 3, sha256: String(repeating: "0", count: 64))
        XCTAssertThrowsError(try ModelPack.check(url, against: badSum, pack: "test"))
        let badSize = ModelFile(path: "x", size: 4, sha256: good.sha256)
        XCTAssertThrowsError(try ModelPack.check(url, against: badSize, pack: "test"))
    }
}

// D-11: the near-miss count of the spotter, with a fake joiner. Token 0 is the blank. The phrase is 1 2 3 4.
final class NearMissTests: XCTestCase {
    private func decoder(autoResetSeconds: Double = 5) -> StreamingKwsDecoder {
        let graph = ContextGraph(contextScore: 1.0, acThreshold: 0.5)
        graph.build(tokenIds: [[1, 2, 3, 4]], phrases: ["test"], boosts: [0], thresholds: [0])
        let d = StreamingKwsDecoder(decoderFn: { _ in [0] }, joinerFn: { frame, _ in frame.map { $0 * 10 } },
                                    contextGraph: graph, blankId: 0, contextSize: 2, beam: 1, numTrailingBlanks: 1,
                                    frameShiftSeconds: 0.04, autoResetSeconds: autoResetSeconds)
        d.nearMissLength = 4
        return d
    }

    /// One frame for each token: the joiner gives that token the top score.
    private func run(_ d: StreamingKwsDecoder, _ tokens: [Int]) -> Int {
        var emissions = 0
        for token in tokens {
            var frame = [Float](repeating: 0, count: 6)
            frame[token] = 1
            emissions += d.step(encoderFrame: frame).count
        }
        return emissions
    }

    private let blanks = [Int](repeating: 0, count: 30)

    func testPartialMatchThatFallsBackIsANearMiss() {
        let d = decoder()
        XCTAssertEqual(run(d, [1, 0, 2, 0, 3, 0, 5] + blanks), 0)
        let m = d.takeNearMisses()
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m.best, 0.75, accuracy: 1e-9, "3 of the 4 pieces matched")
        XCTAssertEqual(d.takeNearMisses().count, 0, "take starts the count again")
    }

    func testFullMatchIsNoNearMiss() {
        let d = decoder()
        XCTAssertEqual(run(d, [1, 2, 3, 4, 0, 0] + blanks), 1)
        XCTAssertEqual(d.takeNearMisses().count, 0)
    }

    func testFallBackRightBeforeAWakeIsNoNearMiss() {
        // The top hypothesis can fall back for a short time in a real wake. The cooldown keeps it out of the count.
        let d = decoder()
        XCTAssertEqual(run(d, [1, 2, 3, 5, 1, 2, 3, 4, 0, 0] + blanks), 1)
        XCTAssertEqual(d.takeNearMisses().count, 0)
    }

    func testShortPartialMatchIsNoNearMiss() {
        let d = decoder()
        XCTAssertEqual(run(d, [1, 5] + blanks), 0)
        XCTAssertEqual(d.takeNearMisses().count, 0, "1 of 4 pieces is less than half")
    }

    func testAutoResetInAPartialMatchIsANearMiss() {
        let d = decoder(autoResetSeconds: 0.4)   // 10 frames
        XCTAssertEqual(run(d, [1, 2, 3] + blanks + blanks), 0)
        let m = d.takeNearMisses()
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m.best, 0.75, accuracy: 1e-9)
    }

    func testNoLengthCountsNothing() {
        let d = decoder()
        d.nearMissLength = 0
        XCTAssertEqual(run(d, [1, 2, 3, 5] + blanks), 0)
        XCTAssertEqual(d.takeNearMisses().count, 0)
    }
}
