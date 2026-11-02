import EarshotCore
import Foundation
import XCTest
@testable import EarshotRouter

/// A tier-2 chooser for tests. It records each call.
final class FakeChooser: Tier2Chooser, @unchecked Sendable {
    var calls: [[String]] = []
    let delayMs: Int
    let pick: ([String]) -> Int?

    init(delayMs: Int = 0, pick: @escaping ([String]) -> Int?) {
        self.delayMs = delayMs
        self.pick = pick
    }

    func choose(_ text: String, options: [String], budgetMs: Int) async -> Int? {
        calls.append(options)
        if delayMs > 0 { try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000) }
        return pick(options)
    }
}

final class EarshotRouterTests: XCTestCase {
    let router = CommandRouter()

    func route(_ text: String, _ context: RouteContext = Fixtures.context, router: CommandRouter? = nil) async -> RouteResult {
        await (router ?? self.router).route(text, context: context)
    }

    func chat(_ app: String, _ target: String, _ text: String? = nil) -> Intent {
        .openChat(appID: app, target: target, text: text)
    }

    func expect(_ words: String, _ intent: Intent, sure: Bool = true, _ context: RouteContext = Fixtures.context,
                file: StaticString = #filePath, line: UInt = #line) async {
        let r = await route(words, context)
        XCTAssertEqual(r.intent, intent, "\"\(words)\": \(r.why)", file: file, line: line)
        if sure {
            XCTAssertGreaterThanOrEqual(r.confidence, SafetyPolicy.minimumConfidence, "\"\(words)\" is not sure: \(r.why)",
                                        file: file, line: line)
        }
    }

    // MARK: - E1 command kinds (E1, section 3)

    func testE1FullNames() async {
        await expect("message Prakash Iyer on Slack", chat("slack", "Prakash Iyer"))
        await expect("open my chat with Felix in Messages", chat("messages", "Felix"))
        await expect("go to Udita on Messages", chat("messages", "Udita"))
    }

    func testE1AppFirstAndFirstNameOnly() async {
        await expect("Slack Prakash", chat("slack", "Prakash Iyer"))
        await expect("message Felix", chat("messages", "Felix"))
        await expect("ping Udita", chat("messages", "Udita"))
    }

    func testE1Misheard() async {
        await expect("message prakush on Slack", chat("slack", "Prakash Iyer"))
        await expect("message Feliks on Messages", chat("messages", "Felix"))
    }

    func testE1WithText() async {
        await expect("tell Ravi on Slack that I will be ten minutes late", chat("slack", "Ravi Kumar", "I will be ten minutes late"))
        await expect("Slack Ravi, can we move the call to four", chat("slack", "Ravi Kumar", "can we move the call to four"))
        // The text keeps case and punctuation, and a possessive in the text stays.
        await expect("Slack Ravi, It's done. Can we ship?", chat("slack", "Ravi Kumar", "It's done. Can we ship?"))
        await expect("Slack Ravi running late", chat("slack", "Ravi Kumar", "running late"))
        await expect("tell Ravi that Slack is down", chat("slack", "Ravi Kumar", "Slack is down"))
    }

    func testE1Self() async {
        await expect("message me on Slack", chat("slack", "Owner (you)"))
        await expect("Messages me, buy milk", chat("messages", "Owner", "buy milk"))
        await expect("open my own chat in Slack", chat("slack", "Owner (you)"))
    }

    // MARK: - No comma (live test: speech to text often drops it)

    func testSelfWithNoComma() async {
        await expect("Slack me running late.", chat("slack", "Owner (you)", "running late"))
        await expect("iMessage me sounds good", chat("messages", "Owner", "sounds good"))
        // No app named: the front chat app decides between the two own chats.
        let front = RouteContext(apps: Fixtures.apps, names: Fixtures.names, frontBundleID: "com.apple.MobileSMS")
        await expect("message myself buy milk", chat("messages", "Owner", "buy milk"), front)
        // No front app: the verb "message" leans to the app "Messages".
        await expect("message myself buy milk", chat("messages", "Owner", "buy milk"))
        // A verb that names no app leaves two own chats: unsure.
        let noFront = await route("ping myself buy milk")
        XCTAssertLessThan(noFront.confidence, SafetyPolicy.minimumConfidence, "two own chats, no hint: \(noFront.why)")
        await expect("text me on Slack", chat("slack", "Owner (you)"))
        await expect("ping myself on Slack call the bank", chat("slack", "Owner (you)", "call the bank"))
        await expect("open my own chat in Slack", chat("slack", "Owner (you)"))
        await expect("Slack my own chat pick up the parcel", chat("slack", "Owner (you)", "pick up the parcel"))
        for s in ["Slack me running late", "message myself buy milk", "Slack me, running late"] {
            XCTAssertNil(CommandRouter.heardName(s, context: Fixtures.context), s)
        }
    }

    func testSelfWithComma() async {
        await expect("Slack me, running late", chat("slack", "Owner (you)", "running late"))
        await expect("Messages myself, buy milk", chat("messages", "Owner", "buy milk"))
    }

    func testKnownNameWithNoComma() async {
        await expect("Slack Prakash running late", chat("slack", "Prakash Iyer", "running late"))
        await expect("Slack Prakash Iyer running late", chat("slack", "Prakash Iyer", "running late"))
        await expect("message Felix see you at 6", chat("messages", "Felix", "see you at 6"))
        await expect("Slack Prakash, running late", chat("slack", "Prakash Iyer", "running late"))
        XCTAssertNil(CommandRouter.heardName("Slack Prakash running late", context: Fixtures.context))
    }

