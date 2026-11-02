import EarshotCore
import XCTest
@testable import EarshotDiscovery

final class MenuRulesTests: XCTestCase {
    private func s(_ path: String, _ keys: String) -> MenuShortcut {
        MenuShortcut(path: path.components(separatedBy: " > "), keys: keys)
    }

    func testSwitcherWinsOverSearch() {
        let g = MenuRules.guess([s("Edit > Find > Find...", "cmd+f"), s("Go > Switch to Channel", "cmd+k")])
        XCTAssertEqual(g?.keys, "cmd+k")
        XCTAssertEqual(g?.rule, .switchTo)
        XCTAssertEqual(g?.opensChat, true)
    }

    func testNewMessageRule() {
        let g = MenuRules.guess([s("File > New Message", "cmd+n"), s("Edit > Find > Find...", "cmd+f")])
        XCTAssertEqual(g?.rule, .newMessage)
        XCTAssertEqual(g?.keys, "cmd+n")
    }

    func testSearchAloneIsNotAChatApp() {
        let g = MenuRules.guess([s("Edit > Find > Find...", "cmd+f")])
        XCTAssertEqual(g?.rule, .search)
        XCTAssertEqual(g?.opensChat, false)
        let row = MenuRules.entry(name: "Safari", bundleID: "b.safari", shortcuts: [s("Edit > Find > Find...", "cmd+f")], electron: false)
        XCTAssertFalse(row.isChat)
        XCTAssertEqual(row.openChat, OpenChat.none)
        XCTAssertTrue(row.approved)
    }

    func testWholeWordsAppleMenuExcludedAndReturn() {
        // "find" must not match "Finder". The Apple menu does not count.
        XCTAssertNil(MenuRules.guess([s("Window > Open Finder", "cmd+opt+f")]))
        XCTAssertNil(MenuRules.guess([s("Apple > Search", "cmd+space")]))
        XCTAssertNil(MenuRules.guess([s("Edit > Find > Find Next", "cmd+g")]))
        XCTAssertNil(MenuRules.guess([s("Chat > Jump to End", "opt+down")]))
        // A shortcut with Return can send a message. It never counts.
        XCTAssertNil(MenuRules.guess([s("File > New Message", "cmd+return")]))
        XCTAssertNil(MenuRules.guess([s("File > New Chat", "key code 99")]))
    }

    func testShortcutText() {
        XCTAssertEqual(MenuRules.shortcutText(char: "K", modifiers: 0, keyCode: nil), "cmd+k")
        XCTAssertEqual(MenuRules.shortcutText(char: "n", modifiers: 1, keyCode: nil), "shift+cmd+n")
        XCTAssertEqual(MenuRules.shortcutText(char: "e", modifiers: 6, keyCode: nil), "ctrl+opt+cmd+e")
        XCTAssertEqual(MenuRules.shortcutText(char: "\r", modifiers: 0, keyCode: nil), "cmd+return")
        XCTAssertEqual(MenuRules.shortcutText(char: "k", modifiers: 8, keyCode: nil), "k")
    }

    func testAliases() {
        XCTAssertEqual(MenuRules.aliases(for: "Google Chrome"), ["google chrome", "chrome"])
        XCTAssertEqual(MenuRules.aliases(for: "Sublime Text"), ["sublime text"])
        XCTAssertEqual(MenuRules.aliases(for: "Messages", extra: ["Messages", "iMessage"]), ["messages", "imessage"])
    }

    func testChatRowNeedsApproval() {
        let row = MenuRules.entry(name: "Chat App", bundleID: "x.chat", shortcuts: [s("Go > Jump to...", "cmd+k")], electron: true)
        XCTAssertEqual(row.id, "chatapp")
        XCTAssertTrue(row.isChat)
        XCTAssertEqual(row.openChat, .switcher(keys: "cmd+k"))
        XCTAssertFalse(row.approved)
        XCTAssertTrue(row.electron)
    }

