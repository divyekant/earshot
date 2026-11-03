import EarshotCore
import XCTest
@testable import EarshotUI

final class HoldKeyTests: XCTestCase {
    func testDefaultIsRightOption() {
        XCTAssertEqual(HoldKeys.name(of: EarshotSettings()), "Right Option")  // R-ON-4
    }

    func testRecordModifierAloneClearsModifiers() {
        var s = EarshotSettings()
        HoldKeys.apply(code: 54, modifiers: 1 << 20, to: &s)
        XCTAssertEqual(s.holdKeyCode, 54)
        XCTAssertTrue(s.holdKeyIsModifierOnly)
        XCTAssertEqual(s.holdKeyModifiers, 0)
        XCTAssertEqual(HoldKeys.name(of: s), "Right Command")
    }

    func testRecordKeyWithModifier() {
        var s = EarshotSettings()
        HoldKeys.apply(code: 96, modifiers: (1 << 18) | (1 << 8), to: &s)  // Control + F5, plus a non-modifier bit
        XCTAssertFalse(s.holdKeyIsModifierOnly)
        XCTAssertEqual(s.holdKeyModifiers, 1 << 18)
        XCTAssertEqual(HoldKeys.name(of: s), "Control + F5")
    }

    func testWarnings() {
        XCTAssertNotNil(HoldKeys.warning(code: 36, modifierOnly: false, modifiers: 0))  // Return can send (R-NV-5)
        XCTAssertNotNil(HoldKeys.warning(code: 49, modifierOnly: false, modifiers: 0))
        XCTAssertNotNil(HoldKeys.warning(code: 0, modifierOnly: false, modifiers: 0))   // "a" types a character
        XCTAssertNil(HoldKeys.warning(code: 61, modifierOnly: true, modifiers: 0))
        XCTAssertNil(HoldKeys.warning(code: 96, modifierOnly: false, modifiers: 0))
    }
}

final class CatalogueEditTests: XCTestCase {
    func testMergeKeepsOwnerChoicesAndAddsNewRowsUnapproved() {  // R-MT-2
        let saved = [AppEntry(id: "a", name: "Alpha", bundleID: "x.a", aliases: ["al"], approved: true, enabled: false)]
        let found = [AppEntry(id: "a", name: "Alpha 2", bundleID: "x.a", aliases: ["alpha"], isChat: true, approved: false),
                     AppEntry(id: "b", name: "Beta", bundleID: "x.b", approved: true)]
        let merged = CatalogueEdit.merge(saved: saved, discovered: found)
        XCTAssertEqual(merged.map(\.id), ["a", "b"])
        XCTAssertEqual(merged[0].name, "Alpha 2")
        XCTAssertTrue(merged[0].approved)
        XCTAssertFalse(merged[0].enabled)
        XCTAssertTrue(merged[0].isChat)
        XCTAssertEqual(merged[0].aliases, ["al", "alpha"])
        XCTAssertFalse(merged[1].approved)
    }

    func testMergeKeepsRowsThatDiscoveryDidNotFind() {
        let saved = [AppEntry(id: "z", name: "Zed", bundleID: "x.z", approved: true)]
        XCTAssertEqual(CatalogueEdit.merge(saved: saved, discovered: []).map(\.id), ["z"])
    }

    func testReplaceNamesKeepsManualAndOwnerMarks() {
        let saved = [NameEntry(appID: "a", name: "Me", isSelf: true, source: .sidebar),
                     NameEntry(appID: "a", name: "Old", source: .sidebar),
                     NameEntry(appID: "a", name: "Typed", source: .manual),
                     NameEntry(appID: "b", name: "Other", source: .sidebar)]
        let found = [NameEntry(appID: "a", name: "me", source: .sidebar),
                     NameEntry(appID: "a", name: "typed", source: .search),
                     NameEntry(appID: "a", name: "New", source: .search)]
        let out = CatalogueEdit.replaceNames(saved, appID: "a", with: found)
        XCTAssertEqual(Set(out.map(\.name)), ["Typed", "Other", "me", "New"])
        XCTAssertTrue(out.first { $0.name == "me" }!.isSelf)
        XCTAssertEqual(out.filter { SafetyPolicy.normalize($0.name) == "typed" }.count, 1)
    }

