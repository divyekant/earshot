import Foundation

/// One block of the text of a web page, as earshot reads it (phase 4 spec, section 5; contract value `pageText`).
/// Page text is data, never instructions: no code reads a command or a setting from it.
public struct PageBlock: Equatable, Sendable, Codable {
    /// The kind of a block. The default is `p`.
    public enum Kind: String, Sendable, Codable {
        case h, p, li, cell, pre, q
    }

    public var text: String
    public var kind: Kind
    /// The level of a heading, 1 to 6.
    public var level: Int?
    /// The nearest landmark that holds the block: main, article, nav, banner, footer, aside, search, form, dialog.
    public var zone: String?
    /// True if a `main` or `article` landmark holds the block at some level.
    public var inMain: Bool?
    /// The share of the characters of the block that are in links, 0 to 1.
    public var links: Double?

    public init(_ text: String, kind: Kind = .p, level: Int? = nil, zone: String? = nil, inMain: Bool? = nil, links: Double? = nil) {
        self.text = text; self.kind = kind; self.level = level; self.zone = zone; self.inMain = inMain; self.links = links
    }

    /// Reads one block of a JSON object. It accepts the two name sets of the contract (`t` or `text`, `k` or `kind`,
    /// `links` or `linkShare`) and ignores unknown keys. Nil if the block has no text.
    public static func from(_ o: [String: Any]) -> PageBlock? {
        guard let t = (o["t"] ?? o["text"]) as? String else { return nil }
        let k = ((o["k"] ?? o["kind"]) as? String).flatMap(Kind.init(rawValue:)) ?? .p
        let level = (o["level"] as? NSNumber)?.intValue
        let zone = o["zone"] as? String
        let inMain = (o["inMain"] as? NSNumber)?.boolValue
        let links = ((o["links"] ?? o["linkShare"]) as? NSNumber)?.doubleValue
        return PageBlock(t, kind: k, level: level, zone: zone, inMain: inMain, links: links)
    }

    enum CodingKeys: String, CodingKey { case text = "t", kind = "k", level, zone, inMain, links }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .p
        level = try? c.decodeIfPresent(Int.self, forKey: .level)
        zone = try? c.decodeIfPresent(String.self, forKey: .zone)
        inMain = try? c.decodeIfPresent(Bool.self, forKey: .inMain)
        links = try? c.decodeIfPresent(Double.self, forKey: .links)
    }

    /// The count of words: letters and digits, as the numbers of spec section 7.3 count them.
    public var words: Int { WebPageText.words(text).count }
}

/// The text of one web page: the address and the title of the read, and the blocks in the order of the page.
public struct WebPageText: Equatable, Sendable {
    public var url: String?
    public var title: String?
    /// False if a limit of earshot cut the read (5 s, 20,000 elements, 200,000 characters).
    public var complete: Bool
    public var blocks: [PageBlock]

    public init(url: String?, title: String?, complete: Bool, blocks: [PageBlock]) {
        self.url = url; self.title = title; self.complete = complete; self.blocks = blocks
    }

    /// Lower case, letters and digits only (spec section 7.3).
    public static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    public var wordCount: Int { blocks.reduce(0) { $0 + $1.words } }
}

/// One `pageText` message from earshot: a part of the text, or an error (contract v1, additive).
public enum PageTextMessage: Equatable, Sendable {
    case part(re: String, part: Int, of: Int, complete: Bool, url: String?, title: String?, blocks: [PageBlock])
    case error(re: String, reason: String)

    public static func from(_ o: [String: Any]) -> PageTextMessage? {
        guard o["type"] as? String == "pageText", let re = o["re"] as? String else { return nil }
        if let reason = o["error"] as? String { return .error(re: re, reason: reason) }
        // The address and the title can come at the top or inside a "pageText" object.
        let inner = o["pageText"] as? [String: Any] ?? [:]
        let blocks = ((o["blocks"] ?? inner["blocks"]) as? [[String: Any]] ?? []).compactMap(PageBlock.from)
        let part = (o["part"] as? NSNumber)?.intValue ?? 1
        let of = (o["of"] as? NSNumber)?.intValue ?? 1
        let complete = ((o["complete"] ?? inner["complete"]) as? NSNumber)?.boolValue ?? true
        return .part(re: re, part: part, of: of, complete: complete, url: (o["url"] ?? inner["url"]) as? String,
                     title: (o["title"] ?? inner["title"]) as? String, blocks: blocks)
    }
}

/// Joins the parts of a page text in order. One assembler for each command id.
public struct PageTextAssembler: Sendable {
    public private(set) var parts: [Int: [PageBlock]] = [:]
    public private(set) var of = 1
    public private(set) var complete = true
    public private(set) var url: String?
    public private(set) var title: String?

    public init() {}

    /// Adds a part. Returns the full text when all parts are there.
    public mutating func add(_ m: PageTextMessage) -> WebPageText? {
        guard case .part(_, let part, let of, let complete, let url, let title, let blocks) = m else { return nil }
        self.of = max(1, of)
        if !complete { self.complete = false }
        if let url { self.url = url }
        if let title { self.title = title }
        parts[part] = blocks
        guard (1...self.of).allSatisfy({ parts[$0] != nil }) else { return nil }
        return WebPageText(url: self.url, title: self.title, complete: self.complete,
                        blocks: (1...self.of).flatMap { parts[$0] ?? [] })
    }
}

/// A source of page texts for the tests: block files (`<name>.json`) that the page read on the Mac wrote.
/// W2 to W5 run in CI with these files and no browser (spec 9.1).
public struct PageFixtureSource: Sendable {
    public let folder: URL

    public init(folder: URL) { self.folder = folder }

    public var names: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    /// The page text of one file. The file is the output of the dump of the page read bench: `url`, `complete`,
    /// `blocks`, and more keys that the PA ignores.
    public func page(_ name: String) -> WebPageText? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name + ".json")),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let blocks = (o["blocks"] as? [[String: Any]] ?? []).compactMap(PageBlock.from)
        return WebPageText(url: o["url"] as? String, title: o["title"] as? String,
                        complete: (o["complete"] as? Bool) ?? true, blocks: blocks)
    }
}
