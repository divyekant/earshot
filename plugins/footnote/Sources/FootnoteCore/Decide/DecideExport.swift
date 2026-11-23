import Foundation

/// E13 package L1 (`/mnt/project-files/earshot-footnote-model/local-check-spec.md`): the owner's recent inbox mail
/// as an item file of the decision model, for a check on the owner's Mac.
///
/// `footnote --decide-export <file> --days 30 [--max N]`
///
/// - It reads through a `MailSource` only (read only; the Mac source uses the fixed scripts of `AppleScripts`).
/// - It writes the file with mode 0600. The ids in the file are its own (`l1-0001`), not the ids of Mail.
/// - It reads the text only of a mail that passes the bulk filter. A held mail keeps its header facts.
/// - It prints counts only: never a field of a mail.
public struct DecideExport {
    public var days: Int
    /// The most mails to look at, newest first.
    public var maxMails: Int
    public var batch = 20
    public var out: (String) -> Void = { print($0) }

    public init(days: Int, maxMails: Int = 5000) {
        self.days = days
        self.maxMails = maxMails
    }

    public struct Result: Equatable {
        public var mails = 0
        public var withText = 0
        public var failed = 0
    }

    /// The owner of the items: the setting, or the Mail accounts (as `Engine.ownerAddresses` and `ownerNames`).
    public static func owner(_ settings: FootnoteSettings, accounts: [String]) -> (name: String, addresses: [String]) {
        let addrs = (settings.owner.addresses.isEmpty ? accounts : settings.owner.addresses).map { $0.lowercased() }
        var name = settings.owner.names.joined(separator: " ")
        if name.isEmpty {
            name = addrs.flatMap { a in
                (a.split(separator: "@").first.map(String.init) ?? "").split(whereSeparator: { ".-_+".contains($0) })
                    .map { $0.lowercased() }.filter { $0.count >= 3 }
            }.joined(separator: " ")
        }
        return (name, addrs)
    }

    /// The owner address of one item. The item format has one owner address, and the bulk filter of the bench uses
    /// it: the address that sent the mail, else the first owner address in To or Cc, else the first owner address.
    static func ownerAddress(_ m: MailMessage, _ addresses: [String]) -> String {
        let from = m.fromAddress.lowercased()
        if addresses.contains(from) { return from }
        let all = Set((m.to + m.cc).map { $0.lowercased() })
        return addresses.first(where: all.contains) ?? addresses.first ?? ""
    }

    public func run(source: MailSource, ownerName: String, ownerAddresses: [String], to file: URL,
                    now: Date = Date()) throws -> Result {
        guard source.isRunning else { throw SourceError("Mail does not run") }
        let since = now.addingTimeInterval(-TimeInterval(days) * 86400)
        let iso = ISO8601DateFormatter()
        var r = Result()
        var lines: [String] = []
        var pos = 0
        var done = false
        while !done, r.mails < maxMails {
            let ids = try source.ids(from: pos, count: batch)
            if ids.isEmpty { break }
            pos += ids.count
            for id in ids {
                guard r.mails < maxMails else { done = true; break }
                guard var m = try? source.envelope(id: id) else { r.failed += 1; continue }
                if m.date < since { done = true; break }
                let own = Self.ownerAddress(m, ownerAddresses)
                if BulkFilter.reason(m, owner: Set(ownerAddresses)) == nil {
                    if let t = try? source.text(id: id) {
                        m.text = String(t.prefix(MailMessage.maxText))
                        r.withText += 1
                    } else {
                        r.failed += 1
                    }
                }
                r.mails += 1
                let obj: [String: Any] = [
                    "id": String(format: "l1-%04d", r.mails), "kind": "mail",
                    "owner": ["name": ownerName, "address": own], "now": iso.string(from: now),
                    "from_name": m.fromName, "from_address": m.fromAddress, "to": m.to, "cc": m.cc,
                    "subject": m.subject, "date": iso.string(from: m.date), "list_unsubscribe": m.listHeader,
                    "precedence": m.precedence, "auto_submitted": m.autoSubmitted, "junk": m.junk,
                    "replied": m.replied, "body": m.text,
                ]
                let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
                lines.append(String(decoding: data, as: UTF8.self))
            }
        }
        let fm = FileManager.default
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Mode 0600 from the start: the file holds the owner's mail.
        fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let h = try FileHandle(forWritingTo: file)
        try h.truncate(atOffset: 0)
        try h.write(contentsOf: Data((lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).utf8))
        try h.close()
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        out("Export: \(r.mails) mails in \(days) days, \(r.withText) with text, \(r.failed) failed reads")
        return r
    }
}