    func testAddManual() {
        var names = CatalogueEdit.addManual([], appID: "a", name: "  Ravi ")
        XCTAssertEqual(names.first?.name, "Ravi")
        XCTAssertEqual(names.first?.source, .manual)
        names = CatalogueEdit.addManual(names, appID: "a", name: "ravi")
        XCTAssertEqual(names.count, 1)
        XCTAssertEqual(CatalogueEdit.addManual(names, appID: "a", name: "  ").count, 1)
    }

    func testParseAliases() {
        XCTAssertEqual(CatalogueEdit.parseAliases("imessage, text , ,Text"), ["imessage", "text"])
    }
}

final class ActivityStatsTests: XCTestCase {
    private func record(_ ok: Bool, _ stages: [String: Double], tier: RouterTier = .rules) -> ActivityRecord {
        ActivityRecord(heard: "h", intent: "i", tier: tier, ok: ok, note: "", stages: stages)
    }

    func testTotalAndStageLine() {
        let r = record(true, ["route": 135, "text": 120, "chat": 380])
        XCTAssertEqual(ActivityStats.total(r), 380)
        XCTAssertEqual(ActivityStats.stageLine(r), "text 120 · route 135 · chat 380")
        XCTAssertNil(ActivityStats.total(record(true, [:])))
    }

    func testPercentile() {
        XCTAssertNil(ActivityStats.percentile([], 0.5))
        XCTAssertEqual(ActivityStats.percentile([5, 1, 3, 2, 4], 0.5), 3)
        XCTAssertEqual(ActivityStats.percentile(Array(1...10).map(Double.init), 0.9), 9)
        XCTAssertEqual(ActivityStats.percentile([7], 0.9), 7)
    }

    func testSummary() {
        let s = ActivityStats.summary([record(true, ["a": 100]), record(false, ["a": 300], tier: .jev), record(true, [:])])
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.okCount, 2)
        XCTAssertEqual(s.medianMs, 100)
        XCTAssertEqual(s.byTier, ["rules": 2, "jev": 1])
        XCTAssertEqual(ActivityStats.summaryLine(s), "3 commands · 2 OK · median 100 ms · p90 300 ms")
    }

    func testReadsLogFromStore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = ActivityLog(store: Store(folder: folder))
        try log.append(record(true, ["text": 90]))
        XCTAssertEqual(log.last(10).count, 1)
    }
}

final class IntentTextTests: XCTestCase {
    func testDescribe() {  // R-FB-1
        let apps = [AppEntry(id: "app1", name: "Chat App", bundleID: "x.c")]
        XCTAssertEqual(IntentText.describe(.openApp(appID: "app1"), apps: apps), "→ Chat App")
        XCTAssertEqual(IntentText.describe(.openChat(appID: "app1", target: "Ravi", text: nil), apps: apps), "→ Chat App · Ravi")
        XCTAssertEqual(IntentText.describe(.openChat(appID: "zz", target: "Ravi", text: "late"), apps: apps), "→ zz · Ravi · type \"late\"")
        let screen = ScreenSnapshot(bundleID: "b", windowTitle: "w", elements: [ScreenElement(id: "e1", role: "AXLink", label: "Docs", risky: false)])
        XCTAssertEqual(IntentText.describe(.click(elementID: "e1"), screen: screen), "Click \"Docs\"")
        XCTAssertEqual(IntentText.describe(.scroll(.down)), "Scroll down")
    }

    func testBelowLine() {
        XCTAssertTrue(IntentText.belowLine(RouteResult(intent: .back, confidence: 0.5, tier: .fuzzy, ms: 1)))
        XCTAssertFalse(IntentText.belowLine(RouteResult(intent: .back, confidence: 0.9, tier: .rules, ms: 1)))
    }
}