    func testMergeKeepsOwnerChoices() {
        var approved = AppEntry(id: "a", name: "A", bundleID: "x.a", aliases: ["my a"], isChat: true,
                                openChat: .switcher(keys: "cmd+j"), approved: true)
        approved.enabled = true
        var off = AppEntry(id: "b", name: "B", bundleID: "x.b", isChat: true, openChat: .switcher(keys: "cmd+k"))
        off.enabled = false
        let chatC = AppEntry(id: "c", name: "C", bundleID: "x.c", isChat: true, openChat: .switcher(keys: "cmd+k"))
        let found = [
            AppEntry(id: "a", name: "A", bundleID: "x.a", isChat: true, openChat: .switcher(keys: "cmd+k")),
            AppEntry(id: "b", name: "B", bundleID: "x.b", isChat: true, openChat: .switcher(keys: "cmd+t")),
            AppEntry(id: "c", name: "C", bundleID: "x.c", approved: true),  // installed only: less data
            AppEntry(id: "a", name: "A", bundleID: "y.other", approved: true),  // same id, other app
        ]
        let out = MenuRules.merge(existing: [approved, off, chatC], found: found)
        XCTAssertEqual(out.first { $0.bundleID == "x.a" }, approved)
        let b = out.first { $0.bundleID == "x.b" }
        XCTAssertEqual(b?.openChat, .switcher(keys: "cmd+t"))
        XCTAssertEqual(b?.enabled, false)
        XCTAssertEqual(out.first { $0.bundleID == "x.c" }, chatC)
        XCTAssertEqual(out.first { $0.bundleID == "y.other" }?.id, "a2")
        XCTAssertEqual(out.count, 4)
    }
}

final class CatalogueSafetyTests: XCTestCase {
    func testApprovedRowGainsChatKeysAndKeepsApproval() {
        // Seen live: the owner approved Slack while Accessibility was off, so the row had no chat keys.
        let old = AppEntry(id: "slack", name: "Slack", bundleID: "x.slack", aliases: ["slack", "work chat"], approved: true,
                           enabled: true)
        let new = AppEntry(id: "slack", name: "Slack", bundleID: "x.slack", aliases: ["slack"], isChat: true,
                           openChat: .switcher(keys: "cmd+k"))
        let row = MenuRules.merge(existing: [old], found: [new]).first
        XCTAssertEqual(row?.isChat, true)
        XCTAssertEqual(row?.openChat, .switcher(keys: "cmd+k"))
        XCTAssertEqual(row?.approved, true)
        XCTAssertEqual(row?.aliases, ["slack", "work chat"])
        // A row that the owner did not approve still needs approval.
        let fresh = MenuRules.merge(existing: [AppEntry(id: "slack", name: "Slack", bundleID: "x.slack")], found: [new]).first
        XCTAssertEqual(fresh?.approved, false)
    }

    func testNoScanAndNoSaveWithoutAccessibility() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("earshot-t4-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(folder: folder)
        let catalogue = MenuCatalogue(skip: [], includeInstalled: true, trusted: { false })
        let rows = await catalogue.discover()
        XCTAssertEqual(rows, [])
        do {
            try await catalogue.refresh(store: store)
            XCTFail("refresh must throw")
        } catch {
            XCTAssertEqual(error as? DiscoveryError, .accessibilityOff)
            XCTAssertEqual(error.localizedDescription, "Turn on Accessibility for earshot first")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("apps.json").path))
    }
}

final class DeclaredNamesTests: XCTestCase {
    func testSchemesFromInfoPlist() {
        // A fake Info.plist of a messages app. No real app name is needed for the rule.
        let info: [String: Any] = [
            "CFBundleName": "Chatter",
            "CFBundleURLTypes": [
                ["CFBundleURLSchemes": ["imessage", "sms", "im"]],
                ["CFBundleURLSchemes": ["https", "mailto", "x-chatter", "chatter2", "message", "Chatter"]],
            ],
        ]
        // "imessage" shares "message" with the app name. "sms" shares no word with it.
        XCTAssertEqual(MenuRules.declaredNames(info, appName: "Messages"), ["Chatter", "imessage"])
        XCTAssertEqual(MenuRules.declaredNames([:]), [])
        let row = MenuRules.entry(name: "Messages", bundleID: "x.m",
                                  extraNames: MenuRules.declaredNames(info, appName: "Messages"), shortcuts: nil, electron: false)
        XCTAssertEqual(row.aliases, ["messages", "chatter", "imessage"])
        // Seen live: apps also declare schemes of other products ("upi", "codex"). They share no word with the name.
        let other: [String: Any] = ["CFBundleName": "Talk Pad",
                                    "CFBundleURLTypes": [["CFBundleURLSchemes": ["upi", "codex", "talkpad", "talk"]]]]
        XCTAssertEqual(MenuRules.declaredNames(other, appName: "TalkPad"), ["Talk Pad", "talkpad", "talk"])
    }

