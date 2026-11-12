#if os(macOS)
import AppKit
import Foundation
import PACore

/// The mail source of the Mac (spec 6.1, 7.4): the Mail app through Apple events, one small event at a time, with a
/// pause of 200 ms or more between two events. Read only: the scripts are in `AppleScripts` and a test bans the
/// words of a change. The PA never starts Mail: if Mail does not run, `isRunning` is false and the PA does not read.
public final class AppleMail: MailSource {
    static let bundleID = "com.apple.mail"
    public static let pause: TimeInterval = 0.2
    var lastEvent: Date?
    /// The position of each id in the inbox at the last read of ids (1 is the newest).
    var positions: [String: Int] = [:]

    public init() {}

    public var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty }

    public var isFront: Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.bundleID }

    /// Runs one script after the pause. Throws if Mail does not run or the script fails.
    func event(_ script: String) throws -> NSAppleEventDescriptor {
        guard isRunning else { throw SourceError("Mail does not run") }
        if let last = lastEvent {
            let wait = Self.pause - Date().timeIntervalSince(last)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        }
        defer { lastEvent = Date() }
        let (out, _, code) = SourceProbe.run(script)
        if let code { throw SourceError("Apple event error \(code)") }
        guard let out else { throw SourceError("no answer") }
        return out
    }

    static func strings(_ d: NSAppleEventDescriptor?) -> [String] {
        guard let d else { return [] }
        if d.numberOfItems == 0 { return d.stringValue.map { [$0] } ?? [] }
        return (1...d.numberOfItems).compactMap { d.atIndex($0)?.stringValue }
    }

    public func ids(from: Int, count: Int) throws -> [String] {
        let a = from + 1, b = from + max(1, count)
        var list: [String]
        do {
            list = Self.strings(try event(AppleScripts.range(AppleScripts.mailIDsRange, a, b)))
        } catch {
            // B is after the last message: read the count, then the rest.
            let n = Int(try event(AppleScripts.mailInboxCount).int32Value)
            guard a <= n else { return [] }
            list = Self.strings(try event(AppleScripts.range(AppleScripts.mailIDsRange, a, min(b, n))))
        }
        for (i, id) in list.enumerated() { positions[id] = a + i }
        return list
    }

    /// The position of an id now. New mail can move it down: then look in the next places.
    func position(of id: String) throws -> Int {
        guard let p = positions[id] else { throw SourceError("unknown id") }
        let first = Self.strings(try event(AppleScripts.limited(AppleScripts.mailIDOne, p))).first
        if first == id { return p }
        let found = try ids(from: p - 1, count: 10)
        guard let i = found.firstIndex(of: id) else { throw SourceError("message moved") }
        return p + i
    }

    /// "Sam Lee <sam.lee@example.net>" gives the name and the address.
    static func from(_ line: String) -> (String, String) {
        guard let lt = line.lastIndex(of: "<"), let gt = line.lastIndex(of: ">"), lt < gt else {
            return ("", line.trimmingCharacters(in: .whitespaces))
        }
        let name = line[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        return (name, String(line[line.index(after: lt)..<gt]))
    }

    public func envelope(id: String) throws -> MailMessage {
        let p = try position(of: id)
        let d = try event(AppleScripts.limited(AppleScripts.mailEnvelopeOne, p))
        guard d.numberOfItems >= 12, d.atIndex(1)?.stringValue == id else { throw SourceError("message moved") }
        let fromLine = Self.strings(d.atIndex(9)).first ?? ""
        let (name, address) = Self.from(fromLine)
        let headerNames = Set(Self.strings(d.atIndex(10)).map { $0.lowercased() })
        let auto = (Self.strings(d.atIndex(12)).first ?? "no").lowercased()
        return MailMessage(
            id: id, messageID: d.atIndex(2)?.stringValue ?? "", fromName: name, fromAddress: address,
            to: Self.strings(d.atIndex(7)), cc: Self.strings(d.atIndex(8)), subject: d.atIndex(3)?.stringValue ?? "",
            date: d.atIndex(4)?.dateValue ?? Date(), listHeader: headerNames.contains("list-unsubscribe") || headerNames.contains("list-id"),
            precedence: (Self.strings(d.atIndex(11)).first ?? "").lowercased(),
            autoSubmitted: !(auto.trimmingCharacters(in: .whitespaces).isEmpty || auto.trimmingCharacters(in: .whitespaces).hasPrefix("no")), junk: d.atIndex(6)?.booleanValue ?? false,
            replied: d.atIndex(5)?.booleanValue ?? false)
    }

    public func text(id: String) throws -> String {
        let p = try position(of: id)
        let t = try event(AppleScripts.limited(AppleScripts.mailContentOne, p)).stringValue ?? ""
        return String(t.prefix(MailMessage.maxText))
    }

    public func accountAddresses() throws -> [String] {
        let d = try event(AppleScripts.mailAccountAddresses)
        var out: [String] = []
        for i in stride(from: 1, through: d.numberOfItems, by: 1) { out += Self.strings(d.atIndex(i)) }
        return out
    }
}
#endif
