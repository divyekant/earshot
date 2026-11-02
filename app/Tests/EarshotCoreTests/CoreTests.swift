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
    }

    func testBlockedPages() {
        XCTAssertTrue(SafetyPolicy.isBlockedPage(url: "https://account.example.com/signInTwoFactorAuth",
                                                 title: "Account", labels: ["Verification code"]))
        XCTAssertFalse(SafetyPolicy.isBlockedPage(url: "https://news.ycombinator.com/", title: "Hacker News",
                                                  labels: ["new", "past", "comments"]))
    }

    func testReturnOnlyForSend() {
        XCTAssertTrue(SafetyPolicy.mayPressReturn(for: .send))
        XCTAssertFalse(SafetyPolicy.mayPressReturn(for: .openChat(appID: "slack", target: "Ravi", text: "hi")))
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