    func testUnknownNameWithNoComma() async {
        let r = await route("Slack Ishaan running late")
        XCTAssertTrue(r.intent == .none || r.intent == .openApp(appID: "slack"), "\(r.intent)")
        // The end of an unknown name is not known: search for the first word only.
        let heard = CommandRouter.heardName("Slack Ishaan running late", context: Fixtures.context)
        XCTAssertEqual(heard?.name, "Ishaan")
        XCTAssertEqual(heard?.appID, "slack")
        // With a comma, the whole name part goes to the search.
        XCTAssertEqual(CommandRouter.heardName("message Ingrid Vasquez, running late", context: Fixtures.context)?.name,
                       "Ingrid Vasquez")
        // After the search adds the name, the next route takes the rest as the text.
        let ctx = RouteContext(apps: Fixtures.apps,
                               names: Fixtures.names + [NameEntry(appID: "slack", name: "Ishaan Verma", source: .search)])
        await expect("Slack Ishaan running late", chat("slack", "Ishaan Verma", "running late"), ctx)
    }

    // MARK: - App names split by speech to text (live: "iMessage me, sounds good" gave "I message me sounds good")

    func testSplitAppNamesJoin() async {
        await expect("I message me sounds good", chat("messages", "Owner", "sounds good"))
        await expect("i message me, sounds good", chat("messages", "Owner", "sounds good"))
        await expect("whats app me call mum", chat("whatsapp", "Owner (You)", "call mum"))
        await expect("text Udita on i message", chat("messages", "Udita"))
        await expect("open chat GPT", .openApp(appID: "chatgpt"))
    }

    func testNoJoinWhenWordsDoNotMakeAnApp() async {
        // A word that alone is an app name is never part of a join.
        await expect("open notes app", .openApp(appID: "notes"))
        // "chat" alone is a stop word, not an app: "chat with Mrunal" opens Mrunal.
        await expect("chat with Mrunal", chat("messages", "Mrunal"))
    }

    func testChatVerbLeansToTheAppWithThatName() async {
        await expect("message me sounds good", chat("messages", "Owner", "sounds good"))
        // An app that the owner names always wins.
        await expect("message me on Slack hi", chat("slack", "Owner (you)", "hi"))
        await expect("Slack me sounds good", chat("slack", "Owner (you)", "sounds good"))
        // A known name that only one app has wins.
        await expect("message Prakash", chat("slack", "Prakash Iyer"))
    }

    // MARK: - Hesitation words (live: "Uh slack me running tomorrow." was "no command word")

    func testHesitationWordsAreDropped() async {
        await expect("Uh slack me running late.", chat("slack", "Owner (you)", "running late"))
        await expect("um, Slack me running late", chat("slack", "Owner (you)", "running late"))
        await expect("okay message me sounds good", chat("messages", "Owner", "sounds good"))
        await expect("so message Felix", chat("messages", "Felix"))
        await expect("erm click new", .click(elementID: "e2"), news)
        await expect("um open hn.com", .openURL("https://hn.com"))
        await expect("uh, okay open hn.com", .openURL("https://hn.com"))
        let so = await route("so what")
        XCTAssertEqual(so.intent, .none)
        XCTAssertEqual(so.why, "no command word or app name")
    }

    func testE1OpenApp() async {
        await expect("switch to Slack", .openApp(appID: "slack"))
        await expect("open Notes", .openApp(appID: "notes"))
        await expect("open Lock Screen", .openApp(appID: "lockscreen"))
        // Speech to text splits a one-word name (E2).
        await expect("open Tiger VNC", .openApp(appID: "tigervnc"))
    }

    func testE1SpokenAppName() async {
        await expect("text Udita on iMessage", chat("messages", "Udita"))
    }

    func testE1FreePhrasings() async {
        await expect("can you pull up Felix on Messages", chat("messages", "Felix"))
        await expect("Felix on Messages", chat("messages", "Felix"))
        await expect("I need to talk to Ravi on Slack", chat("slack", "Ravi Kumar"))
        await expect("reply to Udita", chat("messages", "Udita"))
        await expect("DM Ravi on Slack", chat("slack", "Ravi Kumar"))
        await expect("open Slack and go to Ravi", chat("slack", "Ravi Kumar"))
        await expect("let's write to Felix", chat("messages", "Felix"))
        await expect("Slack, Ravi", chat("slack", "Ravi Kumar"))
        await expect("switch over to my chat with Mrunal", chat("messages", "Mrunal"))
    }

    func testE1NoCommandIsNone() async {
        for s in ["I think the meeting moved to Thursday", "running late, be there in ten minutes",
                  "the build passed on the second try", "what is the weather like today",
                  "remind me to call the bank tomorrow", "can you summarise this page"] {
            let r = await route(s)
            XCTAssertEqual(r.intent, .none, "\"\(s)\": \(r.why)")
        }
    }

    func testE1UnknownNames() async {
        // Doing nothing is correct. Opening only the app is also safe.
        let r = await route("message Ishaan on Slack")
        XCTAssertTrue(r.intent == .none || r.intent == .openApp(appID: "slack"), "\(r.intent)")
        for s in ["ping Thembeka", "ping Okonkwo", "message Ingrid Vasquez"] {
            let r = await route(s)
            XCTAssertEqual(r.intent, .none, "\"\(s)\": \(r.why)")
        }
        let heard = CommandRouter.heardName("message Ishaan on Slack", context: Fixtures.context)
        XCTAssertEqual(heard?.name, "Ishaan")
        XCTAssertEqual(heard?.appID, "slack")
    }

    func testNoAppThatIsNotApproved() async {
        let r = await route("message Zed on Discord")
        if case .openChat(let app, _, _) = r.intent { XCTAssertNotEqual(app, "discord") }
        XCTAssertNotEqual(r.intent, .openApp(appID: "discord"))
    }

