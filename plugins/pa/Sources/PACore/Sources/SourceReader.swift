import Foundation

// Phase 3 (build spec 7.4): one protocol for each source, with a fixture source for the tests.
// The Mac sources (EventKit, Mail and Notes through Apple events) are in PAMac.

/// One mail message, as the reader gives it (spec 7.4). `text` is empty until the PA asks for it.
public struct MailMessage: Equatable, Sendable {
    /// The id of the message in Mail.
    public var id: String
    /// The Message-ID header, for the link.
    public var messageID: String
    public var fromName: String
    public var fromAddress: String
    public var to: [String]
    public var cc: [String]
    public var subject: String
    public var date: Date
    /// `List-Unsubscribe` or `List-Id` is there.
    public var listHeader: Bool
    /// The value of `Precedence` in lower case, or "".
    public var precedence: String
    /// `Auto-Submitted` is there and is not "no".
    public var autoSubmitted: Bool
    public var junk: Bool
    public var replied: Bool
    /// The plain text, the first 6,000 characters.
    public var text: String

    public static let maxText = 6000

    public init(id: String, messageID: String, fromName: String, fromAddress: String, to: [String], cc: [String],
                subject: String, date: Date, listHeader: Bool = false, precedence: String = "",
                autoSubmitted: Bool = false, junk: Bool = false, replied: Bool = false, text: String = "") {
        self.id = id; self.messageID = messageID; self.fromName = fromName; self.fromAddress = fromAddress
        self.to = to; self.cc = cc; self.subject = subject; self.date = date; self.listHeader = listHeader
        self.precedence = precedence; self.autoSubmitted = autoSubmitted; self.junk = junk; self.replied = replied
        self.text = String(text.prefix(MailMessage.maxText))
    }
}

/// One note, with no text.
public struct NoteHeader: Equatable, Sendable {
    public var id: String
    public var name: String
    public var modifiedAt: Date
    public var locked: Bool

    public init(id: String, name: String, modifiedAt: Date, locked: Bool = false) {
        self.id = id; self.name = name; self.modifiedAt = modifiedAt; self.locked = locked
    }
}

/// The permission state of a source.
public enum SourceAccess: String, Sendable {
    case allowed
    case notAsked = "not asked"
    case denied
    /// The app does not run. The PA never starts it (rule 2).
    case notRunning = "not running"
}

public protocol CalendarSource: AnyObject {
    var access: SourceAccess { get }
    /// The events that start in the span. The source skips declined, cancelled and all-day events (spec 9.1).
    func events(from: Date, to: Date) throws -> [CalEvent]
}

public protocol MailSource: AnyObject {
    /// Mail runs. If it does not run, the PA does not read (rule 2).
    var isRunning: Bool { get }
    /// Mail is the front app. The PA does not read then (spec 6.1, rule 5).
    var isFront: Bool { get }
    /// The ids of the newest inbox messages, newest first, from position `from` (0 is the newest).
    func ids(from: Int, count: Int) throws -> [String]
    /// The message with no text.
    func envelope(id: String) throws -> MailMessage
    /// The plain text of the message, the first 6,000 characters.
    func text(id: String) throws -> String
    /// The addresses of the Mail accounts (for the setting `owner`).
    func accountAddresses() throws -> [String]
}

public protocol NotesSource: AnyObject {
    var isRunning: Bool { get }
    /// The notes, newest change first.
    func notes() throws -> [NoteHeader]
    func text(id: String) throws -> String
}

public struct SourceError: Error, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

// MARK: - Fixture sources

/// Mail from JSON lines in the format of the build spec, section 8.2.
public final class FixtureMail: MailSource {
    public var isRunning = true
    public var isFront = false
    public var owner: [String]
    /// Newest first.
    public private(set) var messages: [MailMessage]
    /// The count of calls, for the tests of the read plan.
    public private(set) var calls = 0

    public init(messages: [MailMessage], owner: [String] = ["maya.rao@example.com"]) {
        self.messages = messages.sorted { $0.date > $1.date }
        self.owner = owner
    }

    public convenience init(jsonl url: URL, owner: [String] = ["maya.rao@example.com"]) throws {
        try self.init(messages: FixtureMail.read(url), owner: owner)
    }

