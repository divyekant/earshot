import EarshotCore
import XCTest
@testable import EarshotUI

// Item 10 of the gap list: the menu bar icon shows if earshot listens.

final class ListenStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testIdleByDefault() {
        XCTAssertEqual(ListenClock().state(at: t0), .idle)
        XCTAssertNil(ListenClock().nextChange(after: t0))
    }

    func testOpenTurnListens() {
        var c = ListenClock()
        c.turnStarted()
        XCTAssertEqual(c.state(at: t0), .listening)
    }

    func testFollowUpWindowStartsAfterTheSoundAndEnds() {
        var c = ListenClock()
        c.turnStarted()
        c.turnFinished(at: t0, followUpSeconds: 5, soundSeconds: 1)
        XCTAssertEqual(c.state(at: t0.addingTimeInterval(5.9)), .followUp)
        XCTAssertEqual(c.state(at: t0.addingTimeInterval(6)), .idle)
        XCTAssertEqual(c.nextChange(after: t0), t0.addingTimeInterval(6))
    }

    func testHoldTurnOpensNoWindow() {
        var c = ListenClock()
        c.turnStarted()
        c.turnFinished(at: t0, followUpSeconds: nil)
        XCTAssertEqual(c.state(at: t0), .idle)
    }

    func testBareTypeExpectsText() {
        var c = ListenClock()
        c.turnFinished(at: t0, followUpSeconds: nil, armedUntil: t0.addingTimeInterval(5))
        XCTAssertEqual(c.state(at: t0.addingTimeInterval(4)), .textExpected)
        XCTAssertEqual(c.state(at: t0.addingTimeInterval(5)), .idle)
    }

    func testAlwaysOnTypingExpectsTextInTheWindow() {
        var c = ListenClock()
        c.turnFinished(at: t0, followUpSeconds: 5, expectsText: true)
        XCTAssertEqual(c.state(at: t0.addingTimeInterval(1)), .textExpected)
        XCTAssertEqual(c.state(at: t0.addingTimeInterval(5)), .idle)
    }

    func testDropClosesTheWindows() {
        var c = ListenClock()
        c.turnFinished(at: t0, followUpSeconds: 5)
        c.turnStarted()
        c.turnDropped()
        XCTAssertEqual(c.state(at: t0.addingTimeInterval(1)), .idle)
    }

    func testPauseWinsAndEnds() {
        var c = ListenClock()
        c.pausedUntil = t0.addingTimeInterval(3600)
        c.turnStarted()
        XCTAssertEqual(c.state(at: t0), .paused)
        XCTAssertEqual(c.nextChange(after: t0), t0.addingTimeInterval(3600))
        c.turnOpen = false
        XCTAssertEqual(c.state(at: t0.addingTimeInterval(3600)), .idle)
    }

    func testEachStateHasItsOwnIconAndLabel() {
        XCTAssertEqual(Set(ListenState.allCases.map(\.symbol)).count, ListenState.allCases.count)
        XCTAssertEqual(ListenState.idle.symbol, "ear", "the idle icon stays the ear of v0.3.0")
        XCTAssertTrue(ListenState.idle.label(mode: .alwaysOn, wakePhrase: "hey atlas").contains("hey atlas"))
        XCTAssertFalse(ListenState.idle.label(mode: .hold, wakePhrase: "hey atlas").contains("hey atlas"))
        XCTAssertTrue(ListenState.paused.label(mode: .hold, wakePhrase: "", pausedUntil: t0).hasPrefix("Paused until"))
    }
}
