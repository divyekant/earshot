import EarshotCore
import XCTest
@testable import EarshotUI

/// The text of the menu bar panel (R-FB-1): plain words, no router details.
final class MenuPanelTests: XCTestCase {
    private func record(heard: String, intent: String, note: String, ok: Bool = true,
                        stages: [String: Double] = ["total": 300], at: TimeInterval = 0) -> ActivityRecord {
        var r = ActivityRecord(heard: heard, intent: intent, tier: .rules, ok: ok, note: note, stages: stages)
        r.at = Date(timeIntervalSince1970: at)
        return r
    }

    func testDidKeepsThePartBeforeTheRoute() {
        let r = record(heard: "open notes", intent: "Open Notes", note: "opened Notes · route: app name · screen: x")
        XCTAssertEqual(PanelText.did(r), "Opened Notes")
        XCTAssertEqual(PanelText.title(r), "“open notes”")
    }

    func testDidRemovesTheArrowAndUsesTheIntentForAnEmptyNote() {
        XCTAssertEqual(PanelText.did(record(heard: "h", intent: "i", note: "→ Slack · Udita")), "Slack · Udita")
        XCTAssertEqual(PanelText.did(record(heard: "h", intent: "Open Notes", note: "")), "Open Notes")
        XCTAssertEqual(PanelText.did(record(heard: "h", intent: "", note: "", ok: false)), "Not done")
    }

    func testDictationUsesTheIntentAsTitle() {
        // The log keeps no dictated words (R-MD-1), so the title is the intent.
        let r = record(heard: "", intent: "Type \"…\"", note: "typed · route: focused text field")
        XCTAssertEqual(PanelText.title(r), "Type \"…\"")
        XCTAssertTrue(PanelText.shows(r))
    }

    func testWordCountOnlyIsADictation() {
        XCTAssertEqual(PanelText.title(record(heard: "(15 words)", intent: "Type \"…\"", note: "typed")), "Dictation · 15 words")
        XCTAssertEqual(PanelText.title(record(heard: "(1 word)", intent: "Type \"…\"", note: "typed")), "Dictation · 1 word")
        XCTAssertEqual(PanelText.title(record(heard: "Type. (14 words).", intent: "Type \"…\"", note: "typed")),
                       "“Type. (14 words).”")
    }

    func testRecentSkipsRecordsWithNoCommandAndKeepsTheNewestFirst() {
        let rows = [
            record(heard: "a", intent: "A", note: "", at: 1),
            record(heard: "", intent: "none", note: "no words", ok: false, at: 2),
            record(heard: "wake", intent: "none", note: "rejected wake", stages: [:], at: 3),
            record(heard: "b", intent: "B", note: "", at: 4),
            record(heard: "c", intent: "C", note: "", at: 5),
        ]
        XCTAssertEqual(PanelText.recent(rows, count: 2).map(\.heard), ["c", "b"])
        XCTAssertEqual(PanelText.recent(rows).map(\.heard), ["c", "b", "a"])
    }

    func testManagePagesAreFourTextLinks() {
        XCTAssertEqual(ManagePage.allCases.map(\.title), ["Settings", "Activity", "Plugins", "Advanced"])
    }
}