    func testUnsureNameAsksForNothingWithoutTier2() async {
        // "get me Felix's chat" has no command word: the rules are unsure, and tier 2 is off.
        let r = await route("get me Felix's chat")
        XCTAssertEqual(r.intent, .none)
        XCTAssertLessThan(r.confidence, SafetyPolicy.minimumConfidence)
    }

    // MARK: - Names by sound (E2, section 7, item 5)

    func testSoundCodes() {
        XCTAssertEqual(SoundCode.code("udita"), SoundCode.code("aditty"))
        XCTAssertEqual(SoundCode.code("claude"), SoundCode.code("clawed"))
        XCTAssertEqual(SoundCode.code("manel"), SoundCode.code("manal"))
        XCTAssertEqual(SoundCode.similarity("today", "udita"), 0, "the first sound must be the same")
        XCTAssertGreaterThanOrEqual(SoundCode.similarity("marinel", "mrunal"), 0.8)
        XCTAssertGreaterThanOrEqual(SoundCode.similarity("manal", "mrunal"), 0.8)
    }

    func testADittyIsUdita() async {
        await expect("message a ditty", chat("messages", "Udita"))
        await expect("ping a ditty on Messages", chat("messages", "Udita"))
        await expect("Messages a ditty, see you at 6", chat("messages", "Udita", "see you at 6"))
    }

    func testMisheardMrunal() async {
        await expect("message Marinel", chat("messages", "Mrunal"))
        await expect("message Manal", chat("messages", "Mrunal"))
    }

    func testSoundAlikeNamesAreUnsure() async {
        // With "Manel & Mrunal" in the index, "Manal" can be either. The rules must not be sure.
        let ctx = RouteContext(apps: Fixtures.apps, names: Fixtures.names + [Fixtures.group])
        let r = await route("message Manal", ctx)
        XCTAssertLessThan(r.confidence, SafetyPolicy.minimumConfidence, "\(r.intent) \(r.why)")
        // The E1 miss: "Mrunal" must give Mrunal, not the group chat.
        await expect("message Mrunal", chat("messages", "Mrunal"), ctx)
    }

    // MARK: - Send, numbers, typing

    func testSendNeedsTheWordSend() async {
        await expect("send", .send)
        await expect("send it", .send)
        await expect("okay send it now", .send)
        let r1 = await route("don't send it")
        XCTAssertNotEqual(r1.intent, .send)
        let r2 = await route("send Ravi a message on Slack")
        XCTAssertEqual(r2.intent, chat("slack", "Ravi Kumar"), r2.why)
        let r3 = await route("send the build report to Ravi")
        XCTAssertNotEqual(r3.intent, .send)
    }

    func testShowAndHideNumbers() async {
        await expect("show numbers", .showNumbers)
        await expect("hide the numbers", .hideNumbers)
    }

    func testTypeWithNoScreen() async {
        await expect("type Hello, World", .typeText("Hello, World"))
    }

    // MARK: - E2 voice clicks (E2, section 5)

    var news: RouteContext { RouteContext(apps: Fixtures.apps, names: Fixtures.names, screen: Fixtures.news) }
    var wiki: RouteContext { RouteContext(apps: Fixtures.apps, names: Fixtures.names, screen: Fixtures.wiki) }

    func testE2LabelMatch() async {
        await expect("click new", .click(elementID: "e2"), news)
        await expect("click on past", .click(elementID: "e3"), news)
        await expect("go to the talk page", .click(elementID: "w3"), wiki)
        await expect("view history", .click(elementID: "w7"), wiki)
        await expect("open the article tab", .click(elementID: "w8"), wiki)
        let r = await route("click new", news)
        XCTAssertEqual(r.tier, .rules)
    }

    func testE2NumbersMatchExactly() async {
        await expect("click 382 comments", .click(elementID: "e10"), news)
        await expect("click 384 comments", .click(elementID: "e13"), news)
        await expect("click three hundred eighty two comments", .click(elementID: "e10"), news)
        await expect("click 2", .click(elementID: "e18"), news)
        await expect("click 12", .click(elementID: "e19"), news)
        let r = await route("click 383 comments", news)
        XCTAssertNotEqual(r.intent, .click(elementID: "e10"))
        XCTAssertNotEqual(r.intent, .click(elementID: "e13"))
    }

    func testE2ShownNumbers() async {
        // No label is "3": "click 3" is the element with the id "e3", as T3 numbers them (R-CL-3).
        await expect("click 3", .click(elementID: "e3"), news)
        XCTAssertEqual(CommandRouter.spokenTarget("click the submit button"), "submit")
        // The seventh element is "submit", a risky label. A number is not the exact label, so nothing happens.
        let r = await route("click 7", news)
        XCTAssertEqual(r.intent, .none)
        XCTAssertTrue(r.why.hasPrefix("blocked"), r.why)
    }

    func testE2Ordinals() async {
        await expect("open the second result", .click(elementID: "e12"), news)
        await expect("open the first story", .click(elementID: "e9"), news)
        await expect("open the last result", .click(elementID: "e14"), news)
    }

    func testE2TypeScrollBack() async {
        await expect("search for swift concurrency", .typeInto(elementID: "e17", text: "swift concurrency"), news)
        await expect("search for Swift", .typeInto(elementID: "w5", text: "Swift"), wiki)
        await expect("scroll down", .scroll(.down), news)
        await expect("scroll up", .scroll(.up), news)
        await expect("go to the top", .scroll(.top), news)
        await expect("go back", .back, news)
    }

