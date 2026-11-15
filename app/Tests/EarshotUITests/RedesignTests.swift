import EarshotCore
import XCTest
@testable import EarshotUI

/// The words of the new window, panel and note (design canvas, 2026-11-15, R-FB-1). Made-up names only.
final class RecordTextTests: XCTestCase {
    private let apps = [AppEntry(id: "notes", name: "Notes", bundleID: "com.example.notes")]

    private func record(heard: String, intent: String, note: String, ok: Bool = true, tier: RouterTier = .rules) -> ActivityRecord {
        ActivityRecord(heard: heard, intent: intent, tier: tier, ok: ok, note: note, stages: ["total": 300])
    }

    func testOpenSaysWhatEarshotDidThenWhatTheOwnerSaid() {
        let line = RecordText.line(record(heard: "Open notes.", intent: "→ Notes", note: "→ Notes · route: app name · screen: com.example.notes"),
                                   apps: apps)
        XCTAssertEqual(line.title, "Opened Notes")
        XCTAssertEqual(line.detail, "“open notes” · Notes")
        XCTAssertEqual(line.tone, .done)
    }

    func testDictationKeepsOnlyTheWordCount() {
        let line = RecordText.line(record(heard: "(14 words)", intent: "Type \"(14 words)\"", note: "typed · screen: com.example.notes"),
                                   apps: apps)
        XCTAssertEqual(line.title, "Typed 14 words")
        XCTAssertEqual(line.detail, "in Notes")
        XCTAssertEqual(line.glyph, .typed)
    }

    func testFailedClickNamesTheLabel() {
        let line = RecordText.line(record(heard: "click lights", intent: "Click \"Lights\"", note: "did not find it: x", ok: false))
        XCTAssertEqual(line.title, "Did not find “Lights”")
        XCTAssertEqual(line.tone, .failed)
    }

    func testNotSureIsAQuestion() {
        let line = RecordText.line(record(heard: "open no", intent: "none", note: "not sure: two apps are close · 1: Notes · 2: Notion · say one"))
        XCTAssertEqual(line.title, "Asked you: Notes or Notion?")
        XCTAssertEqual(line.tone, .asked)
    }

    func testPluginHandOff() {
        let line = RecordText.line(record(heard: "todo call the shop", intent: "Planner · todo", note: "sent to Planner"))
        XCTAssertEqual(line.title, "Handed to Planner")
        XCTAssertEqual(line.glyph, .plugin)
    }
}

final class NoteContentTests: XCTestCase {
    func testDoneNoteIsAPillWithNoArrow() {
        XCTAssertEqual(NoteContent.parse("→ Notes", ok: true), .pill(glyph: .open, text: "Notes", aside: "", failed: false))
    }

    func testFailedNoteKeepsTheReasonOnly() {
        XCTAssertEqual(NoteContent.parse("✗ the search field did not show in 1200 ms: x", ok: false),
                       .pill(glyph: .failed, text: "The search field did not show in 1200 ms", aside: "", failed: true))
    }

    func testNotSureIsACard() {
        XCTAssertEqual(NoteContent.parse("not sure: two apps are close · 1: Notes · 2: Notion", ok: false),
                       .question(title: "Not sure", question: "Two apps are close", choices: ["Notes", "Notion"],
                                 hint: "Say “the first one”, “the second one” or “no”."))
    }

    func testPluginAnswer() {
        XCTAssertEqual(NoteContent.answer(from: "Planner", text: "Done."), .pill(glyph: .plugin, text: "Done.", aside: "Planner", failed: false))
        let card = NoteContent.answer(from: "Planner", text: "Due today\n1. Call the shop · 5 pm\n2. Pay the rent · Wed (late)")
        XCTAssertEqual(card, .answer(from: "Planner", text: "Due today", items: [
            NoteContent.AnswerItem(text: "Call the shop", when: "5 pm", late: false),
            NoteContent.AnswerItem(text: "Pay the rent", when: "Wed", late: true),
        ]))
    }
}

