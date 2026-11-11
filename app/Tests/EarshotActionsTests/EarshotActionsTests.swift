import AppKit
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

    /// A fake browser window: a tab strip, a toolbar, and a web page with many links.
    private final class Node {
        let role: String, subrole: String, title: String
        var children: [Node]
        init(_ role: String, _ subrole: String = "", _ title: String = "", _ children: [Node] = []) {
            self.role = role; self.subrole = subrole; self.title = title; self.children = children
        }
    }

    func testWindowControlsSkipTheWebPage() {
        let page = Node("AXWebArea", "", "", (0..<500).map { Node("AXLink", "", "link \($0)") })
        let window = Node("AXWindow", "", "", [
            Node("AXGroup", "", "", [
                Node("AXTabGroup", "", "", [Node("AXRadioButton", "AXTabButton", "shadcn/ui"),
                                            Node("AXRadioButton", "AXTabButton", "FPL Guru"),
                                            Node("AXButton", "", "New Tab")]),
                Node("AXToolbar", "", "", [Node("AXButton", "", "Back"), Node("AXButton", "", "Reload"),
                                           Node("AXTextField", "", "Address and search bar")]),
            ]),
            Node("AXGroup", "", "", [page]),
            Node("AXMenuBar", "", "", [Node("AXMenuItem", "", "File")]),
        ])
        let t0 = Clock.nowNs()
        let found = ScreenReader.controlWalk(window, role: { $0.role }, subrole: { $0.subrole }, children: { $0.children })
        let ms = Clock.ms(since: t0)
        XCTAssertEqual(found.map(\.title), ["shadcn/ui", "FPL Guru", "New Tab", "Back", "Reload", "Address and search bar"])
        XCTAssertEqual(found.compactMap { ActionRules.kind(role: $0.role, subrole: $0.subrole) }, ["tab", "tab", "button", "button", "button", "field"])
        XCTAssertLessThan(ms, 25)
    }

    func testPageRulesForWindowControls() {
        XCTAssertFalse(ActionRules.pageRulesApply(kind: "tab", inPage: false))   // a browser tab: no page rules
        XCTAssertTrue(ActionRules.pageRulesApply(kind: "button", inPage: false)) // Reload on a payment page: blocked
        XCTAssertTrue(ActionRules.pageRulesApply(kind: "tab", inPage: true))     // a tab inside the page
    }

    func testSkipLinksHaveNoVisiblePoint() {
        let vp = Frame(x: 0, y: 80, w: 1200, h: 800)
        XCTAssertFalse(ActionRules.visible(Frame(x: 0, y: 80, w: 1, h: 1), in: vp))           // a 1x1 skip link
        XCTAssertFalse(ActionRules.visible(Frame(x: 0, y: 0, w: 0, h: 0), in: vp))            // an empty frame
        XCTAssertFalse(ActionRules.visible(Frame(x: -10000, y: -10000, w: 150, h: 20), in: vp)) // off screen
        XCTAssertTrue(ActionRules.visible(Frame(x: 10, y: 870, w: 150, h: 20), in: vp))       // partly visible: kept
    }

    func testInsideAndHostAfterScroll() {
        let v = Frame(x: 0, y: 100, w: 1200, h: 700)
        XCTAssertTrue(ActionRules.inside(Frame(x: 20, y: 400, w: 200, h: 20), v))
        XCTAssertFalse(ActionRules.inside(Frame(x: 20, y: 1400, w: 200, h: 20), v))   // below the view
        XCTAssertFalse(ActionRules.inside(Frame(x: 20, y: 790, w: 200, h: 20), v))    // cut at the bottom
        XCTAssertNil(ActionRules.afterScrollBlock(before: "https://x.com/home", after: "https://x.com/home#top"))
        XCTAssertNotNil(ActionRules.afterScrollBlock(before: "https://x.com/home", after: "https://accounts.example.com/"))
        XCTAssertNotNil(ActionRules.afterScrollBlock(before: "https://x.com/home", after: nil))
        XCTAssertNil(ActionRules.afterScrollBlock(before: nil, after: nil))  // a native window
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
        // A browser tab title with its hover note (live test, 2026-11-03).
        XCTAssertEqual(ActionText.cleanLabel("(1) Home / X - Memory usage - 547 MB"), "(1) Home / X")
        XCTAssertEqual(ActionText.cleanLabel("Docs - Memory usage - 1.2 GB"), "Docs")
        XCTAssertEqual(ActionText.cleanLabel("Memory usage report"), "Memory usage report")
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

    /// A fake app for the switcher field wait. The element type is a string.
    private final class FakeSwitcher {
        let t0 = Clock.nowNs()
        var fieldShowsAtMs: Double
        var takesFocusOnItsOwn: Bool
        var acceptsAXFocus: Bool
        var focusedField = false
        var focusSets = 0
        init(showsAt: Double, ownFocus: Bool, acceptsAX: Bool) { fieldShowsAtMs = showsAt; takesFocusOnItsOwn = ownFocus; acceptsAXFocus = acceptsAX }
        var shown: Bool { Clock.ms(since: t0) >= fieldShowsAtMs }
        /// The number of focus checks after the field showed.
        var pollsAfterShown = 0
        /// The number of focus checks after the first set-focus call.
        var pollsAfterSet = 0
        /// The number of scans that found the field.
        var scansFound = 0
        func focused() -> (String?, Bool, Bool) {
            if shown { pollsAfterShown += 1 }
            if focusSets > 0 { pollsAfterSet += 1 }
            if shown && (takesFocusOnItsOwn || focusedField) { return ("to-field", true, false) }
            return ("message-box", false, true)  // the focus stays in the message box of the open chat
        }
        func newField() -> String? {
            guard shown else { return nil }
            scansFound += 1
            return "to-field"
        }
        func setFocus(_ f: String) { focusSets += 1; if acceptsAXFocus { focusedField = true } }
        var clicks = 0
        /// A click gives the focus, also in an app that ignores AXFocused (WhatsApp).
        func click(_ f: String) { clicks += 1; focusedField = true }
    }

    /// WhatsApp: the new-chat field shows but ignores AXFocused. earshot clicks it one time at the next scan.
    func testFieldThatIgnoresAXFocusGetsOneClick() async {
        let runner = EarshotActionRunner(store: nil)
        let fake = FakeSwitcher(showsAt: 0, ownFocus: false, acceptsAX: false)
        let (field, why, stats) = await runner.waitForSwitcherField(scanDelayMs: 0, focused: fake.focused, newField: fake.newField,
                                                                   setFocus: fake.setFocus, click: fake.click)
        XCTAssertEqual(field, "to-field")
        XCTAssertNil(why)
        XCTAssertEqual(fake.focusSets, 1)
        XCTAssertEqual(fake.clicks, 1)
        XCTAssertTrue(stats.clicked)
        XCTAssertLessThan(Clock.ms(since: fake.t0), Double(3 * SwitcherTiming.scanMs) + 200)
    }

    /// Slack (2026) Cmd-K: query rows hold the typed name. They are not results, and Return on them runs a search.
    func testQueryRowsAreNotChatResults() {
        let name = "Sam Rivera"
        func t(_ s: String, _ y: Double, _ h: Double = 20) -> (String, Frame) { (s, Frame(x: 400, y: y, w: 500, h: h)) }
        let searchOnly = [t("Search for: Sam Rivera", 131, 40), t("Show results for:", 141), t("Sam Rivera", 141),
                          t("Ask Slackbot about Sam Rivera", 171, 40), t("Ask Slackbot:", 181), t("Sam Rivera", 181)]
        XCTAssertEqual(ActionRules.switcherResult(searchOnly, name: name, baseline: []), .none)
        XCTAssertFalse(ActionRules.resultShows(searchOnly, name: name, baseline: []))
        // The chat row first: Return opens the chat.
        let chatFirst = [t("Suggestions", 131, 132), t("Sam Rivera, Direct Message", 131, 40), t("Sam Rivera", 141), t("(you)", 141)]
            + searchOnly.map { ($0.0, Frame(x: 400, y: $0.1.y + 40, w: 500, h: $0.1.h)) }
        XCTAssertEqual(ActionRules.switcherResult(chatFirst, name: name, baseline: []), .chat)
        // The chat row below a search row: Return would run the search.
        let chatBelow = searchOnly + [t("Sam Rivera, Direct Message", 211, 40), t("Sam Rivera", 221)]
        XCTAssertEqual(ActionRules.switcherResult(chatBelow, name: name, baseline: []), .searchFirst)
    }

    /// WhatsApp: Return does not open the result. earshot presses the top new row that matches the name.
    func testPickResultRow() {
        let old = ("Sam Rivera", Frame(x: 350, y: 537, w: 380, h: 37))
        let baseline = ActionRules.matchKeys([old], name: "Sam Rivera")
        let rows: [(label: String, frame: Frame)] = [
            ("New group", Frame(x: 350, y: 357, w: 380, h: 37)),
            ("Search for: Sam Rivera", Frame(x: 350, y: 300, w: 380, h: 37)),
            old,
            ("Sam Rivera", Frame(x: 350, y: 381, w: 380, h: 37)),
        ]
        XCTAssertEqual(ActionRules.pickResultRow(rows, name: "Sam Rivera", baseline: baseline), 3)
        XCTAssertNil(ActionRules.pickResultRow([old], name: "Sam Rivera", baseline: baseline))
        XCTAssertNil(ActionRules.pickResultRow([("Delete chat Sam Rivera", Frame(x: 350, y: 381, w: 380, h: 37))],
                                               name: "Sam Rivera", baseline: []))
    }

    func testRowsGroupTextsOfOneRow() {
        let rows = ActionRules.rows([("b", Frame(x: 0, y: 141, w: 10, h: 20)), ("a", Frame(x: 0, y: 131, w: 10, h: 40)),
                                     ("c", Frame(x: 0, y: 171, w: 10, h: 40))])
        XCTAssertEqual(rows.map { $0.map(\.0) }, [["a", "b"], ["c"]])
        // A section label that covers the rows does not join them (Slack "Suggestions").
        let withSection = ActionRules.rows([("Suggestions", Frame(x: 0, y: 131, w: 10, h: 132)), ("a", Frame(x: 0, y: 131, w: 10, h: 40)),
                                            ("b", Frame(x: 0, y: 141, w: 10, h: 20)), ("c", Frame(x: 0, y: 171, w: 10, h: 40)),
                                            ("d", Frame(x: 0, y: 211, w: 10, h: 40))])
        XCTAssertEqual(withSection.map { $0.map(\.0) }, [["a", "b"], ["c"], ["d"]])
    }

    func testSwitcherFieldShowsLate() async {
        let runner = EarshotActionRunner(store: nil)
        let fake = FakeSwitcher(showsAt: 600, ownFocus: true, acceptsAX: false)  // E0: "To:" after about 600 ms
        let (field, why, _) = await runner.waitForSwitcherField(focused: fake.focused, newField: fake.newField, setFocus: fake.setFocus)
        XCTAssertEqual(field, "to-field")
        XCTAssertNil(why)
        XCTAssertLessThan(Clock.ms(since: fake.t0), 750)
    }

    func testSwitcherFieldWithoutFocusGetsAXFocus() async {
        let runner = EarshotActionRunner(store: nil)
        let fake = FakeSwitcher(showsAt: 200, ownFocus: false, acceptsAX: true)
        let (field, _, stats) = await runner.waitForSwitcherField(scanDelayMs: 0, focused: fake.focused, newField: fake.newField, setFocus: fake.setFocus)
        let ms = Clock.ms(since: fake.t0)
        print("EARSHOT_BENCH fake switcher AX focus: \(ms) ms (field at 200 ms), \(stats.polls) polls")
        XCTAssertEqual(field, "to-field")
        XCTAssertTrue(stats.setFocus)
        // The behaviour: the first scan that finds the field sets the focus once.
        XCTAssertEqual(fake.scansFound, 1)
        XCTAssertEqual(fake.focusSets, 1)
        // The focus check right after the set ends the wait. No sleep, no second set.
        XCTAssertEqual(fake.pollsAfterSet, 1)
        // The field showed, then at most one scan interval of polls ran before the scan found it.
        XCTAssertLessThanOrEqual(fake.pollsAfterShown, 2 + SwitcherTiming.scanMs / SwitcherTiming.pollMs)
        // A wall-time bound with margin for a busy CI runner. The checks above carry the exact behaviour.
        XCTAssertLessThan(ms, 200 + Double(SwitcherTiming.scanMs) + 200)
    }

    func testFocusStaysInMessageBoxTypesNothing() async {
        let runner = EarshotActionRunner(store: nil)
        // No switcher field ever shows: the focus stays in the message box.
        let fake = FakeSwitcher(showsAt: .infinity, ownFocus: false, acceptsAX: false)
        let (field, why, _) = await runner.waitForSwitcherField(timeoutMs: 200, focused: fake.focused, newField: fake.newField, setFocus: fake.setFocus)
        XCTAssertNil(field)
        XCTAssertEqual(why?.contains("message box"), true)
        // The field shows but refuses the focus: still nothing.
        let stuck = FakeSwitcher(showsAt: 0, ownFocus: false, acceptsAX: false)
        let (f2, why2, _) = await runner.waitForSwitcherField(timeoutMs: 200, focused: stuck.focused, newField: stuck.newField, setFocus: stuck.setFocus)
        XCTAssertNil(f2)
        XCTAssertEqual(why2?.contains("did not take the focus"), true)
    }

    /// Slack Cmd-K: the field takes the focus by itself. The wait must end one poll after it, with no scan.
    func testOwnFocusFieldEndsWithinOnePoll() async {
        let runner = EarshotActionRunner(store: nil)
        let fake = FakeSwitcher(showsAt: 100, ownFocus: true, acceptsAX: false)
        var scans = 0
        let (field, _, stats) = await runner.waitForSwitcherField(focused: fake.focused, newField: { scans += 1; return nil },
                                                                 setFocus: fake.setFocus)
        let ms = Clock.ms(since: fake.t0)
        print("EARSHOT_BENCH fake switcher field: \(ms) ms (field at 100 ms), \(stats.polls) polls")
        XCTAssertEqual(field, "to-field")
        // The behaviour: the first focus check after the field shows ends the wait. No later poll, no sleep in between.
        XCTAssertEqual(fake.pollsAfterShown, 1)
        // No scan: a scan runs only after scanDelayMs (150 ms), so the wait also ended before that.
        XCTAssertEqual(scans, 0)
        XCTAssertFalse(stats.setFocus)
        // A wall-time bound with margin for a busy CI runner. The two checks above carry the exact behaviour.
        XCTAssertLessThan(ms, Double(SwitcherTiming.scanDelayMs) + 100)
    }

    /// An app without a learned behaviour scans only after scanDelayMs; an app learned as "set" scans at once.
    func testScanDelay() async {
        let runner = EarshotActionRunner(store: nil)
        let late = FakeSwitcher(showsAt: 0, ownFocus: false, acceptsAX: true)
        _ = await runner.waitForSwitcherField(focused: late.focused, newField: late.newField, setFocus: late.setFocus)
        XCTAssertGreaterThanOrEqual(Clock.ms(since: late.t0), Double(SwitcherTiming.scanDelayMs))
        let learned = FakeSwitcher(showsAt: 0, ownFocus: false, acceptsAX: true)
        _ = await runner.waitForSwitcherField(scanDelayMs: 0, focused: learned.focused, newField: learned.newField, setFocus: learned.setFocus)
        XCTAssertLessThan(Clock.ms(since: learned.t0), 60)
    }

    /// A fake link below the view. The scroll moves it into view after 60 ms. The wait ends soon after.
    func testScrollIntoViewWaitsForTheFrame() async {
        let runner = EarshotActionRunner(store: nil)
        let view = Frame(x: 0, y: 100, w: 1200, h: 700)
        var scrolledAt: UInt64?
        var readsAfterMove = 0  // frame reads after the frame moved into view
        var seenAt: UInt64?     // the time of the read that saw the frame in view
        let t0 = Clock.nowNs()
        let f = await runner.scrollIntoView(perform: { scrolledAt = Clock.nowNs() }, frame: {
            guard let s = scrolledAt, Clock.ms(since: s) >= 60 else { return Frame(x: 20, y: 1400, w: 200, h: 20) }
            readsAfterMove += 1
            seenAt = Clock.nowNs()
            return Frame(x: 20, y: 400, w: 200, h: 20)
        }, view: view)
        let ms = Clock.ms(since: t0)
        let afterSeen = seenAt.map { Clock.ms(since: $0) } ?? .infinity
        print("EARSHOT_BENCH fake scroll into view: \(ms) ms (frame moves at 60 ms), \(afterSeen) ms after the read that saw it")
        XCTAssertEqual(f, Frame(x: 20, y: 400, w: 200, h: 20))
        // The behaviour: the first frame read after the move ends the wait. No later read.
        XCTAssertEqual(readsAfterMove, 1)
        // The wait reads the frame at the poll interval, so it sees the move within one poll.
        XCTAssertLessThanOrEqual(SwitcherTiming.pollMs, 20)
        // No sleep after the read that saw the frame: the wait returns at once.
        XCTAssertLessThan(afterSeen, 30)
        // The wait ended on the move, before the time-out. A tighter wall bound (60 + 100 ms) failed on the GitHub
        // macOS runner (161.6 ms and 180.9 ms), because short sleeps overshoot there. The checks above carry the
        // exact behaviour, and they do not depend on the runner's sleep time.
        XCTAssertLessThan(ms, Double(ScrollTiming.limitMs))
    }

    /// The frame never comes into view: nil at the time limit, so earshot does not click.
    func testScrollIntoViewTimesOut() async {
        let runner = EarshotActionRunner(store: nil)
        let t0 = Clock.nowNs()
        let f = await runner.scrollIntoView(perform: {}, frame: { Frame(x: 20, y: 1400, w: 200, h: 20) },
                                            view: Frame(x: 0, y: 100, w: 1200, h: 700))
        XCTAssertNil(f)
        XCTAssertGreaterThanOrEqual(Clock.ms(since: t0), Double(ScrollTiming.limitMs))
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
        // Read one app that is not in front, by bundle id, for example a browser: EARSHOT_READ_BUNDLE=com.google.Chrome.
        // It reads only. The window controls walk is timed on its own, so the cost of the new targets shows.
        if let id = ProcessInfo.processInfo.environment["EARSHOT_READ_BUNDLE"],
           let pid = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.processIdentifier {
            var total: [Double] = [], walk: [Double] = []
            var n = 0, tabs = 0, inPage = 0
            for _ in 0..<10 {
                guard let r = ScreenReader.read(pid: pid, maxElements: 400) else { continue }
                total.append(r.ms)
                n = r.snapshot.elements.count
                inPage = r.items.values.filter(\.inPage).count
                tabs = r.items.values.filter { !$0.inPage && $0.kind == "tab" }.count
                if let w = AX.window(AX.appElement(pid)) {
                    let t0 = Clock.nowNs()
                    _ = ScreenReader.windowControls(w)
                    walk.append(Clock.ms(since: t0))
                }
            }
            total.sort(); walk.sort()
            if !total.isEmpty, !walk.isEmpty {
                print("EARSHOT_BENCH \(id) read: \(n) elements (\(inPage) in the page, \(tabs) window tabs), median \(total[total.count / 2]) ms, max \(total.last!) ms; window controls walk median \(walk[walk.count / 2]) ms")
            }
        }
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

/// The always-on "send" alone after typing (D-12, R-ON-5). Return is pressed only by ActionRunner.send, which asks
/// sendBlock first. Made-up text only.
final class OwnerSendRuleTests: XCTestCase {
    func testOnlyTheSendPathPressesReturn() {
        // Return is pressed only by ActionRunner.send, which asks sendBlock first.
        let info = { (owner: Bool) in CommandInfo(mode: .alwaysOn, tier: .rules, spokenTarget: "send", ownerSendAfterTyping: owner) }
        XCTAssertEqual(ActionRules.sendBlock(command: info(false), inMessageBox: true, boxText: "made up", sensitive: nil),
                       "blocked: send needs the hold key")
        XCTAssertNil(ActionRules.sendBlock(command: info(true), inMessageBox: true, boxText: "made up", sensitive: nil))
        XCTAssertNotNil(ActionRules.sendBlock(command: info(true), inMessageBox: false, boxText: "made up", sensitive: nil))
        XCTAssertNotNil(ActionRules.sendBlock(command: info(true), inMessageBox: true, boxText: "", sensitive: nil))
        XCTAssertNotNil(ActionRules.sendBlock(command: info(true), inMessageBox: true, boxText: "made up", sensitive: "a password field"))
        var jev = info(true); jev.tier = .jev
        XCTAssertNotNil(ActionRules.sendBlock(command: jev, inMessageBox: true, boxText: "made up", sensitive: nil))
    }
}
