import Foundation

// The context key "pageText" (docs/PLUGINS.md, section 5.3). The plugin asks for the text of the web page in front
// after a command. earshot reads the page through Accessibility and sends the text in one or more lines.
// The read is not on the command path (R-PL-5).

/// One block of the page text: a heading, a paragraph, a list item, a table cell, code or a quote.
/// The short keys keep the lines small. A key is absent when earshot does not know its value.
public struct PageBlock: Codable, Equatable, Sendable {
    /// The text.
    public var t: String
    /// The kind: h, p, li, cell, pre or q. The default is p.
    public var k: String
    /// The level of a heading, 1 to 6.
    public var level: Int?
    /// The nearest landmark that holds the block: main, article, nav, banner, footer, aside, search, form or dialog.
    public var zone: String?
    /// True if a main or article landmark holds the block at some level.
    public var inMain: Bool?
    /// The share of link text in the block, 0 to 1.
    public var links: Double?

    public init(t: String, k: String = "p", level: Int? = nil, zone: String? = nil, inMain: Bool? = nil, links: Double? = nil) {
        self.t = t; self.k = k; self.level = level; self.zone = zone; self.inMain = inMain; self.links = links
    }
}

/// One line from earshot to the plugin with page text, or with the reason that there is none.
public struct PageTextReply: Codable, Equatable, Sendable {
    public var type = "pageText"
    public var re: String
    public var part: Int?
    public var of: Int?
    /// False if a limit stopped the read. The same on each part.
    public var complete: Bool?
    /// The address and the window title at the time of the read. Only on part 1.
    public var url: String?
    public var title: String?
    public var blocks: [PageBlock]?
    /// Why there is no text. A short reason for the note.
    public var error: String?

    public init(re: String, part: Int? = nil, of: Int? = nil, complete: Bool? = nil, url: String? = nil, title: String? = nil,
                blocks: [PageBlock]? = nil, error: String? = nil) {
        self.re = re; self.part = part; self.of = of; self.complete = complete; self.url = url; self.title = title
        self.blocks = blocks; self.error = error
    }
}

public enum PageText {
    /// The context key.
    public static let key = "pageText"
    /// The longest time from the command to the ask of the plugin.
    public static let askSeconds: TimeInterval = 10
    /// The limits of one read. If a limit stops the read, `complete` is false.
    public static let maxSeconds: Double = 5
    public static let maxElements = 20_000
    public static let maxCharacters = 200_000
    /// The largest line that earshot sends, in bytes. Under the 64 KB line limit of the contract.
    public static let maxLineBytes = 60_000
    /// The longest text of one block in a line. A longer block becomes more blocks of the same kind.
    static let maxBlockCharacters = 8_000

    /// A page that is still loading gives few words. If a read gives fewer words than this, earshot reads again
    /// after `settleStepSeconds`, until `settleSeconds` after the first read.
    public static let settleWords = 50
    public static let settleStepSeconds: Double = 1
    public static let settleSeconds: Double = 3

    /// The number of words in the blocks.
    public static func words(_ blocks: [PageBlock]) -> Int {
        blocks.reduce(0) { $0 + $1.t.split(whereSeparator: { $0.isWhitespace }).count }
    }

    /// Reads until the page has `settleWords` words, an error comes, or the time is over. `read` gives the blocks,
    /// or nil for an error. Gives the last read.
    public static func settled<R>(read: () -> R, blocks: (R) -> [PageBlock]?, wait: (Double) -> Void = { Thread.sleep(forTimeInterval: $0) }) -> R {
        var result = read()
        var waited: Double = 0
        while let b = blocks(result), words(b) < settleWords, waited + settleStepSeconds <= settleSeconds {
            wait(settleStepSeconds)
            waited += settleStepSeconds
            result = read()
        }
        return result
    }

    /// The JSON lines of a read: one or more parts, in order, each under `maxLineBytes`, with a newline at the end.
    public static func lines(re: String, url: String?, title: String?, blocks: [PageBlock], complete: Bool) -> [Data] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // A very long block (a text area) is cut into pieces, so that each piece fits in a line.
        var pieces: [PageBlock] = []
        for b in blocks {
            guard b.t.count > maxBlockCharacters else { pieces.append(b); continue }
            var rest = Substring(b.t)
            while !rest.isEmpty {
                var piece = b
                piece.t = String(rest.prefix(maxBlockCharacters))
                rest = rest.dropFirst(maxBlockCharacters)
                pieces.append(piece)
            }
        }
        let head = PageTextReply(re: re, part: 1, of: 1, complete: complete, url: url.map { String($0.prefix(2_000)) },
                                 title: title.map { String($0.prefix(500)) }, blocks: [])
        let headBytes = (try? encoder.encode(head).count) ?? 3_000
        let budget = maxLineBytes - headBytes - 100
        var groups: [[PageBlock]] = [[]]
        var size = 0
        for p in pieces {
            let n = ((try? encoder.encode(p).count) ?? p.t.utf8.count * 6) + 1
            if size + n > budget, !groups[groups.count - 1].isEmpty {
                groups.append([])
                size = 0
            }
            groups[groups.count - 1].append(p)
            size += n
        }
        return groups.enumerated().compactMap { i, group in
            var reply = PageTextReply(re: re, part: i + 1, of: groups.count, complete: complete, blocks: group)
            if i == 0 { reply.url = head.url; reply.title = head.title }
            guard var line = try? encoder.encode(reply) else { return nil }
            line.append(0x0A)
            return line
        }
    }

    /// The JSON line for a read that gives no text.
    public static func errorLine(re: String, _ reason: String) -> Data {
        var line = (try? JSONEncoder().encode(PageTextReply(re: re, error: reason))) ?? Data()
        line.append(0x0A)
        return line
    }
}

/// The commands that a plugin can ask page text for: one ask for each command, at most `PageText.askSeconds`
/// after the command. Thread safe.
public final class PageTextAsks: @unchecked Sendable {
    public struct Command: Equatable, Sendable {
        /// The command id: the `re` of the ask and of each reply line.
        public var id: String
        public var pluginID: String
        public var at: Date
        /// The page address when the command went out, if earshot knew it.
        public var url: String?
        public var asked = false
    }

    private let lock = NSLock()
    private var commands: [String: Command] = [:]

    public init() {}

    /// Keeps a command that went to a plugin whose manifest names "pageText".
    public func sent(id: String, pluginID: String, url: String?, at: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        commands = commands.filter { at.timeIntervalSince($0.value.at) <= PageText.askSeconds * 6 }
        commands[id] = Command(id: id, pluginID: pluginID, at: at, url: url)
    }

    /// The command for an ask, or the reason to refuse the ask.
    public func ask(re: String?, pluginID: String, at: Date = Date()) -> Result<Command, AskRefusal> {
        lock.lock(); defer { lock.unlock() }
        guard let re, var c = commands[re], c.pluginID == pluginID else { return .failure(AskRefusal("no command with this id")) }
        guard !c.asked else { return .failure(AskRefusal("one ask for each command")) }
        guard at.timeIntervalSince(c.at) <= PageText.askSeconds else { return .failure(AskRefusal("too late")) }
        c.asked = true
        commands[re] = c
        return .success(c)
    }

    public struct AskRefusal: Error, Equatable, Sendable {
        public let reason: String
        public init(_ reason: String) { self.reason = reason }
    }
}