final class LiveStateTests: XCTestCase {
    func testHeaderAndChip() {
        let ready = LiveState(holdKey: "⌥ right")
        XCTAssertEqual(ready.header, LiveState.Header(title: "Ready", before: "Hold", key: "⌥ right", after: "and speak"))
        XCTAssertEqual(ready.chip.state, "Ready")
        XCTAssertEqual(ready.chip.key, "⌥")
        var needs = ready
        needs.needsYou = true
        XCTAssertEqual(needs.chip.state, "Needs you")
        XCTAssertEqual(needs.orb, .needsYou)
        var paused = ready
        paused.listen = .paused
        XCTAssertEqual(paused.header.title, "Paused")
    }

    func testHoldKeyWords() {
        XCTAssertEqual(HoldKeys.capText("Right Option"), "⌥ right")
        XCTAssertEqual(HoldKeys.capText("Control + F5"), "Control + F5")
        XCTAssertEqual(LiveState.holdWords("⌥ right"), "the right ⌥ key")
        XCTAssertEqual(LiveState.holdWords("fn"), "the fn key")
        XCTAssertEqual(LiveState.holdWords("F5"), "F5")
    }

    func testPanelTimeAndMarks() {
        let now = Date()
        XCTAssertTrue(MenuPanel.time(now, now: now).contains(":"))
        let earlier = now.addingTimeInterval(-3 * 86_400)
        XCTAssertEqual(MenuPanel.time(earlier, now: now), earlier.formatted(.dateTime.weekday(.abbreviated)))
        let old = now.addingTimeInterval(-20 * 86_400)
        XCTAssertEqual(MenuPanel.time(old, now: now), old.formatted(.dateTime.day().month(.abbreviated)))
        guard case .todo(late: true) = MenuPanel.mark(Board.Row(text: "Pay", late: true, mark: "todo")) else {
            return XCTFail("a late to-do is a coral circle")
        }
        guard case .glyph(.typed, _) = MenuPanel.mark(Board.Row(text: "Tiler", mark: "note")) else {
            return XCTFail("a note has the note glyph")
        }
    }

    func testShortcutCaps() {
        XCTAssertEqual(ShortcutCaps.caps("cmd+k"), ["⌘", "K"])
        XCTAssertEqual(ShortcutCaps.caps("cmd+shift+k"), ["⇧", "⌘", "K"])
        XCTAssertEqual(ShortcutCaps.caps("ctrl+opt+return"), ["⌃", "⌥", "↩"])
    }
}

final class PageWordsTests: XCTestCase {
    func testSay() {
        XCTAssertEqual(AppWords.say([]), "")
        XCTAssertEqual(AppWords.say(["slack"]), "“slack”")
        XCTAssertEqual(AppWords.say(["a", "b", "c", "d"]), "“a”, “b” or “c”")
    }

    func testAppDetail() {  // R-MT-2
        let chat = AppEntry(id: "chat", name: "Chat", bundleID: "com.example.chat", aliases: ["chat"], isChat: true,
                            openChat: .switcher(keys: "cmd+k"), approved: true)
        XCTAssertEqual(AppWords.detail(chat, names: 46), "Chats · 46 people and channels · say “chat”")
        var new = chat
        new.approved = false
        XCTAssertEqual(AppWords.detail(new, names: 0), "New · has chats")
        var off = chat
        off.enabled = false
        XCTAssertEqual(AppWords.detail(off, names: 3), "Off · earshot does nothing in this app")
    }

    func testNamesOwnChatFirst() {
        let names = [NameEntry(appID: "a", name: "Zed", source: .sidebar), NameEntry(appID: "a", name: "Amy", source: .sidebar),
                     NameEntry(appID: "a", name: "Notes to self", isSelf: true, source: .sidebar),
                     NameEntry(appID: "a", name: "Kim", source: .manual), NameEntry(appID: "b", name: "Other", source: .sidebar)]
        XCTAssertEqual(AppWords.sorted(names, appID: "a").map(\.name), ["Notes to self", "Kim", "Amy", "Zed"])
    }