    func testNewAliasesJoinOwnerRows() {
        let owner = AppEntry(id: "messages", name: "My Messages", bundleID: "x.m", aliases: ["messages", "texts"],
                             isChat: true, openChat: .switcher(keys: "cmd+n"), approved: true, enabled: false)
        let found = AppEntry(id: "messages", name: "Messages", bundleID: "x.m", aliases: ["messages", "imessage"],
                             isChat: true, openChat: .switcher(keys: "cmd+n"))
        let row = MenuRules.merge(existing: [owner], found: [found]).first
        XCTAssertEqual(row?.aliases, ["messages", "texts", "imessage"])
        XCTAssertEqual(row?.approved, true)
        XCTAssertEqual(row?.enabled, false)
        XCTAssertEqual(row?.name, "My Messages")
        // An installed-only scan (less data) also adds its names, and keeps the chat keys.
        let installed = AppEntry(id: "messages", name: "Messages", bundleID: "x.m", aliases: ["sms"], approved: true)
        let row2 = MenuRules.merge(existing: [owner], found: [installed]).first
        XCTAssertEqual(row2?.aliases, ["messages", "texts", "sms"])
        XCTAssertEqual(row2?.isChat, true)
    }
}

final class NameRulesTests: XCTestCase {
    func testClean() {
        XCTAssertEqual(NameRules.clean("Ravi Kumar (you)")?.name, "Ravi Kumar")
        XCTAssertEqual(NameRules.clean("Ravi Kumar (you)")?.isSelf, true)
        XCTAssertEqual(NameRules.clean("Prakash\u{200E} Iyer")?.name, "Prakash Iyer")
        for label in ["10:42", "9.30 PM", "12/10/26", "3m", "2 new", "Threads", "Direct messages", "Monday",
                      "New Message to Ravi", "Loading…", "Manel & +1 (415) 555 0100", "x"] {
            XCTAssertNil(NameRules.clean(label), label)
        }
    }

    func testPlaceholderAliases() {
        XCTAssertEqual(NameRules.placeholderAliases("Text Message • iMessage"), ["imessage"])
        XCTAssertEqual(NameRules.placeholderAliases("Message Ravi"), [])
        XCTAssertEqual(NameRules.placeholderAliases(nil), [])
    }

    func testResultLineFilters() {
        XCTAssertNil(NameRules.cleanResultLine("Show results for: ravi", appName: "Chat"))
        XCTAssertNil(NameRules.cleanResultLine("notes_2026.pdf", appName: "Chat"))
        // Seen in Slack: a file result with more text after the file name.
        XCTAssertNil(NameRules.cleanResultLine("teamgithubsetup.md, 2 KB", appName: "Chat"))
        XCTAssertNil(NameRules.cleanResultLine("TEAM_DESKTOP_SETUP.md Shared", appName: "Chat"))
        XCTAssertEqual(NameRules.cleanResultLine("Dr. Ravi", appName: "Chat"), "Dr. Ravi")
        // A user handle is not a file name. It is removed from the name.
        XCTAssertEqual(NameRules.cleanResultLine("Prakash Iyer prakash.iyer", appName: "Chat"), "Prakash Iyer")
        XCTAssertEqual(NameRules.cleanResultLine("Ravi @ravi", appName: "Chat"), "Ravi")
        XCTAssertNil(NameRules.cleanResultLine("https://example.com", appName: "Chat"))
        XCTAssertNil(NameRules.cleanResultLine("Connect your tools to this place", appName: "Chat"))
        XCTAssertNil(NameRules.cleanResultLine("Chat Connect", appName: "Chat"))
        XCTAssertNil(NameRules.cleanResultLine("SIRI FOUND IN", appName: "Chat"))
        XCTAssertEqual(NameRules.cleanResultLine("Ravi Kumar • Today", appName: "Chat"), "Ravi Kumar")
        XCTAssertEqual(NameRules.cleanResultLine("O&#39;Neil", appName: "Chat"), "O'Neil")
    }

