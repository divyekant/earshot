import XCTest
import EarshotCore
@testable import EarshotSpeech

/// The microphone closes after 2 minutes with no command in hold mode, and stays open in always-on mode.
final class MicIdleTests: XCTestCase {
    func testHoldModeClosesAfterTwoMinutesAndAlwaysOnKeepsTheMicrophoneOpen() {
        XCTAssertEqual(MicIdle.seconds(for: .hold), 120)
        XCTAssertNil(MicIdle.seconds(for: .alwaysOn))
    }

    func testTheTimerRunsTheActionAfterTheIdleTime() {
        let timer = MicIdleTimer()
        timer.seconds = 0.05
        let ran = expectation(description: "idle action")
        timer.arm { ran.fulfill() }
        wait(for: [ran], timeout: 2)
    }

    func testCancelStopsTheTimer() {
        let timer = MicIdleTimer()
        timer.seconds = 0.05
        let ran = expectation(description: "idle action")
        ran.isInverted = true
        timer.arm { ran.fulfill() }
        timer.cancel()
        wait(for: [ran], timeout: 0.3)
    }

    func testANewArmReplacesTheOldTimer() {
        let timer = MicIdleTimer()
        timer.seconds = 0.05
        let old = expectation(description: "old action")
        old.isInverted = true
        let new = expectation(description: "new action")
        timer.arm { old.fulfill() }
        timer.arm { new.fulfill() }
        wait(for: [old, new], timeout: 0.3)
    }

    func testNoIdleTimeMeansNoTimer() {
        let timer = MicIdleTimer()
        let ran = expectation(description: "idle action")
        ran.isInverted = true
        timer.arm { ran.fulfill() }
        wait(for: [ran], timeout: 0.2)
    }

    func testANilIdleTimeCancelsATimerThatRuns() {
        let timer = MicIdleTimer()
        timer.seconds = 0.05
        let ran = expectation(description: "idle action")
        ran.isInverted = true
        timer.arm { ran.fulfill() }
        timer.seconds = nil
        wait(for: [ran], timeout: 0.3)
    }
}
