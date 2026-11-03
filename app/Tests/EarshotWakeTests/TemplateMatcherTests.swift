import Foundation
import XCTest
@testable import EarshotWake

// D-11, E5: the audio template match, with made-up frames. No model file is needed.
final class TemplateMatcherTests: XCTestCase {
    /// Random frames from a fixed seed, 320 values each, as the encoder of the spotter gives.
    private func frames(_ count: Int, seed: UInt64) -> [[Float]] {
        var state = seed
        func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int64(bitPattern: state >> 11) % 2000) / 1000 - 1
        }
        return (0..<count).map { _ in (0..<320).map { _ in next() } }
    }

    private func run(_ matcher: TemplateMatcher, _ stream: [[Float]]) -> [TemplateMatcher.Match] {
        stream.compactMap { matcher.push($0) }
    }

    /// The frames with a little noise: another take of the same sound.
    private func noisy(_ take: [[Float]], seed: UInt64, amount: Float = 0.1) -> [[Float]] {
        let noise = frames(take.count, seed: seed)
        return zip(take, noise).map { frame, n in zip(frame, n).map { $0 + amount * $1 } }
    }

    func testTheSameSoundWakes() {
        let phrase = frames(20, seed: 7)
        let takes = (0..<3).map { noisy(phrase, seed: 200 + UInt64($0)) }
        // The stream holds a fourth take after 30 other frames, then 10 more.
        let stream = frames(30, seed: 100) + noisy(phrase, seed: 300) + frames(10, seed: 101)
        let matches = run(TemplateMatcher(templates: takes), stream)
        XCTAssertEqual(matches.count, 1)
        guard let match = matches.first else { return }
        XCTAssertEqual(match.startFrame, 30)
        XCTAssertEqual(match.endFrame, 49)
        XCTAssertLessThan(match.score, 0.05)
        XCTAssertLessThanOrEqual(match.score, match.worst, "the worst part is not lower than the mean")
    }

    func testScoreIsTheMeanOfTheTwoBestTemplates() {
        let take = frames(20, seed: 3)
        let matcher = TemplateMatcher(templates: [take, take, frames(20, seed: 4)])
        let matches = run(matcher, frames(25, seed: 5) + take + frames(5, seed: 6))
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.score ?? 1, 0, accuracy: 1e-5, "two templates are the same as the speech")
        XCTAssertEqual(matches.first?.worst ?? 1, 0, accuracy: 1e-5)
    }

    func testOneUnrelatedTemplateRaisesTheScore() {
        let take = frames(20, seed: 3)
        let matcher = TemplateMatcher(templates: [take, frames(20, seed: 8), frames(20, seed: 9)])
        XCTAssertTrue(run(matcher, frames(25, seed: 5) + take + frames(5, seed: 6)).isEmpty,
                      "one matching take of 3 is not enough: the score is the mean of the 2 best")
    }

    func testSlowerAndFasterSpeechStillWake() {
        let take = frames(20, seed: 11)
        let templates = [take, take, take]
        // Slower: each odd frame twice. Faster: every third frame left out, but not the last one.
        let slower = take.enumerated().flatMap { $0.offset % 2 == 1 ? [$0.element, $0.element] : [$0.element] }
        let faster = take.enumerated().filter { $0.offset % 3 != 1 || $0.offset == take.count - 1 }.map(\.element)
        for (name, speech) in [("slower", slower), ("faster", faster)] {
            let matches = run(TemplateMatcher(templates: templates), frames(20, seed: 12) + speech + frames(5, seed: 13))
            XCTAssertEqual(matches.count, 1, name)
            XCTAssertLessThan(matches.first?.score ?? 1, 0.05, name)
            XCTAssertEqual(matches.first?.startFrame, 20, name)
        }
    }

    func testUnrelatedSoundDoesNotWake() {
        let matcher = TemplateMatcher(templates: (0..<5).map { frames(20, seed: 20 + UInt64($0)) })
        XCTAssertTrue(run(matcher, frames(400, seed: 30)).isEmpty)
        XCTAssertGreaterThan(matcher.lastScore, 0.8, "random frames are almost unrelated: cosine distance about 1")
        XCTAssertEqual(matcher.takeNearMisses().count, 0)
    }

    func testNoSecondWakeInTheRefractoryTime() {
        let take = frames(15, seed: 40)
        let gap = frames(10, seed: 41)
        let near = run(TemplateMatcher(templates: [take, take]), take + gap + take + frames(5, seed: 42))
        XCTAssertEqual(near.count, 1, "the second phrase starts 25 frames after the first: less than 1.5 s")
        let far = run(TemplateMatcher(templates: [take, take]), take + frames(40, seed: 43) + take + frames(5, seed: 44))
        XCTAssertEqual(far.count, 2)
    }

    func testNearMissesAreCountedAndTaken() {
        let phrase = frames(20, seed: 50)
        // The limit 0.001 is below the score of another take of the same sound (about 0.005): a near miss.
        let matcher = TemplateMatcher(templates: [noisy(phrase, seed: 53), noisy(phrase, seed: 54)], limit: 0.001)
        XCTAssertTrue(run(matcher, frames(10, seed: 51) + noisy(phrase, seed: 55) + frames(10, seed: 52)).isEmpty)
        let misses = matcher.takeNearMisses()
        XCTAssertEqual(misses.count, 1)
        XCTAssertGreaterThanOrEqual(misses.best, 0.001)
        XCTAssertLessThan(misses.best, 0.001 + TemplateMatcher.nearMissMargin)
        XCTAssertEqual(matcher.takeNearMisses().count, 0, "taken: the count starts again")
    }

    func testAWakeIsNotANearMiss() {
        let take = frames(20, seed: 60)
        let matcher = TemplateMatcher(templates: [take, take])
        XCTAssertEqual(run(matcher, frames(10, seed: 61) + take + frames(10, seed: 62)).count, 1)
        XCTAssertEqual(matcher.takeNearMisses().count, 0)
    }

    func testResetStartsAgain() {
        let take = frames(20, seed: 70)
        let matcher = TemplateMatcher(templates: [take, take])
        _ = run(matcher, frames(10, seed: 71) + Array(take.prefix(15)))
        matcher.reset()
        XCTAssertEqual(matcher.lastScore, .infinity)
        let matches = run(matcher, Array(take.suffix(5)) + frames(10, seed: 72))
        XCTAssertTrue(matches.isEmpty, "the first part of the phrase was before the reset")
        let again = run(matcher, take + frames(5, seed: 73))
        XCTAssertEqual(again.first?.startFrame, 15, "frames count from the reset")
    }

    func testLowestScoreOfATake() {
        let take = frames(20, seed: 80)
        let matcher = TemplateMatcher(templates: [take, take])
        XCTAssertEqual(matcher.lowestScore(frames(5, seed: 81) + take + frames(5, seed: 82)), 0, accuracy: 1e-5)
        XCTAssertGreaterThan(matcher.lowestScore(frames(60, seed: 83)), 0.8)
        XCTAssertEqual(matcher.lowestScore([]), .infinity)
    }

    func testShortTemplatesAreLeftOut() {
        let matcher = TemplateMatcher(templates: [frames(1, seed: 90), [], frames(10, seed: 91)])
        XCTAssertEqual(matcher.templates.count, 1)
    }

    func testFramesAreScaledToLengthOne() {
        let unit = TemplateMatcher.unit([3, 4])
        XCTAssertEqual(unit[0], 0.6, accuracy: 1e-6)
        XCTAssertEqual(unit[1], 0.8, accuracy: 1e-6)
        XCTAssertEqual(TemplateMatcher.unit([0, 0]), [0, 0], "a frame of zeros stays")
        XCTAssertEqual(TemplateMatcher.dot([1, 2, 3], [4, 5, 6]), 32)
    }

    func testMatchCostIsSmallForOneSecondOfAudio() {
        let matcher = TemplateMatcher(templates: (0..<5).map { frames(25, seed: 100 + UInt64($0)) })
        let stream = frames(250, seed: 110)   // 10 s of encoder frames
        let start = DispatchTime.now().uptimeNanoseconds
        _ = run(matcher, stream)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        print(String(format: "template match: %.1f ms for 10 s of audio, 5 templates of 25 frames", ms))
        XCTAssertLessThan(ms, 1000, "the match must cost much less than the audio time")
    }
}
