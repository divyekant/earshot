import Foundation

/// A message from earshot (docs/PLUGINS.md, section 5.1).
public enum Incoming: Equatable, Sendable {
    case hello(contract: Int)
    case command(id: String, lead: String, text: String, context: [String: String])
    /// Phase 4: a part of the text of a web page, or the reason why earshot gives none.
    case pageText(PageTextMessage)
    /// A message of a type that the PA does not know. The PA ignores it.
    case unknown(type: String)

    /// Reads one line. Nil if the line is not a JSON object with a "type".
    public static func parse(_ line: Data) -> Incoming? {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = obj["type"] as? String else { return nil }
        switch type {
        case "hello":
            return .hello(contract: (obj["contract"] as? Int) ?? 0)
        case "command":
            guard let id = obj["id"] as? String else { return nil }
            let lead = obj["lead"] as? String ?? ""
            let text = obj["text"] as? String ?? ""
            var ctx: [String: String] = [:]
            if let c = obj["context"] as? [String: Any] {
                for (k, v) in c { if let s = v as? String { ctx[k] = s } }
            }
            return .command(id: id, lead: lead, text: text, context: ctx)
        case "pageText":
            guard let m = PageTextMessage.from(obj) else { return nil }
            return .pageText(m)
        default:
            return .unknown(type: type)
        }
    }
}

/// One answer kind (docs/PLUGINS.md, section 5.2).
public enum AnswerKind: String, Sendable {
    case note, list, alert
}

/// A message from the PA to earshot.
public enum Outgoing: Equatable, Sendable {
    case answer(re: String?, kind: AnswerKind, text: String, items: [String])
    case targets([Target])
    /// Phase 4: the ask for the text of the web page of one command (`re` is the id of the command).
    case askPageText(re: String)

    /// One line of JSON, with no line break in it.
    public func line() -> Data {
        var obj: [String: Any] = [:]
        switch self {
        case .answer(let re, let kind, let text, let items):
            obj["type"] = "answer"
            if let re { obj["re"] = re }
            obj["kind"] = kind.rawValue
            obj["text"] = text
            if kind == .list || !items.isEmpty { obj["items"] = items }
        case .askPageText(let re):
            obj["type"] = "pageText"
            obj["re"] = re
        case .targets(let targets):
            obj["type"] = "targets"
            obj["targets"] = targets.map { t -> [String: Any] in
                var o: [String: Any] = ["id": t.id, "name": t.name, "kind": t.kind]
                if let open = t.open { o["open"] = open }
                return o
            }
        }
        // JSONSerialization escapes line breaks in strings, so the output is one line.
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }

    public static func note(_ re: String?, _ text: String) -> Outgoing { .answer(re: re, kind: .note, text: text, items: []) }
    public static func list(_ re: String?, _ title: String, _ items: [String]) -> Outgoing {
        .answer(re: re, kind: .list, text: title, items: items)
    }
    public static func alert(_ text: String) -> Outgoing { .answer(re: nil, kind: .alert, text: text, items: []) }
}

/// A name that the PA knows, for the core verb "open" of earshot (docs/PLUGINS.md, "targets").
public struct Target: Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: String
    public var open: String?

    public init(id: String, name: String, kind: String, open: String?) {
        self.id = id; self.name = name; self.kind = kind; self.open = open
    }
}

/// The writer of the JSON lines. The program writes to stdout. Tests keep the lines.
public protocol Output: AnyObject {
    func send(_ message: Outgoing)
}

/// An output that keeps the messages. For tests.
public final class MemoryOutput: Output {
    public private(set) var messages: [Outgoing] = []
    private let lock = NSLock()
    public init() {}
    public func send(_ message: Outgoing) {
        lock.lock(); messages.append(message); lock.unlock()
    }
    public func take() -> [Outgoing] {
        lock.lock(); defer { lock.unlock() }
        let out = messages
        messages = []
        return out
    }
}
