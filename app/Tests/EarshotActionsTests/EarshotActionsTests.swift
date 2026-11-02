import CoreGraphics
import EarshotCore
import Foundation
import XCTest
@testable import EarshotActions

final class ActionRulesTests: XCTestCase {
    // MARK: - Keys from the catalogue

    func testCatalogueKeysNeverNameReturn() {
        XCTAssertNotNil(Keys.parse("cmd+k"))
        XCTAssertEqual(Keys.parse("cmd+shift+k")?.flags.contains(.maskShift), true)
        XCTAssertNil(Keys.parse("cmd+return"))  // Command-Return sends in Messages (R-NV-5).
        XCTAssertNil(Keys.parse("return"))
        XCTAssertNil(Keys.parse("enter"))
        XCTAssertNil(Keys.parse("cmd+k+j"))     // one key only
        XCTAssertTrue(ActionRules.switcherKeysValid(""))
        XCTAssertFalse(ActionRules.switcherKeysValid("ctrl+return"))
    }

    func testTypedTextHasNoControlCharacters() {
        XCTAssertEqual(ActionText.printable("hi\nthere\r\t!"), "hithere!")
        XCTAssertEqual(ActionText.squash("a\u{200B} \u{00A0}b  c"), "a b c")
    }

    // MARK: - Chats

    func testHandleAndLink() {
        XCTAssertEqual(ActionRules.handle(name: "Ravi", aliases: ["ravi k", "+91 98765 43210"]), "+91 98765 43210")
        XCTAssertEqual(ActionRules.handle(name: "Ravi", aliases: ["ravi@example.com"]), "ravi@example.com")
        XCTAssertEqual(ActionRules.handle(name: "Ravi", aliases: []), "Ravi")
        XCTAssertEqual(ActionRules.linkURL(template: "app://chat?to={handle}", handle: "+91 98")?.absoluteString,
                       "app://chat?to=%2B91%2098")
        XCTAssertNil(ActionRules.linkURL(template: "app://chat", handle: "x"))
    }

    func testNameEntryLookup() {
        let names = [NameEntry(appID: "a", name: "Mrunal Shah", aliases: ["mrunal"], source: .sidebar),
                     NameEntry(appID: "b", name: "Mrunal", source: .sidebar)]
        XCTAssertEqual(ActionRules.nameEntry("mrunal shah", appID: "a", names: names)?.name, "Mrunal Shah")
        XCTAssertEqual(ActionRules.nameEntry("Mrunal", appID: "a", names: names)?.name, "Mrunal Shah")
        XCTAssertEqual(ActionRules.nameEntry("Mrunal", appID: "b", names: names)?.appID, "b")
        XCTAssertNil(ActionRules.nameEntry("Ravi", appID: "a", names: names))
    }

    func testChatCheck() {
        XCTAssertEqual(ActionRules.chatCheck(texts: ["Ravi Kumar - Slack"], names: ["Ravi Kumar"]), .exact)
        XCTAssertEqual(ActionRules.chatCheck(texts: ["Divyekant (you)"], names: ["Divyekant"]), .exact)
        XCTAssertEqual(ActionRules.chatCheck(texts: ["Ravi Kumar, Udita and 3 others"], names: ["Ravi Kumar"]), .partial)
        XCTAssertEqual(ActionRules.chatCheck(texts: ["general"], names: ["Ravi"]), .none)
        XCTAssertEqual(ActionRules.chatCheck(texts: ["R"], names: ["R"]), .none)  // too short to trust
    }

    func testTypingRules() {
        XCTAssertNil(ActionRules.typeBlock(isSelf: false, typeIntoOthers: true, check: .exact, boxText: ""))
        XCTAssertNotNil(ActionRules.typeBlock(isSelf: false, typeIntoOthers: false, check: .exact, boxText: ""))
        XCTAssertNil(ActionRules.typeBlock(isSelf: true, typeIntoOthers: false, check: .exact, boxText: ""))
        XCTAssertNotNil(ActionRules.typeBlock(isSelf: true, typeIntoOthers: true, check: .partial, boxText: ""))
        XCTAssertNotNil(ActionRules.typeBlock(isSelf: true, typeIntoOthers: true, check: .exact, boxText: "a draft"))
        XCTAssertNil(ActionRules.typeBlock(isSelf: true, typeIntoOthers: true, check: .exact, boxText: "\u{200B} "))
    }

