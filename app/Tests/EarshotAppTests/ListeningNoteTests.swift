import EarshotCore
import EarshotUI
import XCTest
@testable import EarshotApp

// Live test 2026-11-11 (E7): the "Listening" note for each follow-up turn that another sound opened looked random.
@MainActor
final class ListeningNoteTests: XCTestCase {
    func testWhichTurnsShowTheListeningNote() {
        XCTAssertTrue(AppController.showsListening(mode: .hold, before: .idle), "a hold-key turn")
        XCTAssertTrue(AppController.showsListening(mode: .alwaysOn, before: .textExpected), "the text after \"type\"")
        XCTAssertFalse(AppController.showsListening(mode: .alwaysOn, before: .followUp),
                       "a follow-up turn with no phrase: often a sound that the voice check drops")
        XCTAssertFalse(AppController.showsListening(mode: .alwaysOn, before: .idle), "a wake shows it in onWake")
    }
}
