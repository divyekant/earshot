@testable import EarshotApp
import EarshotCore
import XCTest

// R-ON-1, R-ON-4: a settings change in the Manage window starts the right parts again.
// Live trial 2026-11-02: a new wake phrase was saved, but the listener kept the old phrase until a restart.
final class SettingsRestartTests: XCTestCase {
    private func change(_ edit: (inout EarshotSettings) -> Void) -> SettingsRestart {
        let old = EarshotSettings()
        var new = old
        edit(&new)
        return SettingsRestart.needed(from: old, to: new)
    }

    func testNoChangeRestartsNothing() {
        XCTAssertEqual(change { _ in }, [])
        XCTAssertEqual(change { $0.showFeedback.toggle() }, [], "the pipeline reads it at once")
        XCTAssertEqual(change { $0.typeIntoOthers.toggle() }, [], "the action options read it at once")
    }

    func testWakeSettingsRestartTheInput() {
        XCTAssertEqual(change { $0.wakePhrase = "hey atlas" }, .input)
        XCTAssertEqual(change { $0.voiceThreshold = 0.5 }, .input)
        XCTAssertEqual(change { $0.voiceGate = 0.2 }, .input, "E6: the gate of the phrase")
        XCTAssertEqual(change { $0.turnVoiceThreshold = 0.45 }, .input, "E6: the limit of a whole turn")
        XCTAssertEqual(change { $0.mode = .alwaysOn }, .input)
        XCTAssertEqual(change { $0.holdKeyCode = 58 }, .input)
    }

    func testEngineAndJev() {
        XCTAssertEqual(change { $0.engine = .apple }, .engine)
        XCTAssertEqual(change { $0.locale = "en_GB" }, .engine)
        XCTAssertEqual(change { $0.tier2 = .jev }, .jev)
        XCTAssertEqual(change { $0.jevSeesScreen = true }, .jev)
        XCTAssertEqual(change { $0.mode = .alwaysOn; $0.engine = .apple }, [.input, .engine])
    }
}
