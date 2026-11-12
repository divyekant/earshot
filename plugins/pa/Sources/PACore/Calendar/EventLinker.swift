import Foundation

/// Links by a rule between a calendar event and the records of the owner (phase 3 build spec, 9.2). A link by a
/// rule shows with "?". The lines:
/// - L1: the project name or an alias is a whole phrase of the event title, and a second signal agrees: one open
///   item of that project shares one more content word with the title, or 3 or more of the 5 nearest owner records
///   of the title are in that project.
/// - L2: an open item whose title has the first or the last name of a person of the event.
/// - L3: the project rule version 2 gives a project for the event title.
/// The rule selects records. It writes no text.
public struct EventLinker: Sendable {
    public struct Lines: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let l1 = Lines(rawValue: 1)
        public static let l2 = Lines(rawValue: 2)
        public static let l3 = Lines(rawValue: 4)

        public var label: String {
            [(Lines.l1, "L1"), (Lines.l2, "L2"), (Lines.l3, "L3")].filter { contains($0.0) }.map(\.1).joined(separator: "+")
        }

        /// Reads "L1+L2" or "L1,L3".
        public init?(label: String) {
            var v: Lines = []
            for p in label.uppercased().split(whereSeparator: { "+, ".contains($0) }) {
                switch p {
                case "L1": v.insert(.l1)
                case "L2": v.insert(.l2)
                case "L3": v.insert(.l3)
                default: return nil
                }
            }
            guard !v.isEmpty else { return nil }
            self = v
        }

        public static let allSets: [Lines] = (1...7).map { Lines(rawValue: $0) }
    }

    public struct Project: Sendable {
        public var key: String
        public var name: String
        public var aliases: [String]
        public init(key: String, name: String, aliases: [String] = []) { self.key = key; self.name = name; self.aliases = aliases }
    }

    /// An open item or a kept document of the owner.
    public struct Record: Sendable {
        public var key: String
        public var project: String?
        public var title: String
        public var isDoc: Bool
        public var due: Day?
        /// A larger number is newer.
        public var order: Double
        public init(key: String, project: String?, title: String, isDoc: Bool = false, due: Day? = nil, order: Double) {
            self.key = key; self.project = project; self.title = title; self.isDoc = isDoc; self.due = due; self.order = order
        }
    }

    public struct Result: Equatable, Sendable {
        public var items: [String] = []
        public var docs: [String] = []
        /// The lines that gave a link.
        public var lines: Lines = []
        public var isEmpty: Bool { items.isEmpty && docs.isEmpty }
    }

    public var lines: Lines
    public static let maxItems = 5
    public static let maxDocs = 3
    /// Words of a person name that do not count (3 letters or more, not a title).
    static let notNames: Set<String> = ["mrs", "mr", "ms", "miss", "dr", "the", "and", "team", "grandpa", "grandma", "mum", "dad"]

    public init(lines: Lines) { self.lines = lines }

    static func words(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "'" { cur.append(ch) } else if !cur.isEmpty { out.append(cur); cur = "" }
        }
        if !cur.isEmpty { out.append(cur) }
        return out.map { $0.hasSuffix("'s") ? String($0.dropLast(2)) : $0 }
    }

    /// True if all words of `phrase` are in `title` one after the other.
    static func hasPhrase(_ title: [String], _ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, phrase.count <= title.count else { return false }
        for i in 0...(title.count - phrase.count) where Array(title[i..<(i + phrase.count)]) == phrase { return true }
        return false
    }

    /// The content words of a text, with no stop words.
    static func content(_ s: String) -> Set<String> {
        Set(words(s).filter { !Words.stop.contains($0) && $0.count >= 3 })
    }

    /// The names of the people of an event: the first and the last name, 3 letters or more, not a title.
    static func names(_ people: [String]) -> Set<String> {
        var out = Set<String>()
        for p in people {
            let w = words(p).filter { $0.count >= 3 && !notNames.contains($0) && !Words.stop.contains($0) }
            if let f = w.first { out.insert(f) }
            if let l = w.last { out.insert(l) }
        }
        return out
    }

    /// The links for one event.
    /// - nearest: the projects of the 5 nearest owner records of the title (L1, second signal).
    /// - ruleProject: the project of the project rule version 2 for the title (L3), or nil.
    public func link(title: String, people: [String], day: Day, projects: [Project], records: [Record],
                     nearest: [String?], ruleProject: String?) -> Result {
        var r = Result()
        let tw = Self.words(title)
        let tContent = Self.content(title)
        var linkedProjects: [String] = []
        if lines.contains(.l1) {
            for p in projects {
                let phrases = ([p.name] + p.aliases).map(Self.words)
                guard phrases.contains(where: { Self.hasPhrase(tw, $0) }) else { continue }
                let nameWords = Set(phrases.flatMap { $0 })
                let rest = tContent.subtracting(nameWords)
                let sharesWord = records.contains { $0.project == p.key && !$0.isDoc && !Self.content($0.title).intersection(rest).isEmpty }
                let near = nearest.prefix(5).filter { $0 == p.key }.count >= 3
                if sharesWord || near { linkedProjects.append(p.key); r.lines.insert(.l1) }
            }
        }
        if lines.contains(.l3), let p = ruleProject, !linkedProjects.contains(p) {
            linkedProjects.append(p)
            r.lines.insert(.l3)
        }
        var items: [String] = []
        if lines.contains(.l2) {
            let names = Self.names(people)
            if !names.isEmpty {
                for rec in records where !rec.isDoc && !Self.content(rec.title).intersection(names).isEmpty {
                    items.append(rec.key)
                    r.lines.insert(.l2)
                }
            }
        }
        var docs: [String] = []
        for p in linkedProjects {
            // Items that share a content word with the title first (a change on the development set: the
            // spec order alone showed 5 newest items that missed the event), then items with a due day up to the
            // event day, then the newest.
            let its = records.filter { $0.project == p && !$0.isDoc }
            func overlap(_ r: Record) -> Int { Self.content(r.title).intersection(tContent).count }
            func dueRank(_ r: Record) -> Int { (r.due.map { $0 <= day } ?? false) ? 1 : 0 }
            items += its.sorted {
                (overlap($0), dueRank($0), $0.order) > (overlap($1), dueRank($1), $1.order)
            }.map(\.key)
            docs += records.filter { $0.project == p && $0.isDoc }.sorted { $0.order > $1.order }.map(\.key)
        }
        var seen = Set<String>()
        r.items = Array(items.filter { seen.insert($0).inserted }.prefix(Self.maxItems))
        r.docs = Array(docs.filter { seen.insert($0).inserted }.prefix(Self.maxDocs))
        return r
    }
}