    func testPluginWords() {  // R-PL-4
        XCTAssertEqual(PluginWords.settingsSummary(values: ["alert", "alert", "list", "off", "alert", "alert"], noun: "Rules"),
                       "6 rules: 4 alert, 1 list, 1 off")
        let m = PluginManifest(id: "planner", name: "Planner", leads: ["todo"], context: ["app", "url", "selection"], run: ["./p"])
        let gets = PluginWords.gets(m)
        XCTAssertEqual(gets.map { $0.text }, ["The words after its lead word", "The front app and the page address",
                                          "The text that you selected",
                                          "No network. Planner says so in its file; earshot does not check it."])
        XCTAssertEqual(gets[2].tone, .amber)
        XCTAssertEqual(PluginWords.getsShort(m), "Words, front window, selected text")
        let now = Date()
        let records = [ActivityRecord(heard: "todo x", intent: "Planner · todo", tier: .rules, ok: true, note: "sent to Planner", stages: [:]),
                       ActivityRecord(heard: "open notes", intent: "Notes", tier: .rules, ok: true, note: "", stages: [:])]
        XCTAssertEqual(PluginWords.today(records, name: "Planner", now: now), 1)
    }

    func testSystemWords() {
        var states: [Permission: PermissionState] = [:]
        for p in Permission.allCases { states[p] = .granted }
        XCTAssertEqual(SystemWords.accessLine(states), "All 5 allowed")
        states[.screenRecording] = .denied
        XCTAssertEqual(SystemWords.accessLine(states), "4 of 5 allowed · the fifth is optional")
        states[.microphone] = .denied
        XCTAssertEqual(SystemWords.accessLine(states), "3 of 5 allowed")
        states[.microphone] = .granted
        states[.speech] = .notAsked
        XCTAssertEqual(SystemWords.accessLine(states, newSpeech: false), "3 of 5 allowed")
        XCTAssertEqual(SystemWords.accessLine(states, newSpeech: true), "3 of 5 allowed · the others are optional")
        XCTAssertTrue(SystemWords.optional(.speech, newSpeech: true))
        XCTAssertFalse(SystemWords.optional(.speech, newSpeech: false))
        let apps = [AppEntry(id: "notes", name: "Notes", bundleID: "n"), AppEntry(id: "notion", name: "Notion", bundleID: "o")]
        let unsure = TestReport(heard: "open no", route: RouteResult(intent: .openApp(appID: "notes"), confidence: 0.54, tier: .fuzzy,
                                                                    ms: 6, alternatives: [.openApp(appID: "notion")]))
        XCTAssertEqual(SystemWords.answer(unsure, apps: apps).title, "earshot would ask: open Notes or open Notion?")
        let sure = TestReport(heard: "open notes", route: RouteResult(intent: .openApp(appID: "notes"), confidence: 0.95, tier: .rules, ms: 2))
        XCTAssertEqual(SystemWords.answer(sure, apps: apps).title, "earshot would open Notes")
        XCTAssertEqual(SystemWords.tier(.fuzzy), "close match")
    }
}

final class BoardTests: XCTestCase {
    func testReadCutsTheLists() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rows = (0..<300).map { Board.Row(text: "Row \($0)") }
        let tabs = (0..<10).map { Board.Tab(id: "t\($0)", title: "T\($0)", sections: [Board.Section(rows: rows)]) }
        let board = Board(panel: Board.PanelList(title: "Today", rows: rows), tabs: tabs, settingsTab: "Rules")
        try JSONEncoder().encode(board).write(to: folder.appendingPathComponent(Board.fileName))
        let read = try XCTUnwrap(Board.read(folder: folder))
        XCTAssertEqual(read.tabs.count, Board.maxTabs)
        XCTAssertEqual(read.tabs[0].sections[0].rows?.count, Board.maxRows)
        XCTAssertEqual(read.panel?.rows.count, 6)
        XCTAssertEqual(read.settingsTab, "Rules")
    }

    func testOtherVersionIsNotRead() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(#"{"version": 2, "tabs": []}"#.utf8).write(to: folder.appendingPathComponent(Board.fileName))
        XCTAssertNil(Board.read(folder: folder))
        try Data("not json".utf8).write(to: folder.appendingPathComponent(Board.fileName))
        XCTAssertNil(Board.read(folder: folder))
    }
}