    func testSwitcherReturnRule() {
        // The typed field, with exactly the name: Return opens the chat.
        XCTAssertTrue(ActionRules.switcherReturnSafe(focusedIsComposer: false, focusedIsTypedField: true, focusedIsSwitcherField: true,
                                                     focusedValue: " Ravi ", wanted: "ravi", focusedRole: "AXTextField"))
        // The field changed its text: no Return.
        XCTAssertFalse(ActionRules.switcherReturnSafe(focusedIsComposer: false, focusedIsTypedField: true, focusedIsSwitcherField: true,
                                                      focusedValue: "Ravi K", wanted: "ravi", focusedRole: "AXTextField"))
        // A message box: never.
        XCTAssertFalse(ActionRules.switcherReturnSafe(focusedIsComposer: true, focusedIsTypedField: true, focusedIsSwitcherField: true,
                                                      focusedValue: "ravi", wanted: "ravi", focusedRole: "AXTextArea"))
        // Another text field or a button: no. A result row: yes.
        XCTAssertFalse(ActionRules.switcherReturnSafe(focusedIsComposer: false, focusedIsTypedField: false, focusedIsSwitcherField: false,
                                                      focusedValue: nil, wanted: "ravi", focusedRole: "AXTextArea"))
        XCTAssertFalse(ActionRules.switcherReturnSafe(focusedIsComposer: false, focusedIsTypedField: false, focusedIsSwitcherField: false,
                                                      focusedValue: nil, wanted: "ravi", focusedRole: "AXButton"))
        XCTAssertTrue(ActionRules.switcherReturnSafe(focusedIsComposer: false, focusedIsTypedField: false, focusedIsSwitcherField: false,
                                                     focusedValue: nil, wanted: "ravi", focusedRole: "AXRow"))
    }

    func testSwitcherResultNeedsANewMatch() {
        let sidebar = ("Divyekant (you)", Frame(x: 20, y: 300, w: 200, h: 20))
        let baseline = ActionRules.matchKeys([sidebar, ("general", Frame(x: 20, y: 320, w: 200, h: 20))], name: "Divyekant")
        XCTAssertEqual(baseline.count, 1)
        // Only the sidebar: no result yet.
        XCTAssertFalse(ActionRules.resultShows([sidebar], name: "Divyekant", baseline: baseline))
        // The same text at a new place: a result row.
        XCTAssertTrue(ActionRules.resultShows([sidebar, ("Divyekant (you)", Frame(x: 400, y: 140, w: 500, h: 30))],
                                              name: "Divyekant", baseline: baseline))
        // A row for another person: no.
        XCTAssertFalse(ActionRules.resultShows([("Ravi Kumar", Frame(x: 400, y: 140, w: 500, h: 30))], name: "Divyekant", baseline: []))
        XCTAssertEqual(SwitcherTiming.resultMs, 800)
    }

    func testComposerShape() {
        let w = Frame(x: 0, y: 0, w: 1000, h: 800)
        XCTAssertTrue(ActionRules.composerShape(field: Frame(x: 300, y: 720, w: 650, h: 40), window: w))
        XCTAssertFalse(ActionRules.composerShape(field: Frame(x: 300, y: 20, w: 650, h: 30), window: w))   // top: a search field
        XCTAssertFalse(ActionRules.composerShape(field: Frame(x: 300, y: 720, w: 100, h: 40), window: w))  // narrow
        XCTAssertTrue(ActionRules.labelSaysComposer("message to #general"))
        XCTAssertTrue(ActionRules.labelSaysSearch("jump to…"))
    }

    // MARK: - Safety gates

    func testRiskyPressNeedsHoldRulesAndExactWords() {
        let hold = CommandInfo(mode: .hold, tier: .rules, spokenTarget: "send")
        XCTAssertNil(ActionRules.pressBlock(label: "Send", command: hold, sensitive: nil))
        XCTAssertNotNil(ActionRules.pressBlock(label: "Send", command: .unknown, sensitive: nil))
        XCTAssertNotNil(ActionRules.pressBlock(label: "Send", command: CommandInfo(mode: .alwaysOn, tier: .rules, spokenTarget: "send"), sensitive: nil))
        XCTAssertNotNil(ActionRules.pressBlock(label: "Send", command: CommandInfo(mode: .hold, tier: .jev, spokenTarget: "send"), sensitive: nil))
        XCTAssertNotNil(ActionRules.pressBlock(label: "Delete chat", command: CommandInfo(mode: .hold, tier: .rules, spokenTarget: "delete"), sensitive: nil))
        XCTAssertNil(ActionRules.pressBlock(label: "Insights", command: .unknown, sensitive: nil))
        // Any press on a sign-in page is blocked.
        XCTAssertNotNil(ActionRules.pressBlock(label: "Insights", command: hold, sensitive: "a password field"))
    }