    /// Reads the fixture file. A bad line is an error.
    public static func read(_ url: URL) throws -> [MailMessage] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let iso = ISO8601DateFormatter()
        var out: [MailMessage] = []
        for (n, line) in text.split(separator: "\n").enumerated() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = obj["id"] as? String else { throw SourceError("line \(n + 1) is not a message") }
            let date = (obj["date"] as? String).flatMap { iso.date(from: $0) } ?? Date(timeIntervalSince1970: 0)
            out.append(MailMessage(
                id: id, messageID: "<\(id)@fixture.example>", fromName: obj["from_name"] as? String ?? "",
                fromAddress: obj["from_address"] as? String ?? "", to: obj["to"] as? [String] ?? [],
                cc: obj["cc"] as? [String] ?? [], subject: obj["subject"] as? String ?? "", date: date,
                listHeader: obj["list_unsubscribe"] as? Bool ?? false,
                precedence: (obj["precedence"] as? String ?? "").lowercased(),
                autoSubmitted: obj["auto_submitted"] as? Bool ?? false, junk: obj["junk"] as? Bool ?? false,
                replied: obj["replied"] as? Bool ?? false, text: obj["body"] as? String ?? ""))
        }
        return out
    }

    /// A new message arrives (newest).
    public func add(_ m: MailMessage) { messages.insert(m, at: 0) }

    /// The owner replied to the message in Mail.
    public func setReplied(_ id: String) {
        if let i = messages.firstIndex(where: { $0.id == id }) { messages[i].replied = true }
    }

    public func ids(from: Int, count: Int) throws -> [String] {
        calls += 1
        guard from < messages.count else { return [] }
        return messages[from..<min(messages.count, from + count)].map(\.id)
    }

    public func envelope(id: String) throws -> MailMessage {
        calls += 1
        guard var m = messages.first(where: { $0.id == id }) else { throw SourceError("no message") }
        m.text = ""
        return m
    }

    public func text(id: String) throws -> String {
        calls += 1
        guard let m = messages.first(where: { $0.id == id }) else { throw SourceError("no message") }
        return m.text
    }

    public func accountAddresses() throws -> [String] { owner }
}

/// A calendar from a list of events.
public final class FixtureCalendar: CalendarSource {
    public var access: SourceAccess = .allowed
    public var all: [CalEvent]

    public init(_ events: [CalEvent]) { all = events }

    public func events(from: Date, to: Date) throws -> [CalEvent] {
        all.filter { $0.startsAt >= from && $0.startsAt < to && !$0.allDay }.sorted { $0.startsAt < $1.startsAt }
    }
}

/// Notes from JSON lines in the mail format (`from_address` empty): `subject` is the name, `body` the text.
public final class FixtureNotes: NotesSource {
    public var isRunning = true
    public var items: [(NoteHeader, String)]

    public init(_ items: [(NoteHeader, String)]) { self.items = items }

    public convenience init(jsonl url: URL) throws {
        let mails = try FixtureMail.read(url)
        self.init(mails.map { (NoteHeader(id: $0.id, name: $0.subject, modifiedAt: $0.date), $0.text) })
    }

    public func notes() throws -> [NoteHeader] { items.map(\.0).sorted { $0.modifiedAt > $1.modifiedAt } }

    public func text(id: String) throws -> String {
        guard let t = items.first(where: { $0.0.id == id }) else { throw SourceError("no note") }
        return t.1
    }
}

// MARK: - The time limit

/// Runs source reads off the command path, one at a time, with a time limit for each batch (rule 3).
/// If a batch reaches the limit, the reader gives `.timedOut` and does not start a new batch until the old one ends.
/// Nothing waits for a source read on the command path.
public final class SourceReader: @unchecked Sendable {
    public enum Outcome<T> {
        case done(T)
        case failed(Error)
        case timedOut
        /// The last batch did not end yet.
        case busy
    }

    public let limit: TimeInterval
    let queue: DispatchQueue
    let lock = NSLock()
    var running = false

    public init(name: String, limit: TimeInterval = 20) {
        self.limit = limit
        queue = DispatchQueue(label: "pa.source.\(name)", qos: .utility)
    }

    public var isBusy: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    /// Runs the batch on the queue of the source and waits for it, at most `limit` seconds. Call it from a
    /// background queue, never from the command path.
    public func run<T>(_ batch: @escaping () throws -> T) -> Outcome<T> {
        lock.lock()
        if running { lock.unlock(); return .busy }
        running = true
        lock.unlock()
        let done = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()
        queue.async { [self] in
            do { box.set(.success(try batch())) } catch { box.set(.failure(error)) }
            lock.lock(); running = false; lock.unlock()
            done.signal()
        }
        guard done.wait(timeout: .now() + limit) == .success, let r = box.get() else { return .timedOut }
        switch r {
        case .success(let v): return .done(v)
        case .failure(let e): return .failed(e)
        }
    }
}

final class ResultBox<T>: @unchecked Sendable {
    let lock = NSLock()
    var value: Result<T, Error>?
    func set(_ v: Result<T, Error>) { lock.lock(); value = v; lock.unlock() }
    func get() -> Result<T, Error>? { lock.lock(); defer { lock.unlock() }; return value }
}