    func testE2RiskyLabels() async {
        // The exact risky label from the owner gives a click. SafetyPolicy in the actions also checks the mode (R-NV-5).
        await expect("click submit", .click(elementID: "e7"), news)
        await expect("click the submit button", .click(elementID: "e7"), news)
        // A fuzzy match on a risky label does nothing.
        for s in ["click submt", "click donate"] {
            let ctx = s.contains("donate") ? wiki : news
            let r = await route(s, ctx)
            XCTAssertEqual(r.intent, .none, s)
            XCTAssertTrue(r.why.hasPrefix("blocked"), "\(s): \(r.why)")
        }
    }

    // MARK: - Risky labels by role (live: x.com chat row "... You: Sent a post" was blocked)

    static let xRow = "user avatar Prakash Iyer Verified account 1h You: Sent a post"

    func testRiskyWordsCountForControlsOnly() {
        XCTAssertFalse(SafetyPolicy.isRisky(Self.xRow, role: "AXRow"))
        XCTAssertFalse(SafetyPolicy.isRisky(Self.xRow, role: "AXLink"))
        XCTAssertFalse(SafetyPolicy.isRisky(Self.xRow, role: "AXCell"))
        XCTAssertTrue(SafetyPolicy.isRisky(Self.xRow, role: "AXButton"), "a control keeps the strict rule")
        XCTAssertTrue(SafetyPolicy.isRisky(Self.xRow, role: nil), "an unknown role keeps the strict rule")
        XCTAssertTrue(SafetyPolicy.isRisky(Self.xRow, role: "AXSomethingNew"), "an unknown role keeps the strict rule")
        XCTAssertTrue(SafetyPolicy.isRisky("Post", role: "AXButton"))
        XCTAssertTrue(SafetyPolicy.isRisky("Send message", role: "AXButton"))
        XCTAssertTrue(SafetyPolicy.isRisky("Delete", role: "AXLink"))
        XCTAssertTrue(SafetyPolicy.isRisky("Delete account", role: "AXLink"))
        XCTAssertTrue(SafetyPolicy.isRisky("Delete this repository and all of its issues", role: "AXLink"))
        XCTAssertTrue(SafetyPolicy.isRisky("Sign out of all your devices now", role: "AXLink"))
        XCTAssertFalse(SafetyPolicy.isRisky("How we post a new release every week", role: "AXLink"))
        // OCR text has no reliable role: a "Send" button in a canvas can arrive as OCR text. Strict rule.
        XCTAssertTrue(SafetyPolicy.isRisky("Send", role: "OCRText"))
        XCTAssertTrue(SafetyPolicy.isRisky("Post now", role: "OCRText"))
        XCTAssertTrue(SafetyPolicy.isRisky("Send", role: "AXUnknownRole"))
        // A click on a group or an image can land on a child control: strict rule.
        XCTAssertTrue(SafetyPolicy.isRisky("Type a message Send", role: "AXGroup"))
        XCTAssertTrue(SafetyPolicy.isRisky("Photo of the team you can share with friends", role: "AXImage"))
        // A short row keeps the strict rule; a long row follows the non-control rule.
        XCTAssertTrue(SafetyPolicy.isRisky("Delete chat", role: "AXRow"))
        XCTAssertFalse(SafetyPolicy.isRisky(Self.xRow, role: "AXStaticText"))
        // The press gate uses the same rule.
        XCTAssertTrue(SafetyPolicy.mayPress(label: Self.xRow, role: "AXRow", spokenTarget: "prakash iyyer", tier: .fuzzy,
                                            mode: .hold))
        XCTAssertFalse(SafetyPolicy.mayPress(label: Self.xRow, spokenTarget: "prakash iyyer", tier: .fuzzy, mode: .hold))
    }