    func testSendRule() {
        let hold = CommandInfo(mode: .hold, tier: .rules, spokenTarget: "send")
        XCTAssertNil(ActionRules.sendBlock(command: hold, inMessageBox: true, boxText: "on my way", sensitive: nil))
        XCTAssertNotNil(ActionRules.sendBlock(command: .unknown, inMessageBox: true, boxText: "on my way", sensitive: nil))
        XCTAssertNotNil(ActionRules.sendBlock(command: CommandInfo(mode: .alwaysOn, tier: .rules), inMessageBox: true, boxText: "x", sensitive: nil))
        XCTAssertNotNil(ActionRules.sendBlock(command: CommandInfo(mode: .hold, tier: .jev), inMessageBox: true, boxText: "x", sensitive: nil))
        XCTAssertNotNil(ActionRules.sendBlock(command: hold, inMessageBox: false, boxText: "x", sensitive: nil))
        XCTAssertNotNil(ActionRules.sendBlock(command: hold, inMessageBox: true, boxText: " ", sensitive: nil))
        XCTAssertNotNil(ActionRules.sendBlock(command: hold, inMessageBox: true, boxText: "x", sensitive: "the address has \"login\""))
    }

    func testTypeIntoRule() {
        XCTAssertNil(ActionRules.typeIntoBlock(role: "AXTextField", subrole: "AXSearchField", sensitive: nil))
        XCTAssertNotNil(ActionRules.typeIntoBlock(role: "AXTextField", subrole: "AXSecureTextField", sensitive: nil))
        XCTAssertNotNil(ActionRules.typeIntoBlock(role: "AXButton", subrole: "", sensitive: nil))
        XCTAssertNotNil(ActionRules.typeIntoBlock(role: "AXTextField", subrole: "", sensitive: "a password field"))
    }

    // MARK: - Elements and geometry

    func testKinds() {
        XCTAssertEqual(ActionRules.kind(role: "AXLink", subrole: ""), "link")
        XCTAssertEqual(ActionRules.kind(role: "AXPopUpButton", subrole: ""), "button")
        XCTAssertEqual(ActionRules.kind(role: "AXRadioButton", subrole: "AXTabButton"), "tab")
        XCTAssertEqual(ActionRules.kind(role: "AXRow", subrole: ""), "row")
        XCTAssertEqual(ActionRules.kind(role: ActionRules.ocrRole, subrole: ""), "text")
        XCTAssertNil(ActionRules.kind(role: "AXStaticText", subrole: ""))
        XCTAssertEqual(ActionRules.elementID(number: 3), "e3")
    }

    func testReadingOrder() {
        let a = Frame(x: 500, y: 100, w: 10, h: 10), b = Frame(x: 10, y: 103, w: 10, h: 10), c = Frame(x: 0, y: 200, w: 10, h: 10)
        let sorted = [c, a, b].sorted(by: ActionRules.readingOrder)
        XCTAssertEqual(sorted, [b, a, c])  // same 8-point row: left to right
    }

    func testBadgeOriginFlipsY() {
        // Main screen 1000 points high. An element at the top left of the main screen.
        let o = ActionRules.badgeOrigin(element: Frame(x: 10, y: 0, w: 50, h: 20), badge: CGSize(width: 26, height: 16),
                                        mainScreenHeight: 1000, screenOrigin: .zero)
        XCTAssertEqual(o, CGPoint(x: 10, y: 984))
        // A second screen to the right, with its own origin.
        let p = ActionRules.badgeOrigin(element: Frame(x: 1500, y: 100, w: 50, h: 20), badge: CGSize(width: 26, height: 16),
                                        mainScreenHeight: 1000, screenOrigin: CGPoint(x: 1440, y: 0))
        XCTAssertEqual(p, CGPoint(x: 60, y: 884))
    }

    func testOCRFrame() {
        let f = ActionRules.ocrFrame(box: CGRect(x: 0.5, y: 0.75, width: 0.25, height: 0.25), window: Frame(x: 100, y: 50, w: 800, h: 400))
        XCTAssertEqual(f, Frame(x: 500, y: 50, w: 200, h: 100))
    }

