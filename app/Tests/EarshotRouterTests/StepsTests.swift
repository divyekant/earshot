import EarshotCore
import XCTest
@testable import EarshotRouter

/// The cut of a chain of commands into steps (I-28). Made-up names only: the repository is public.
final class StepsTests: XCTestCase {
    func steps(_ s: String) -> [String] { CommandRouter.steps(s, context: Fixtures.context) }

    func testDksExample() {
        XCTAssertEqual(steps("click on this, click on that, type this and press send"),
                       ["click on this", "click on that", "type this and send"])
    }

    func testJoiners() {
        XCTAssertEqual(steps("open Notes and click new note, then type hello"), ["open Notes", "click new note", "type hello"])
        XCTAssertEqual(steps("go ahead and open Slack"), ["go ahead and open Slack"])
        XCTAssertEqual(steps("open Slack and go to alerts"), ["open Slack", "go to alerts"])
        XCTAssertEqual(steps("open Chrome then scroll down"), ["open Chrome", "scroll down"])
        XCTAssertEqual(steps("go back and scroll to the top"), ["go back", "scroll to the top"])
        XCTAssertEqual(steps("show numbers then click 5"), ["show numbers", "click 5"])
        XCTAssertEqual(steps("open Chrome. Scroll down."), ["open Chrome", "Scroll down"])
        XCTAssertEqual(steps("open Chrome and then also scroll down"), ["open Chrome", "scroll down"])
        XCTAssertEqual(steps("open Chrome, after that scroll down"), ["open Chrome", "scroll down"])
    }

    func testOneCommandStaysWhole() {
        for s in ["open Slack", "click Terms and Conditions", "type see you soon and send", "the blue fox jumps and send",
                  "Yeah, actually let's send", "message Felix I am late and then I will call",
                  "type I will open it and then close it", "click steer this thread and type hi there",
                  "focus on steer this thread then type hi there", "Slack Ravi, call me later", "open Find and Replace"] {
            XCTAssertEqual(steps(s), [s], s)
        }
    }

    func testTextEndsOnlyAtAStrongJoiner() {
        XCTAssertEqual(steps("type hello, click send"), ["type hello and send"])
        XCTAssertEqual(steps("type see you soon, send it"), ["type see you soon and send"])
        XCTAssertEqual(steps("type hello and open Notes"), ["type hello and open Notes"])
        XCTAssertEqual(steps("type hello and then open Notes"), ["type hello", "open Notes"])
        XCTAssertEqual(steps("type hello. Open Notes."), ["type hello", "Open Notes"])
    }

    func testSendAtTheEnd() {
        XCTAssertEqual(steps("click the reply box, type thanks and send it"), ["click the reply box", "type thanks and send"])
        XCTAssertEqual(steps("open Messages and send"), ["open Messages", "send"])
        XCTAssertEqual(steps("message Felix see you and send"), ["message Felix see you and send"])
    }

    func testSharedOpenVerb() {
        XCTAssertEqual(steps("open Notes and Calendar"), ["open Notes", "open Calendar"])
        XCTAssertEqual(steps("open Notes and Notes"), ["open Notes and Notes"])
    }

    func testLeadingTalkIsDropped() {
        XCTAssertEqual(steps("Not a useful feature. Click on notes and scroll down"), ["Click on notes", "scroll down"])
    }

    // MARK: - Lead words (I-29, activity records 2026-11-03)

    func testLeadWords() async {
        let router = CommandRouter()
        for s in ["Here at least open Slack.", "I want to open Slack", "go ahead and open Slack"] {
            let r = await router.route(s, context: Fixtures.context)
            XCTAssertEqual(r.intent, .openApp(appID: "slack"), s + ": " + r.why)
            XCTAssertGreaterThanOrEqual(r.confidence, SafetyPolicy.minimumConfidence, s)
            XCTAssertTrue(CommandRouter.hasCommandWord(s, context: Fixtures.context), s)
        }
        let typed = await router.route("Here, at least, type.", context: Fixtures.context)
        XCTAssertTrue(typed.awaitsText, typed.why)
        // "I message" is still the app iMessage (PR #24).
        let chat = await router.route("I message Felix", context: Fixtures.context)
        if case .openChat(let app, _, _) = chat.intent { XCTAssertEqual(app, "messages") } else { XCTFail(chat.why) }
    }

    // Live test, 2026-11-03: the common word "all" matched the channel "all-team" by its first part.
    func testOneCommonWordDoesNotMatchAChannelByItsFirstPart() async {
        var context = Fixtures.context
        context.names.append(NameEntry(appID: "slack", name: "all-team", source: .sidebar))
        let r = await CommandRouter().route("Just do all the items, not just this", context: context)
        if case .openChat(_, let target, _) = r.intent { XCTAssertNotEqual(target, "all-team", r.why) }
        let named = await CommandRouter().route("message all-team on Slack", context: context)
        if case .openChat(_, let target, _) = named.intent { XCTAssertEqual(target, "all-team") } else { XCTFail(named.why) }
    }

    func testStepsLatency() {
        let s = "click on this, click on that, open Notes and Calendar, type this and press send"
        var ms: [Double] = []
        for _ in 0..<50 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = steps(s)
            ms.append(Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000)
        }
        let median = ms.sorted()[ms.count / 2]
        print(String(format: "LATENCY steps cut: median %.3f ms, max %.3f ms", median, ms.max()!))
        XCTAssertLessThan(median, 5)
    }
}