    func testResultsDropEchoAndMessageHits() {
        let lines = [ResultLine("ravi"), ResultLine("Ravi Kumar • Today"), ResultLine("Ravi Shankar", inRow: true),
                     ResultLine("Recent messages"), ResultLine("Ravana")]
        XCTAssertEqual(NameRules.results(lines, term: "ravi", appName: "Chat"), ["Ravi Shankar", "Ravi Kumar"])
        // The echo stays if it is a row of its own: a chat can have exactly the typed name.
        XCTAssertEqual(NameRules.results([ResultLine("Ravi", inRow: true)], term: "ravi", appName: "Chat"), ["Ravi"])
        XCTAssertTrue(NameRules.isMessageSection("Messages in #general"))
        XCTAssertFalse(NameRules.isMessageSection("Messaging team"))
    }

    func testPreferRows() {
        let names = [SidebarName(name: "Threads", fromRow: false), SidebarName(name: "Ravi", fromRow: true)]
        XCTAssertEqual(NameRules.preferRows(names).map(\.name), ["Ravi"])
        XCTAssertEqual(NameRules.preferRows([names[0]]).map(\.name), ["Threads"])
    }

    func testSettleCheck() {
        let two = [SidebarName(name: "A", fromRow: true), SidebarName(name: "B", fromRow: true)]
        var c = SettleCheck()
        XCTAssertFalse(c.add([two[0]], loading: false))
        XCTAssertFalse(c.add(two, loading: false))
        XCTAssertTrue(c.add(two, loading: false))
        XCTAssertEqual(c.kept.count, 2)
        XCTAssertEqual(c.reads, 3)

        // An app with no list stops after 3 reads.
        var empty = SettleCheck()
        XCTAssertFalse(empty.add([], loading: false))
        XCTAssertFalse(empty.add([], loading: false))
        XCTAssertTrue(empty.add([], loading: false))

        // A list that still loads goes on, up to 8 reads.
        var loading = SettleCheck()
        var stops = 0
        for _ in 0..<SettleCheck.maxReads where !loading.add(two, loading: true) { stops += 1 }
        XCTAssertEqual(stops, SettleCheck.maxReads - 1)
        XCTAssertTrue(loading.stillLoading)
    }
}

final class NameMergeTests: XCTestCase {
    func testManualWinsAndAliasesJoin() {
        let out = NameMerge.merge([
            [NameEntry(appID: "a", name: "Ravi K", aliases: ["rk"], source: .sidebar)],
            [NameEntry(appID: "a", name: "ravi k", aliases: ["ravi"], isSelf: true, source: .manual)],
            [NameEntry(appID: "b", name: "Ravi K", source: .contacts)],
        ])
        XCTAssertEqual(out.count, 2)
        let a = out.first { $0.appID == "a" }
        XCTAssertEqual(a?.source, .manual)
        XCTAssertEqual(a?.name, "ravi k")
        XCTAssertEqual(a?.isSelf, true)
        XCTAssertEqual(Set(a?.aliases ?? []), ["rk", "ravi"])
    }

    func testContactEntry() {
        let e = NameMerge.contactEntry(appID: "m", given: "Mrunal", family: "Sen", nickname: "Minu", organization: "")
        XCTAssertEqual(e?.name, "Mrunal Sen")
        XCTAssertEqual(e?.aliases, ["mrunal", "minu"])
        XCTAssertEqual(e?.source, .contacts)
        XCTAssertEqual(NameMerge.contactEntry(appID: "m", given: "", family: "", nickname: "", organization: "Acme Labs")?.name,
                       "Acme Labs")
        XCTAssertNil(NameMerge.contactEntry(appID: "m", given: "", family: "", nickname: "", organization: ""))
    }
}

final class SearchSafetyTests: XCTestCase {
    func testKeysHaveNoReturn() {
        XCTAssertNotNil(SearchKeys.parse("cmd+k"))
        XCTAssertNotNil(SearchKeys.parse("shift+cmd+n"))
        XCTAssertNil(SearchKeys.parse("cmd+return"))
        XCTAssertNil(SearchKeys.parse("enter"))
        XCTAssertNil(SearchKeys.parse("cmd+k+j"))
        XCTAssertFalse(SearchKeys.codes.keys.contains("return"))
        XCTAssertEqual(Words.printable("Ravi\n\r\t"), "Ravi")
    }

    func testJoinLines() {
        let lines = SearchReader.joinLines([("Iyer", 60, 100, 16, true), ("Prakash", 10, 101, 16, false),
                                            ("Udita", 10, 140, 16, false)])
        XCTAssertEqual(lines, [ResultLine("Prakash Iyer", inRow: true), ResultLine("Udita")])
    }
}

