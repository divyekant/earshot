@testable import EarshotCore
import XCTest

/// Tab and window titles in menus and tab strips (R-NV-5). The strings are from a live read of Chrome's menus.
final class TitleTests: XCTestCase {
    static let fpl = "FPL Guru — AI Fantasy Premier League transfer tips, captain picks & chip strategy | FPL Guru"
    static let titles = [
        "Apple - Google Chrome - Profile 1",                       // a window
        fpl + " - Memory usage - 491 MB",                          // a tab button
        "(1) Sam Lee (@samlee_dev) / X - Inactive tab - 84.1 MB freed up",
    ]

    func testMenuTitlesNameTabsAndWindows() {
        XCTAssertTrue(WindowTitles.names("FPL Guru — AI Fantasy Premier L…icks & chip strategy | FPL Guru", in: Self.titles))
        XCTAssertTrue(WindowTitles.names("(1) Sam Lee (@samlee_dev) / X", in: Self.titles))
        XCTAssertTrue(WindowTitles.names("Apple", in: Self.titles), "the window menu lists the tab title of a window")
        XCTAssertTrue(WindowTitles.names(Self.fpl, in: Self.titles))
        XCTAssertFalse(WindowTitles.names("Close Tab", in: Self.titles))
        XCTAssertFalse(WindowTitles.names("FPL Guru…strategy", in: Self.titles), "a cut head needs 4 words")
        XCTAssertFalse(WindowTitles.names("FPL Guru — AI Fantasy…other text", in: Self.titles), "the tail must follow")
        XCTAssertFalse(WindowTitles.names("", in: Self.titles))
    }

    func testTitleIsPressableAtJevButCommandsStayStrict() {
        let menu = MenuElements.role, title = MenuElements.titleSubrole
        // The live failure: the Tab menu item was blocked because the page title has "transfer".
        XCTAssertFalse(SafetyPolicy.mayPress(label: Self.fpl, role: menu, spokenTarget: "fpl guru tab", tier: .jev, mode: .hold))
        XCTAssertTrue(SafetyPolicy.mayPress(label: Self.fpl, role: menu, subrole: title, spokenTarget: "fpl guru tab",
                                            tier: .jev, mode: .hold))
        // Commands and short titles keep the strict rule.
        XCTAssertFalse(SafetyPolicy.mayPress(label: "Close Tab", role: menu, spokenTarget: "close", tier: .jev, mode: .hold))
        XCTAssertFalse(SafetyPolicy.mayPress(label: "Close Tab", role: menu, subrole: title, spokenTarget: "close",
                                             tier: .jev, mode: .hold))
        XCTAssertFalse(SafetyPolicy.mayPress(label: "Delete account", role: menu, subrole: title, spokenTarget: "delete",
                                             tier: .jev, mode: .hold))
        // A long title that starts with a risky word stays risky.
        XCTAssertTrue(SafetyPolicy.isRisky("Delete your account and all its data - Settings", role: menu, subrole: title))
        // A tab button of a tab strip is a title too.
        XCTAssertFalse(SafetyPolicy.isRisky(Self.fpl, role: "AXRadioButton", subrole: "AXTabButton"))
        XCTAssertFalse(SafetyPolicy.isRisky(Self.fpl, role: "AXTab"))
        XCTAssertTrue(SafetyPolicy.isRisky(Self.fpl, role: "AXRadioButton"), "a plain radio button is a control")
    }

    func testMenuElementsCarryTheTitleMark() {
        let e = MenuElements.elements([MenuEntry(path: ["Tab", Self.fpl], isTitle: true), MenuEntry(path: ["Tab", "Close Tab"])])
        XCTAssertEqual(e.map(\.subrole), [MenuElements.titleSubrole, ""])
        XCTAssertEqual(e.map(\.risky), [false, true])
        XCTAssertEqual(e.map(SafetyPolicy.isRisky), [false, true])
    }
}
