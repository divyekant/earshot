import Foundation

/// The main text rule of a web page (phase 4 spec, section 8; experiment E12). A pure function: blocks in, the kept
/// blocks out. All word lists and numbers of the rule are in this file. They are set with `pages-dev` only.
public enum MainText {
    /// The variants of E12: (a) the full rule, (b) steps 1, 2 and 5 only, (c) no selection.
    public enum Variant: String, CaseIterable, Sendable {
        case full = "a", zones = "b", all = "c"
    }

    /// Step 1: the blocks inside `main` or `article` count only if they have this many words or more.
    public static let minMainWords = 150
    /// Step 5: with fewer words, the page has no text for the PA.
    public static let minPageWords = 50
    /// Step 3: a block with a larger share of link characters is dropped, if it is not a heading.
    public static let maxLinkShare = 0.5
    /// Step 3: a block with fewer words is dropped, if it is not a heading, a list item or a cell.
    public static let minBlockWords = 4
    /// Step 4: a heading or a short line with one of these texts starts a part that is not main text.
    public static let endWords: [String] = [
        "comments", "related", "you may also like", "more from", "recommended", "share this", "newsletter",
        "read next", "related stories", "related articles", "more opinion", "most read", "popular posts",
        "similar threads", "also on", "other jobs", "leave a comment", "join the newsletter",
    ]
    /// A short line for step 4 has this many words or fewer.
    public static let endLineWords = 6

    static let dropZonesInMain: Set<String> = ["nav", "aside", "form", "search", "footer", "dialog"]
    static let dropZones: Set<String> = ["nav", "banner", "footer", "aside", "search", "form", "dialog"]

    public struct Result: Equatable, Sendable {
        public var blocks: [PageBlock]
        /// True if fewer than 50 words stay: the state `no_text`.
        public var noText: Bool
        public var words: Int
    }

    public static func select(_ blocks: [PageBlock], variant: Variant = .full) -> Result {
        var kept: [PageBlock]
        switch variant {
        case .all:
            kept = blocks
        case .zones, .full:
            kept = zones(blocks)
            if variant == .full { kept = endParts(score(kept)) }
        }
        let words = kept.reduce(0) { $0 + $1.words }
        return Result(blocks: kept, noText: words < minPageWords, words: words)
    }

    /// Steps 1 and 2.
    static func zones(_ blocks: [PageBlock]) -> [PageBlock] {
        let inMain = blocks.filter { $0.inMain == true }
        if inMain.reduce(0, { $0 + $1.words }) >= minMainWords {
            return inMain.filter { !dropZonesInMain.contains($0.zone ?? "") }
        }
        return blocks.filter { !dropZones.contains($0.zone ?? "") }
    }

    /// Step 3: link share, short blocks, short blocks between kept blocks, headings with no kept text below them.
    static func score(_ blocks: [PageBlock]) -> [PageBlock] {
        enum Mark { case keep, short, drop }
        var marks: [Mark] = blocks.map { b in
            if b.kind != .h, (b.links ?? 0) > maxLinkShare { return .drop }
            if b.kind == .h || b.kind == .li || b.kind == .cell { return .keep }
            return b.words < minBlockWords ? .short : .keep
        }
        // A short block between two kept blocks of text stays (a heading does not count as a text block).
        let firstPass = marks
        for i in marks.indices where firstPass[i] == .short {
            let prev = firstPass.indices.prefix(i).last { firstPass[$0] != .short }
            let next = firstPass.indices.suffix(from: i + 1).first { firstPass[$0] != .short }
            let ok = [prev, next].allSatisfy { j in j.map { firstPass[$0] == .keep && blocks[$0].kind != .h } ?? false }
            marks[i] = ok ? .keep : .drop
        }
        // A heading stays only if a kept block that is not a heading follows before the next heading of the same
        // or a higher level.
        for i in marks.indices where marks[i] == .keep && blocks[i].kind == .h {
            let level = blocks[i].level ?? 6
            var has = false
            for j in (i + 1)..<blocks.count {
                if blocks[j].kind == .h, (blocks[j].level ?? 6) <= level { break }
                if blocks[j].kind != .h, marks[j] == .keep { has = true; break }
            }
            if !has { marks[i] = .drop }
        }
        return zip(blocks, marks).filter { $0.1 == .keep }.map(\.0)
    }

    /// True if the text is one of the end words ("Comments (3)" counts as "comments").
    static func isEnd(_ b: PageBlock) -> Bool {
        let w = WebPageText.words(b.text)
        guard !w.isEmpty, w.count <= endLineWords else { return false }
        let line = w.filter { Int($0) == nil }.joined(separator: " ")
        return endWords.contains { line == $0 || line.hasPrefix($0 + " ") }
    }

    /// Step 4: after an end heading or an end line, drop the blocks up to the next heading of the same or a higher
    /// level (for a line that is not a heading: up to the next heading).
    static func endParts(_ blocks: [PageBlock]) -> [PageBlock] {
        var out: [PageBlock] = []
        var stopLevel: Int?
        for b in blocks {
            if let s = stopLevel {
                if b.kind == .h, (b.level ?? 6) <= s, !isEnd(b) { stopLevel = nil } else { continue }
            }
            if isEnd(b) {
                stopLevel = b.kind == .h ? (b.level ?? 6) : 6
                continue
            }
            out.append(b)
        }
        return out
    }
}
