import XCTest
@testable import FootnoteCore

/// E13 package L1: the export of recent mail for the local check. Read only, mode 0600, counts only in the output.
final class DecideExportTests: XCTestCase {
    func mail(_ id: String, daysAgo: Double, list: Bool = false, to: [String] = ["ana.lim@example.com"],
              from: String = "sam.lee@example.org", now: Date) -> MailMessage {
        MailMessage(id: id, messageID: "<\(id)@x.example>", fromName: "Sam Lee", fromAddress: from, to: to, cc: [],
                    subject: "Secret subject \(id)", date: now.addingTimeInterval(-daysAgo * 86400), listHeader: list,
                    text: "Could you send the form by Friday? \(id)")
    }

    func testExportWritesRecentMailWithOwnIdsAndPrintsCountsOnly() throws {
        let now = ISO8601DateFormatter().date(from: "2026-11-23T08:00:00Z")!
        let src = FixtureMail(messages: [
            mail("a", daysAgo: 1, now: now),
            mail("b", daysAgo: 2, list: true, now: now),
            mail("c", daysAgo: 3, to: ["ana@work.example.net"], now: now),
            mail("d", daysAgo: 40, now: now),
        ], owner: ["ana.lim@example.com", "ana@work.example.net"])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("l1-export.jsonl")
        var printed: [String] = []
        var ex = DecideExport(days: 30)
        ex.batch = 2
        ex.out = { printed.append($0) }
        let r = try ex.run(source: src, ownerName: "ana lim", ownerAddresses: ["ana.lim@example.com", "ana@work.example.net"],
                           to: file, now: now)
        XCTAssertEqual(r, DecideExport.Result(mails: 3, withText: 2, failed: 0))
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let items = try DecideBench.read(file)
        XCTAssertEqual(items.map(\.m.id), ["l1-0001", "l1-0002", "l1-0003"])
        XCTAssertFalse(items[0].m.text.isEmpty)
        // A mail that the bulk filter holds keeps no text.
        XCTAssertTrue(items[1].m.text.isEmpty)
        XCTAssertEqual(items[2].ownerAddress, "ana@work.example.net")
        XCTAssertEqual(printed.count, 1)
        XCTAssertFalse(printed[0].contains("Secret"))
        XCTAssertFalse(printed[0].contains("form"))
        XCTAssertFalse(printed[0].contains("example"))
    }

    func testOwnerFromAccountsWhenTheSettingIsEmpty() {
        let o = DecideExport.owner(FootnoteSettings(), accounts: ["Maya.Rao@example.com"])
        XCTAssertEqual(o.addresses, ["maya.rao@example.com"])
        XCTAssertEqual(o.name, "maya rao")
    }
}
