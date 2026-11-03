import EarshotCore
import Foundation
import XCTest

final class CoreTests: XCTestCase {
    func testRiskyLabels() {
        XCTAssertTrue(SafetyPolicy.isRisky("Donate"))
        XCTAssertTrue(SafetyPolicy.isRisky("Star divyekant/earshot"))
        XCTAssertTrue(SafetyPolicy.isRisky("Sign out"))
        XCTAssertFalse(SafetyPolicy.isRisky("Insights"))
        XCTAssertFalse(SafetyPolicy.isRisky("Starred repositories"))  // whole words only
        XCTAssertTrue(SafetyPolicy.isRisky("upvote"))
        XCTAssertTrue(SafetyPolicy.isRisky("Merge pull request"))
        XCTAssertTrue(SafetyPolicy.isRisky("Add to cart"))
    }

    func testMayPressRiskyOnlyOnExactHoldRulesCommand() {
        XCTAssertTrue(SafetyPolicy.mayPress(label: "Insights", spokenTarget: "insights", tier: .jev, mode: .alwaysOn))
        XCTAssertTrue(SafetyPolicy.mayPress(label: "Send", spokenTarget: "send", tier: .rules, mode: .hold))
        XCTAssertFalse(SafetyPolicy.mayPress(label: "Send", spokenTarget: "send", tier: .jev, mode: .hold))
        XCTAssertFalse(SafetyPolicy.mayPress(label: "Send", spokenTarget: "send", tier: .rules, mode: .alwaysOn))
        XCTAssertFalse(SafetyPolicy.mayPress(label: "Merge pull request", spokenTarget: "merge", tier: .rules, mode: .hold))
    }

    private func el(_ role: String, _ label: String, subrole: String = "") -> ScreenElement {
        ScreenElement(id: label, role: role, subrole: subrole, label: label, risky: false)
    }

    func testSensitivePages() {
        // Normal pages with sign-in links and story titles are not blocked.
        XCTAssertNil(SafetyPolicy.sensitive(url: "https://en.wikipedia.org/wiki/Computer_accessibility",
                                            elements: [el("AXLink", "Log in"), el("AXLink", "Create account")]))
        XCTAssertNil(SafetyPolicy.sensitive(url: "https://news.ycombinator.com/",
                                            elements: [el("AXLink", "Show HN: a password manager in 200 lines")]))
        // Sign-in, code and payment pages are blocked.
        XCTAssertNotNil(SafetyPolicy.sensitive(url: "https://example.com/home",
                                               elements: [el("AXTextField", "", subrole: "AXSecureTextField")]))
        XCTAssertNotNil(SafetyPolicy.sensitive(url: "https://example.com/account",
                                               elements: [el("AXTextField", "Verification code")]))
        XCTAssertNotNil(SafetyPolicy.sensitive(url: "https://example.com/signin", elements: []))
    }

    func testOnHost() {
        XCTAssertTrue(SafetyPolicy.onHost("https://www.google.com/search?q=x", "google.com"))
        XCTAssertTrue(SafetyPolicy.onHost("https://en.wikipedia.org/wiki/X", "wikipedia.org"))
        XCTAssertFalse(SafetyPolicy.onHost("https://account.samsung.com/signin", "github.com"))
    }

    func testReturnRule() {
        XCTAssertTrue(SafetyPolicy.mayPressReturn(for: .send, inMessageBox: true))
        XCTAssertFalse(SafetyPolicy.mayPressReturn(for: .openChat(appID: "slack", target: "Ravi", text: "hi"), inMessageBox: true))
        // The chat switcher field needs Return to open the chat (E0).
        XCTAssertTrue(SafetyPolicy.mayPressReturn(for: .openChat(appID: "slack", target: "Ravi", text: nil), inMessageBox: false))
    }

    func testPlaySoundsDefaultsOnForAnOldFile() throws {
        let old = Data(#"{"mode": "alwaysOn", "showFeedback": false}"#.utf8)
        let s = try JSONDecoder().decode(EarshotSettings.self, from: old)
        XCTAssertTrue(s.playSounds, "an old settings file has no playSounds key: sounds are on")
        XCTAssertEqual(s.mode, .alwaysOn)
        XCTAssertFalse(s.showFeedback)
    }

    func testStoreAndLogRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(folder: folder)
        XCTAssertEqual(store.settings, EarshotSettings())

        var s = EarshotSettings()
        s.mode = .alwaysOn
        try store.save(s, "settings.json")
        XCTAssertEqual(store.settings.mode, .alwaysOn)

        try store.save([AppEntry(id: "slack", name: "Slack", bundleID: "com.tinyspeck.slackmacgap",
                                 openChat: .switcher(keys: "cmd+k"))], "apps.json")
        XCTAssertEqual(store.apps.first?.openChat, .switcher(keys: "cmd+k"))

        let log = ActivityLog(store: store)
        try log.append(ActivityRecord(heard: "slack me", intent: "openChat", tier: .rules, ok: true, note: "", stages: ["focus": 466]))
        try log.append(ActivityRecord(heard: "open notes", intent: "openApp", tier: .rules, ok: true, note: "", stages: [:]))
        XCTAssertEqual(log.last(1).first?.heard, "open notes")
        XCTAssertEqual(log.last(10).count, 2)
    }
}