    func testClickAChatRowWithMessageText() async {
        let page = ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "Messages / X", url: "https://x.com/messages",
                                  elements: [
            Fixtures.el("e1", "AXRow", Self.xRow, y: 100),
            Fixtures.el("e2", "AXButton", "Post", y: 10),
            Fixtures.el("e3", "AXLink", "Home", y: 10, x: 50),
        ])
        let ctx = RouteContext(apps: Fixtures.apps, names: Fixtures.names, screen: page)
        let r = await route("Click on Prakash Iyyer", ctx)
        XCTAssertEqual(r.intent, .click(elementID: "e1"), r.why)
        XCTAssertGreaterThanOrEqual(r.confidence, SafetyPolicy.minimumConfidence, "a name in a long row is a sure match: \(r.why)")
        // A text that the OCR fallback found is a click target too (R-CL-4). An OCR text keeps the strict risky rule.
        let canvas = ScreenSnapshot(bundleID: "com.figma.Desktop", windowTitle: "Figma", elements: [
            Fixtures.el("e1", "OCRText", "Quarterly report", y: 100),
            Fixtures.el("e2", "OCRText", "You: Sent a post about the launch", y: 140),
        ])
        let ocr = await route("click quarterly report", RouteContext(apps: Fixtures.apps, names: Fixtures.names, screen: canvas))
        XCTAssertEqual(ocr.intent, .click(elementID: "e1"), ocr.why)
        XCTAssertTrue(SafetyPolicy.isRisky("You: Sent a post about the launch", role: "OCRText"))
        let post = await route("click post", ctx)
        XCTAssertEqual(post.intent, .click(elementID: "e2"), "the exact risky label still gives a click: \(post.why)")
    }

    // MARK: - "On <app>, <screen command>" (live: "On Chrome, click Chat" went to a Slack chat)

    func testAppPrefixGoesToTheScreen() async {
        let chatLink = ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "Gemini", elements: [
            Fixtures.el("e1", "AXLink", "Chat", y: 10), Fixtures.el("e2", "AXLink", "Settings", y: 10, x: 80),
        ])
        let chrome = RouteContext(apps: Fixtures.apps, names: Fixtures.names, frontBundleID: "com.google.Chrome", screen: chatLink)
        await expect("On Chrome, click Chat", .click(elementID: "e1"), chrome)
        await expect("uh, on Google Chrome click settings", .click(elementID: "e2"), chrome)
        await expect("in Chrome scroll down", .scroll(.down), chrome)
        let threads = ScreenSnapshot(bundleID: "com.tinyspeck.slackmacgap", windowTitle: "Slack", elements: [
            Fixtures.el("e1", "AXButton", "Threads", y: 10),
        ])
        let slack = RouteContext(apps: Fixtures.apps, names: Fixtures.names, frontBundleID: "com.tinyspeck.slackmacgap",
                                 screen: threads)
        await expect("on Slack, click Threads", .click(elementID: "e1"), slack)
        // The app is not in front: open it, and do not click on another app's screen.
        let r = await route("On Chrome, click Chat", slack)
        XCTAssertEqual(r.intent, .openApp(appID: "chrome"), r.why)
        // Not a screen command: the chat rules still apply ("Felix on Messages" form).
        await expect("on Slack message Ravi", chat("slack", "Ravi Kumar"), slack)
    }

    func testOpenLabelOnAnApp() async {
        let x = ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "Home / X", url: "https://x.com/home", elements: [
            Fixtures.el("e1", "AXLink", "Home", y: 10), Fixtures.el("e2", "AXLink", "Explore", y: 40),
            Fixtures.el("e3", "AXLink", "Notifications", y: 70), Fixtures.el("e4", "AXLink", "Messages", y: 100),
            Fixtures.el("e5", "AXButton", "Delete", y: 130), Fixtures.el("e6", "AXLink", "Bookmarks", y: 160),
        ])
        let chrome = RouteContext(apps: Fixtures.apps, names: Fixtures.names, frontBundleID: "com.google.Chrome", screen: x)
        await expect("Open notifications on Chrome.", .click(elementID: "e3"), chrome)
        await expect("open bookmarks in Google Chrome", .click(elementID: "e6"), chrome)
        await expect("Chrome, open explore", .click(elementID: "e2"), chrome)
        // An app name still wins over a label.
        await expect("open notes", .openApp(appID: "notes"), chrome)
        // "open" never presses a risky label.
        let del = await route("open delete on Chrome", chrome)
        XCTAssertEqual(del.intent, .none)
        XCTAssertTrue(del.why.hasPrefix("blocked"), del.why)
        // A weak match keeps today's answer: open the app.
        let weak = await route("open the quarterly figures on Chrome", chrome)
        XCTAssertEqual(weak.intent, .openApp(appID: "chrome"), weak.why)
        // Chrome not in front: open it, no click.
        let slackFront = RouteContext(apps: Fixtures.apps, names: Fixtures.names, frontBundleID: "com.tinyspeck.slackmacgap")
        let away = await route("open notifications on Chrome", slackFront)
        XCTAssertEqual(away.intent, .openApp(appID: "chrome"), away.why)
        // A chat form with a comma stays a chat: "Slack, Ravi".
        await expect("Slack, Ravi", chat("slack", "Ravi Kumar"))
    }

    // MARK: - Menu commands (menu items join the screen elements; the intent stays .click)

    static let menus = MenuElements.elements([
        MenuEntry(path: ["Edit", "Undo"]), MenuEntry(path: ["Edit", "Redo"], enabled: false),
        MenuEntry(path: ["Edit", "Copy"]), MenuEntry(path: ["Edit", "Paste"]), MenuEntry(path: ["Edit", "Select All"]),
        MenuEntry(path: ["File", "New Note"]), MenuEntry(path: ["File", "Export…"]),
        MenuEntry(path: ["File", "Close Window"]), MenuEntry(path: ["Notes", "Quit Notes"]),
        MenuEntry(path: ["Meeting", "Mute Audio"]),
    ])

    func menuContext(_ screen: [ScreenElement] = []) -> RouteContext {
        RouteContext(apps: Fixtures.apps, names: Fixtures.names, frontBundleID: "com.apple.Notes",
                     screen: ScreenSnapshot(bundleID: "com.apple.Notes", windowTitle: "Notes", elements: screen + Self.menus))
    }

    func testMenuElements() {
        XCTAssertEqual(MenuElements.id(["Edit", "Select All"]), "m:Edit>Select All")
        XCTAssertEqual(MenuElements.path("m:Edit>Select All"), ["Edit", "Select All"])
        XCTAssertNil(MenuElements.path("e5"))
        XCTAssertFalse(Self.menus.contains { $0.label == "Redo" }, "a disabled item is not a candidate")
        XCTAssertTrue(Self.menus.first { $0.label == "Quit Notes" }!.risky)
        XCTAssertTrue(Self.menus.first { $0.label == "Close Window" }!.risky)
        XCTAssertFalse(Self.menus.first { $0.label == "Copy" }!.risky)
    }

    func testMenuCommandsWithNoVerb() async {
        let ctx = menuContext()
        await expect("copy", .click(elementID: "m:Edit>Copy"), ctx)
        await expect("paste", .click(elementID: "m:Edit>Paste"), ctx)
        await expect("undo", .click(elementID: "m:Edit>Undo"), ctx)
        await expect("select all", .click(elementID: "m:Edit>Select All"), ctx)
        await expect("new note", .click(elementID: "m:File>New Note"), ctx)
        await expect("export", .click(elementID: "m:File>Export…"), ctx)
        await expect("uh, mute audio", .click(elementID: "m:Meeting>Mute Audio"), ctx)
        // A disabled item is not there.
        let redo = await route("redo", ctx)
        XCTAssertEqual(redo.intent, .none, redo.why)
        // Speech that is not a menu title does nothing.
        let talk = await route("I think the meeting moved to Thursday", ctx)
        XCTAssertEqual(talk.intent, .none, talk.why)
    }

    func testMenuAndScreenWithTheSameLabel() async {
        let ctx = menuContext([Fixtures.el("e1", "AXButton", "Copy", y: 50), Fixtures.el("e2", "AXLink", "All", y: 60)])
        // "click" prefers the element on the screen; no verb prefers the menu item.
        await expect("click copy", .click(elementID: "e1"), ctx)
        await expect("copy", .click(elementID: "m:Edit>Copy"), ctx)
        // "select all" is the menu title, not "select" + the link "All".
        await expect("select all", .click(elementID: "m:Edit>Select All"), ctx)
    }

    func testRiskyMenuItemsNeedTheExactTitle() async {
        let ctx = menuContext()
        // The exact title gives a click at tier .rules. The actions then also need the hold key (R-NV-5, R-ON-5).
        let close = await route("close window", ctx)
        XCTAssertEqual(close.intent, .click(elementID: "m:File>Close Window"), close.why)
        XCTAssertEqual(close.tier, .rules)
        XCTAssertTrue(SafetyPolicy.mayPress(label: "Close Window", role: MenuElements.role,
                                            spokenTarget: CommandRouter.spokenTarget("close window"), tier: close.tier, mode: .hold))
        XCTAssertFalse(SafetyPolicy.mayPress(label: "Close Window", role: MenuElements.role,
                                             spokenTarget: CommandRouter.spokenTarget("close window"), tier: close.tier, mode: .alwaysOn))
        // Not the exact title: blocked.
        for s in ["quit", "close the window", "quit note"] {
            let r = await route(s, ctx)
            XCTAssertNotEqual(r.intent, .click(elementID: "m:Notes>Quit Notes"), s)
            XCTAssertNotEqual(r.intent, .click(elementID: "m:File>Close Window"), s)
        }
        XCTAssertTrue(SafetyPolicy.isRisky("Empty Trash", role: MenuElements.role))
        XCTAssertTrue(SafetyPolicy.isRisky("Shut Down…", role: MenuElements.role))
    }

    // MARK: - Live x.com cases (status part, "on open Chrome window", sound match, tabs)

    /// A Chrome window on x.com, with two tabs in the tab strip (AXRadioButton in an AXTabGroup).
    static let xcomScreen = ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "Home / X", url: "https://x.com/home", elements: [
        Fixtures.el("t1", "AXRadioButton", "shadcn/ui", y: 5, x: 100),
        Fixtures.el("t2", "AXRadioButton", "FPL Guru", y: 5, x: 300),
        Fixtures.el("e1", "AXLink", "Skip to home timeline", y: 60),
        Fixtures.el("e2", "AXLink", "Home (New unread posts)", y: 100),
        Fixtures.el("e3", "AXLink", "Chat", y: 140),
        Fixtures.el("e4", "AXButton", "More", y: 180),
        Fixtures.el("e5", "AXTextField", "Search", y: 60, x: 900),
        Fixtures.el("e6", "AXLink", "Pull requests (1)", y: 220),
        Fixtures.el("e7", "AXLink", "Chats, 44", y: 260),
    ])

    func xcom(_ elements: [ScreenElement]? = nil) -> RouteContext {
        var screen = Self.xcomScreen
        if let elements { screen.elements = elements }
        return RouteContext(apps: Fixtures.apps, names: Fixtures.names, frontBundleID: "com.google.Chrome", screen: screen)
    }

    func testLiveClickHomeOnXcom() async {
        let noSkip = xcom(Self.xcomScreen.elements.filter { $0.id != "e1" })
        for ctx in [xcom(), noSkip] {
            for s in ["Click home.", "Click home on Chrome.", "Click home on open Chrome window."] {
                await expect(s, .click(elementID: "e2"), ctx)
                let r = await route(s, ctx)
                XCTAssertEqual(r.tier, .rules, "\(s): the label with no status part is exact")
            }
        }
        await expect("click pull requests", .click(elementID: "e6"), xcom())
        await expect("click chats", .click(elementID: "e7"), xcom())
    }

    func testStatusFreeLabels() {
        XCTAssertEqual(ScreenRouter.statusFree("Home (New unread posts)"), "Home")
        XCTAssertEqual(ScreenRouter.statusFree("Pull requests (1)"), "Pull requests")
        XCTAssertEqual(ScreenRouter.statusFree("Chats, 44"), "Chats")
        XCTAssertNil(ScreenRouter.statusFree("Home"))
        XCTAssertNil(ScreenRouter.statusFree("(3)"), "a label that is only a status part keeps its label")
    }

    func testLiveTabTitles() async {
        await expect("Open the shad CN/UI tab.", .click(elementID: "t1"), xcom())
        await expect("Open the FPL guru tab on Chrome.", .click(elementID: "t2"), xcom())
        await expect("go to the FPL Guru tab", .click(elementID: "t2"), xcom())
        await expect("switch to FPL Guru", .click(elementID: "t2"), xcom())
        // An app name still wins: "switch to Slack" opens Slack.
        await expect("switch to Slack", .openApp(appID: "slack"), xcom())
    }

    func testLiveSoundAlikeLabel() async {
        let r = await route("Click on chart.", xcom())
        XCTAssertEqual(r.intent, .click(elementID: "e3"), r.why)
        XCTAssertEqual(r.tier, .fuzzy, "a near spelling or sound match is never exact")
        // A sound match is fuzzy, so it never presses a risky label (R-NV-5).
        let risky = await route("click delight", RouteContext(apps: Fixtures.apps, names: Fixtures.names,
            screen: ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "x", elements: [Fixtures.el("b1", "AXButton", "Delete", y: 10)])))
        XCTAssertNotEqual(risky.intent, .click(elementID: "b1"), risky.why)
    }

    func testNoSureNoneWhenALabelIsNear() async {
        // Only one word of four is near a label: not a match, but not a sure "none".
        let r = await route("click homer simpson fan page", xcom())
        XCTAssertEqual(r.intent, .none, r.why)
        XCTAssertLessThan(r.confidence, SafetyPolicy.minimumConfidence, r.why)
        // Words that are near no label: a sure "none".
        let far = await route("click zebra quantum", xcom())
        XCTAssertEqual(far.intent, .none)
        XCTAssertEqual(far.why, "no label matches")
    }

    // MARK: - Live cases: letter group + number, whole numbers, app names by sound

    func liveContext(_ elements: [ScreenElement], apps: [AppEntry] = Fixtures.apps) -> RouteContext {
        RouteContext(apps: apps, names: Fixtures.names, frontBundleID: "com.google.Chrome",
                     screen: ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "Fantasy", elements: elements))
    }

    func testLetterGroupAndNumber() async {
        let ctx = liveContext([Fixtures.el("e1", "AXLink", "Review GW8", y: 10), Fixtures.el("e2", "AXLink", "Review GW9", y: 20),
                               Fixtures.el("e3", "AXLink", "Plan GW10", y: 30)])
        await expect("Click on review GW 8", .click(elementID: "e1"), ctx)
        await expect("click review gw eight", .click(elementID: "e1"), ctx)
        await expect("Click on plan GW 10", .click(elementID: "e3"), ctx)
        XCTAssertEqual(ScreenRouter.joinLetterNumber(["review", "gw", "8"]), ["review", "gw8"])
        XCTAssertEqual(ScreenRouter.joinLetterNumber(["page", "2"]), ["page", "2"], "a long word does not join")
        XCTAssertEqual(ScreenRouter.numbers(["gw8"]), ["8"])
    }

    func testANumberMatchesOnlyAWholeNumber() async {
        let ctx = liveContext([Fixtures.el("e1", "AXLink", "Player Who Returned 10,000 Years Later", y: 10),
                               Fixtures.el("e2", "AXLink", "Plan 100", y: 20)])
        let r = await route("Click on plan GW 10", ctx)
        XCTAssertEqual(r.intent, .none, r.why)
        XCTAssertFalse(r.why.contains("Player"), r.why)
        XCTAssertFalse(r.why.contains("Plan 100"), r.why)
        await expect("click plan 100", .click(elementID: "e2"), ctx)
        XCTAssertEqual(ScreenRouter.joinThousands("Returned 10,000 Years"), "Returned 10000 Years")
        XCTAssertEqual(ScreenRouter.joinThousands("Chats, 44"), "Chats, 44")
        XCTAssertEqual(ScreenRouter.info("Player Who Returned 10,000 Years Later").numbers, ["10000"])
        XCTAssertEqual(ScreenRouter.score(["10"], "Plan 100"), 0)
    }

    func testAppNameBySound() async {
        let claude = AppEntry(id: "claude", name: "Claude", bundleID: "com.example.claude", aliases: ["claude"], approved: true)
        let menus = MenuElements.elements([MenuEntry(path: ["File", "Reopen Closed Tab"]), MenuEntry(path: ["View", "Reload"]),
                                           MenuEntry(path: ["History", "Show Full History"])])
        let ctx = liveContext(menus, apps: Fixtures.apps + [claude])
        await expect("Open Cloud.", .openApp(appID: "claude"), ctx)
        await expect("go to cloud", .openApp(appID: "claude"), ctx)
        // An exact label on the screen wins: the screen rules press it.
        let label = liveContext([Fixtures.el("e1", "AXButton", "Cloud", y: 10)], apps: Fixtures.apps + [claude])
        await expect("open cloud", .click(elementID: "e1"), label)
        // No app sounds like it: no app.
        let r = await route("open crowd", ctx)
        XCTAssertNotEqual(r.intent, .openApp(appID: "claude"), r.why)
        // The app must be approved.
        var unapproved = claude
        unapproved.approved = false
        let off = await route("Open Cloud.", liveContext(menus, apps: Fixtures.apps + [unapproved]))
        XCTAssertNotEqual(off.intent, .openApp(appID: "claude"), off.why)
    }

    func testE2NoCommand() async {
        let r = await route("what a lovely day", news)
        XCTAssertEqual(r.intent, .none)
    }

    func testChatWinsOverScreen() async {
        await expect("message Felix", chat("messages", "Felix"), news)
        await expect("open Slack", .openApp(appID: "slack"), wiki)
    }

    // MARK: - Tier 2 (R-MD-1, D-9)

    func testTier2IsOffByDefault() {
        XCTAssertNil(CommandRouter().tier2)
        XCTAssertNil(CommandRouter(settings: EarshotSettings(), jevKey: "key").tier2)
        var s = EarshotSettings()
        s.tier2 = .jev
        XCTAssertNil(Tier2Factory.make(s, jevKey: nil))
        XCTAssertNil(Tier2Factory.make(s, jevKey: "  "))
        XCTAssertTrue(Tier2Factory.make(s, jevKey: "key") is JevChooser)
    }

    func testTier2DecidesWhenRulesAreUnsure() async {
        let fake = FakeChooser { options in options.firstIndex { $0.contains("Felix") } }
        let r = await route("get me Felix's chat", router: CommandRouter(tier2: fake))
        XCTAssertEqual(r.intent, chat("messages", "Felix"))
        XCTAssertEqual(r.tier, .jev)
        XCTAssertEqual(fake.calls.count, 1)
        // Tier 2 sees labels only, never message text.
        XCTAssertFalse(fake.calls[0].contains { $0.contains("buy milk") })
    }

    func testTier2IsNotAskedWhenRulesAreSure() async {
        let fake = FakeChooser { _ in 0 }
        let r = await route("Messages me, buy milk", router: CommandRouter(tier2: fake))
        XCTAssertEqual(r.intent, chat("messages", "Owner", "buy milk"))
        XCTAssertEqual(fake.calls.count, 0)
    }

    func testTier2BudgetKeepsTheRulesAnswer() async {
        let slow = FakeChooser(delayMs: 2000) { _ in 0 }
        let t0 = Date()
        let r = await route("get me Felix's chat", router: CommandRouter(tier2: slow, tier2BudgetMs: 100))
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.0)
        XCTAssertEqual(r.intent, .none)
        XCTAssertNotEqual(r.tier, .jev)
    }

    func testTier2NoneKeepsTheRulesAnswer() async {
        let fake = FakeChooser { _ in nil }
        let r = await route("get me Felix's chat", router: CommandRouter(tier2: fake))
        XCTAssertEqual(r.intent, .none)
        XCTAssertLessThan(r.confidence, SafetyPolicy.minimumConfidence)
    }

    func testTier2NeverGetsARiskyLabel() async {
        let fake = FakeChooser { _ in nil }
        _ = await route("click hid", news, router: CommandRouter(tier2: fake))
        for options in fake.calls { XCTAssertFalse(options.contains { $0.contains("\"hide\"") }, "\(options)") }
    }

    // MARK: - Jev client

    static func jevReply(_ choice: String, ids: [String]) -> Data {
        var probs: [String: Double] = [:]
        for id in ids { probs[id] = id == choice ? 0.9 : 0.1 / Double(ids.count - 1) }
        let body: [String: Any] = ["answers": ["route": ["choice": choice, "confidence": 0.9, "probabilities": probs]]]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    final class Captured: @unchecked Sendable { var request: URLRequest? }

    func testJevSendsTextOnlyAndReadsTheChoice() async throws {
        let captured = Captured()
        let jev = JevChooser(apiKey: "test-key") { request in
            captured.request = request
            return (Self.jevReply("o2", ids: ["o1", "o2", "none"]), 200)
        }
        let i = await jev.choose("message Marinel", options: ["Messages: open the chat \"Mrunal\"", "Open the app Messages"],
                                 budgetMs: 1000)
        XCTAssertEqual(i, 1)
        let req = try XCTUnwrap(captured.request)
        XCTAssertEqual(req.url, JevChooser.endpoint)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(req.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["model", "state", "questions"])
        XCTAssertEqual(body["state"] as? [String: String], ["command": "message Marinel"])
    }

    func testJevNoneAndBadAnswersGiveNil() async {
        let none = JevChooser(apiKey: "k") { _ in (Self.jevReply("none", ids: ["o1", "none"]), 200) }
        let a = await none.choose("x", options: ["a"], budgetMs: 1000)
        XCTAssertNil(a)
        let bad = JevChooser(apiKey: "k") { _ in (Data(#"{"answers":{"route":{"choice":"o1","probabilities":{"o1":0.2,"none":0.3}}}}"#.utf8), 200) }
        let b = await bad.choose("x", options: ["a"], budgetMs: 1000)
        XCTAssertNil(b)
        let error = JevChooser(apiKey: "k") { _ in (Data(), 503) }
        let c = await error.choose("x", options: ["a"], budgetMs: 1000)
        XCTAssertNil(c)
    }

    func testJevKeepsItsBudget() async {
        let slow = JevChooser(apiKey: "k") { _ in
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return (Self.jevReply("o1", ids: ["o1", "none"]), 200)
        }
        let t0 = Date()
        let i = await slow.choose("x", options: ["a"], budgetMs: 100)
        XCTAssertNil(i)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.0)
    }

    // MARK: - Text helpers

    func testDigitize() {
        XCTAssertEqual(TextKit.digitize(["three", "hundred", "eighty", "two"]), ["382"])
        XCTAssertEqual(TextKit.digitize(["twenty", "one", "comments"]), ["21", "comments"])
        XCTAssertEqual(TextKit.digitize(["three", "hundred", "and", "five"]), ["305"])
        XCTAssertEqual(TextKit.digitize(["one", "piece"]), ["1", "piece"])
    }

    // MARK: - Latency (AGENTS.md: measure every change to the command path)

    func testRulesLatency() async {
        let chats = ["message Prakash Iyer on Slack", "Slack Prakash", "message prakush on Slack", "Messages me, buy milk",
                     "tell Ravi on Slack that I will be ten minutes late", "message a ditty", "message Marinel",
                     "switch to Slack", "I think the meeting moved to Thursday", "get me Felix's chat"]
        let clicks = ["click new", "click 382 comments", "open the second result", "search for swift concurrency",
                      "go to the talk page", "click submt"]
        var chatMs: [Double] = [], clickMs: [Double] = []
        for _ in 0..<30 {
            for s in chats { chatMs.append(await route(s).ms) }
            for s in clicks { clickMs.append(await route(s, s.contains("talk") ? wiki : news).ms) }
        }
        func pct(_ xs: [Double], _ p: Double) -> Double {
            let s = xs.sorted()
            return s[max(0, min(s.count - 1, Int((p * Double(s.count)).rounded(.up)) - 1))]
        }
        let line = String(format: "LATENCY rules, chat: median %.3f ms, p90 %.3f ms, max %.3f ms; screen: median %.3f ms, p90 %.3f ms, max %.3f ms",
                          pct(chatMs, 0.5), pct(chatMs, 0.9), chatMs.max()!, pct(clickMs, 0.5), pct(clickMs, 0.9), clickMs.max()!)
        print(line)
        XCTAssertLessThan(pct(chatMs, 0.5), 20)
        XCTAssertLessThan(pct(clickMs, 0.5), 20)
    }
}