/// Live reads on the Mac. They run only with EARSHOT_LIVE_DISCOVERY set, and need the Accessibility permission.
/// "read" reads menu bars and sidebars only: it presses nothing.
/// "search" also types EARSHOT_SEARCH_TERM into the search of EARSHOT_SEARCH_APP. It never presses Return.
final class LiveDiscoveryTests: XCTestCase {
    private var mode: String { ProcessInfo.processInfo.environment["EARSHOT_LIVE_DISCOVERY"] ?? "" }

    func testLiveRead() async throws {
        try XCTSkipUnless(mode == "read" || mode == "search", "set EARSHOT_LIVE_DISCOVERY=read")
        try XCTSkipUnless(AX.trusted(), "Accessibility is off for this process")
        let catalogue = MenuCatalogue()
        let rows = await catalogue.discover()
        print("LIVE catalogue: \(rows.count) rows, \(catalogue.lastReads.count) running apps read in \(Int(catalogue.lastMs)) ms")
        let times = catalogue.lastReads.map(\.ms).sorted()
        if !times.isEmpty { print("LIVE menu read per app: median \(Int(times[times.count / 2])) ms, max \(Int(times.last!)) ms") }
        for row in rows where row.isChat { print("LIVE   \(row.name) aliases: \(row.aliases.joined(separator: ", "))") }
        for r in catalogue.lastReads where r.timedOut || r.ms > 1000 {
            print("LIVE   SLOW menu read: \(r.name) \(Int(r.ms)) ms, stopped at the limit: \(r.timedOut)")
        }
        for r in catalogue.lastReads where r.guess != nil {
            print("LIVE   \(r.name): \(r.guess!.rule.rawValue) \(r.guess!.keys) (\(r.guess!.menuPath)), \(r.shortcuts) shortcuts, \(Int(r.ms)) ms")
        }
        let chat = rows.filter(\.isChat).map { var e = $0; e.approved = true; return e }
        let front = ProcessInfo.processInfo.environment["EARSHOT_LIVE_FRONT"] == "1"
        let index = NameIndex(apps: { chat })
        await index.setReadInFront(front)
        await index.refresh()
        print("LIVE sidebar read with apps in front: \(front)")
        for app in chat {
            let names = await index.names(appID: app.id)
            let scan = await index.lastScans[app.id]
            print("LIVE   \(app.name) sidebar: \(names.filter { $0.source == .sidebar }.count) names, self \(names.contains(where: \.isSelf)), "
                  + "one read \(Int(scan?.readMs ?? 0)) ms, settled \(Int(scan?.settleMs ?? 0)) ms in \(scan?.reads ?? 0) reads, "
                  + "\(scan?.windows ?? 0) windows, \(scan?.nodes ?? 0) nodes")
        }
    }

    func testLiveSearch() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(mode == "search", "set EARSHOT_LIVE_DISCOVERY=search")
        guard let appName = env["EARSHOT_SEARCH_APP"], let terms = env["EARSHOT_SEARCH_TERM"] else {
            throw XCTSkip("set EARSHOT_SEARCH_APP and EARSHOT_SEARCH_TERM")
        }
        let rows = await MenuCatalogue(includeInstalled: false).discover()
        guard var app = rows.first(where: { $0.isChat && ($0.id == Words.key(appName) || $0.name == appName) }) else {
            throw XCTSkip("\(appName) is not a running chat app")
        }
        app.approved = true
        let fixed = app
        let index = NameIndex(apps: { return [fixed] })
        for term in terms.split(separator: ",").map(String.init) {
            let found = await index.search(appID: app.id, term: term)
            let scan = await index.lastSearch
            print("LIVE search \(app.name) \"\(term)\": \(found.count) names in \(Int(scan?.resultsMs ?? 0)) ms, typed \(Int(scan?.typedMs ?? 0)) ms, "
                  + "closed \(scan?.closed ?? false)\(scan?.failure.map { ", FAILED: \($0)" } ?? ""): "
                  + found.prefix(5).map(\.name).joined(separator: " | "))
            for line in scan?.rawLines ?? [] { print("LIVE     raw: \(line)") }
            XCTAssertEqual(scan?.closed, true)
            try await Task.sleep(nanoseconds: 400_000_000)
        }
    }
}