    func testScrollPlan() {
        XCTAssertEqual(ActionRules.scrollPlan(.down, web: true), .key(Keys.pageDown))
        XCTAssertEqual(ActionRules.scrollPlan(.top, web: true), .key(Keys.home))
        XCTAssertEqual(ActionRules.scrollPlan(.down, web: false), .wheel(lines: -12, times: 1))
        XCTAssertEqual(ActionRules.scrollPlan(.top, web: false), .wheel(lines: 100, times: 40))
    }

    func testCleanLabel() {
        XCTAssertEqual(ActionText.cleanLabel("Mail ravi@example.com now"), "Mail [email] now")
        XCTAssertEqual(ActionText.cleanLabel(String(repeating: "a", count: 150)).count, 100)
    }
}

/// Runs without the Accessibility permission: every intent fails safely, and nothing is pressed.
@MainActor
final class ActionRunnerTests: XCTestCase {
    func testRunnerRefusesUnapprovedApps() async throws {
        let runner = EarshotActionRunner(store: nil)
        let app = AppEntry(id: "x", name: "X", bundleID: "com.example.none", isChat: true, openChat: .switcher(keys: "cmd+k"))
        let out = await runner.run(.openChat(appID: "x", target: "Ravi", text: "hi"), context: RouteContext(apps: [app], names: []))
        XCTAssertFalse(out.ok)
    }

    /// A fake result list that shows the row after 45 ms. The wait must end soon after, not after a fixed sleep.
    func testResultWaitEndsWhenTheRowShows() async {
        let runner = EarshotActionRunner(store: nil)
        let t0 = Clock.nowNs()
        let row = ("Divyekant (you)", Frame(x: 400, y: 140, w: 500, h: 30))
        let shown = await runner.waitForResult(name: "Divyekant", baseline: []) {
            Clock.ms(since: t0) >= 45 ? [row] : []
        }
        let ms = Clock.ms(since: t0)
        print("EARSHOT_BENCH fake result wait: \(ms) ms (row at 45 ms)")
        XCTAssertTrue(shown)
        XCTAssertGreaterThanOrEqual(ms, 45)
        XCTAssertLessThan(ms, 150)
    }

    /// No row: the wait stops at its time limit and reports false, so earshot presses no Return.
    func testResultWaitTimesOut() async {
        let runner = EarshotActionRunner(store: nil)
        let t0 = Clock.nowNs()
        let shown = await runner.waitForResult(name: "Divyekant", baseline: [], timeoutMs: 100) { [] }
        XCTAssertFalse(shown)
        XCTAssertGreaterThanOrEqual(Clock.ms(since: t0), 100)
    }

    /// Read-only latency check: reads the front window 10 times and prints the times. It presses nothing.
    /// Run it with EARSHOT_READ_BENCH=1 on a Mac where the test process has the Accessibility permission.
    func testScreenReadLatency() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["EARSHOT_READ_BENCH"] == "1", "set EARSHOT_READ_BENCH=1")
        try XCTSkipUnless(AX.trusted(), "no Accessibility permission")
        let runner = EarshotActionRunner(options: { var o = ActionOptions(); o.ocrFallback = false; return o }(), store: nil)
        var times: [Double] = []
        var count = 0
        var bundle = ""
        for _ in 0..<10 {
            let t0 = Clock.nowNs()
            let s = await runner.screen()
            times.append(Clock.ms(since: t0))
            count = s?.elements.count ?? 0
            bundle = s?.bundleID ?? "none"
        }
        times.sort()
        print("EARSHOT_BENCH screen read: front \(bundle), \(count) elements, median \(times[5]) ms, max \(times[9]) ms")
        if ProcessInfo.processInfo.environment["EARSHOT_OCR_BENCH"] == "1", OCR.allowed(), let pid = AX.frontPid(),
           let w = AX.window(AX.appElement(pid)).flatMap({ AX.frame($0) }) {
            var ocr: [Double] = []
            var found = 0
            for _ in 0..<5 {
                let t0 = Clock.nowNs()
                found = await OCR.read(pid: pid, window: w).count
                ocr.append(Clock.ms(since: t0))
            }
            ocr.sort()
            print("EARSHOT_BENCH OCR: \(found) texts, median \(ocr[2]) ms, max \(ocr[4]) ms")
        }
    }
}