final class PermissionTests: XCTestCase {
    func testSettingsURLs() {
        XCTAssertEqual(Permission.accessibility.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        XCTAssertTrue(Permission.inputMonitoring.settingsURL.absoluteString.hasSuffix("Privacy_ListenEvent"))
    }

    func testCanAskNeedsUsageText() {
        XCTAssertFalse(Permissions.canAsk(.microphone, info: [:]))
        XCTAssertTrue(Permissions.canAsk(.microphone, info: ["NSMicrophoneUsageDescription": "Hear commands"]))
        XCTAssertTrue(Permissions.canAsk(.accessibility, info: [:]))
    }
}

final class KeychainTests: XCTestCase {
    func testWriteReadDelete() {
        let secret = KeychainSecret(service: "earshot-tests-\(UUID().uuidString)", account: "test")
        defer { secret.delete() }
        XCTAssertNil(secret.read())
        XCTAssertTrue(secret.write("  abc  "))
        XCTAssertEqual(secret.read(), "abc")
        XCTAssertTrue(secret.write("def"))
        XCTAssertEqual(secret.read(), "def")
        XCTAssertTrue(secret.write(""))  // An empty value removes the item.
        XCTAssertNil(secret.read())
    }
}

final class SettingsSaveTests: XCTestCase {
    func testSettingsRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(folder: folder)
        var s = EarshotSettings()
        XCTAssertEqual(s.mode, .hold)   // Always-on is off by default (R-ON-1, R-ON-4).
        XCTAssertEqual(s.tier2, .off)   // No cloud by default (R-MD-1).
        s.mode = .alwaysOn
        HoldKeys.apply(code: 58, modifiers: 0, to: &s)
        try store.save(s, "settings.json")
        XCTAssertEqual(store.settings, s)
    }
}

final class AppsFilterTests: XCTestCase {
    private let apps = [
        AppEntry(id: "a", name: "Alpha Chat", bundleID: "com.example.alphachat", aliases: ["al"], isChat: true, approved: true),
        AppEntry(id: "b", name: "Beta", bundleID: "org.beta.app", approved: false, enabled: false),
        AppEntry(id: "c", name: "Gamma Notes", bundleID: "io.gamma.notes", approved: false),
    ]

    func testSearchLooksAtNameBundleAndAliases() {
        XCTAssertEqual(CatalogueEdit.filter(apps, query: "gamma", scope: .all).map(\.id), ["c"])
        XCTAssertEqual(CatalogueEdit.filter(apps, query: "ORG.BETA", scope: .all).map(\.id), ["b"])
        XCTAssertEqual(CatalogueEdit.filter(apps, query: "al", scope: .all).map(\.id), ["a"])
        XCTAssertEqual(CatalogueEdit.filter(apps, query: "  ", scope: .all).count, 3)
    }

    func testScopes() {
        XCTAssertEqual(CatalogueEdit.filter(apps, query: "", scope: .needsApproval).map(\.id), ["b", "c"])
        XCTAssertEqual(CatalogueEdit.filter(apps, query: "", scope: .approved).map(\.id), ["a"])
        XCTAssertEqual(CatalogueEdit.filter(apps, query: "", scope: .chat).map(\.id), ["a"])
        XCTAssertEqual(CatalogueEdit.filter(apps, query: "", scope: .off).map(\.id), ["b"])
        XCTAssertEqual(CatalogueEdit.filter(apps, query: "notes", scope: .needsApproval).map(\.id), ["c"])
    }

    func testBulkSet() {
        let out = CatalogueEdit.set(\.approved, true, ids: ["b", "c"], in: apps)
        XCTAssertEqual(out.map(\.approved), [true, true, true])
        let off = CatalogueEdit.set(\.enabled, false, ids: ["a"], in: out)
        XCTAssertEqual(off.map(\.enabled), [false, false, true])
        XCTAssertEqual(off.map(\.id), ["a", "b", "c"])
    }
}

final class BrandTests: XCTestCase {
    func testMarkMatchesTheSVG() {
        // assets/brand/src/mark.svg: translate(161 180) scale(27), stroke-width 2.2.
        XCTAssertEqual(MarkShapes.origin, CGPoint(x: 161, y: 180))
        XCTAssertEqual(MarkShapes.scale, 27)
        XCTAssertEqual(MarkShapes.strokeWidth, 59.4, accuracy: 0.01)
        XCTAssertEqual(MarkShapes.strokes.count, 2)
        XCTAssertEqual(MarkShapes.strokes.map { $0.curves.count }, [6, 4])
    }

    func testMarkIsCentredInTheTile() {
        let box = MarkShapes.path().boundingRect
        XCTAssertEqual(box.midX, 512, accuracy: 4)
        XCTAssertEqual(box.midY, 512, accuracy: 4)
        // The ear stays inside the tile (100 to 924), with room for the stroke.
        let outer = box.insetBy(dx: -MarkShapes.strokeWidth / 2, dy: -MarkShapes.strokeWidth / 2)
        XCTAssertTrue(CGRect(x: 100, y: 100, width: 824, height: 824).contains(outer))
    }
}
