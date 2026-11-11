import Foundation

/// The project rule, version 2 (phase 2 follow-up spec, R1): propose a project only if two different signals agree.
/// The records are only the ones that the owner put in a project: items with `project_by` owner, and the
/// passages of documents with a project.
public struct ProjectRuleV2: Equatable, Sendable {
    /// The variants of the measure table (3.3).
    public enum Variant: String, CaseIterable, Sendable {
        case name = "Name only"
        case neighbors = "Neighbors only"
        case keywords = "Keywords only"
        case neighborsAndKeywords = "Neighbors and Keywords"
        case fullWithH = "Full rule with line 3"
        case fullNoH = "Full rule without line 3"
    }

    /// Of the 5 nearest records, this many must be in one project.
    public var neighborsNeed = 4
    /// Of the first 3 keyword results, this many must be in one project. The development data chose 3:
    /// 26 proposals, 26 correct, 0 wrong (with 2: 41 proposals, 2 wrong).
    public var keywordsNeed = 3
    /// Line 3: 5 of 5 neighbors, and the nearest record above this score. Nil: line 3 is off.
    public var high: Float?
    /// A project needs this many owner records before the rule can propose it.
    public var minRecords = 3

    public init(high: Float? = nil) { self.high = high }

    /// The signals of one capture.
    public struct Signals: Equatable, Sendable {
        /// The project whose name is in the capture, if exactly one is.
        public var name: String?
        /// The project of the 5 nearest records (4 or 5 of 5), with the count and the score of the nearest one.
        public var neighbors: String?
        public var neighborsCount = 0
        public var nearest: Float = -1
        /// The project of the first 3 keyword results (2 or 3 of 3).
        public var keywords: String?
        public var keywordsCount = 0
        public init() {}
    }

    /// The project of a list of records, if `need` or more of them are in one project.
    public static func majority(_ projects: [String], need: Int) -> (String, Int)? {
        var count: [String: Int] = [:]
        for p in projects { count[p, default: 0] += 1 }
        guard let best = count.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }),
              best.value >= need else { return nil }
        return (best.key, best.value)
    }

    /// The project names that are in the words as whole words. Case and plural "s" do not count.
    public static func names(in words: String, projects: [(id: String, name: String)]) -> [String] {
        let w = Words.terms(words).map(Words.stem)
        return projects.filter { p in
            let n = Words.terms(p.name).map(Words.stem)
            guard !n.isEmpty, n.count <= w.count else { return false }
            for i in 0...(w.count - n.count) where Array(w[i..<i + n.count]) == n { return true }
            return false
        }.map(\.id)
    }

    /// The signals of one capture. `nearest` is the list of (project, score) of the nearest records, best first.
    /// `keywordHits` is the list of projects of the keyword results, best first.
    public func signals(words: String, projects: [(id: String, name: String)], nearest: [(String, Float)],
                        floor: Float, keywordHits: [String]) -> Signals {
        var s = Signals()
        let n = Self.names(in: words, projects: projects)
        if n.count == 1 { s.name = n[0] }
        let top = nearest.prefix(5).filter { $0.1 >= floor }
        s.nearest = nearest.first?.1 ?? -1
        // The signals keep the best project and its count. `propose` checks the count against the need.
        if let m = Self.majority(top.map(\.0), need: 1) { s.neighbors = m.0; s.neighborsCount = m.1 }
        if let m = Self.majority(Array(keywordHits.prefix(3)), need: 1) { s.keywords = m.0; s.keywordsCount = m.1 }
        return s
    }

    /// The proposal of the full rule.
    public func propose(_ s: Signals) -> String? {
        propose(s, variant: high == nil ? .fullNoH : .fullWithH)
    }

    public func propose(_ s0: Signals, variant: Variant) -> String? {
        var s = s0
        if s.neighborsCount < neighborsNeed { s.neighbors = nil }
        if s.keywordsCount < keywordsNeed { s.keywords = nil }
        switch variant {
        case .name: return s.name
        case .neighbors: return s.neighbors
        case .keywords: return s.keywords
        case .neighborsAndKeywords:
            return s.neighbors != nil && s.neighbors == s.keywords ? s.neighbors : nil
        case .fullNoH, .fullWithH:
            if let n = s.name { return n }
            if let n = s.neighbors, n == s.keywords { return n }
            if variant == .fullWithH, let h = high, let n = s.neighbors, s.neighborsCount == 5, s.nearest > h { return n }
            return nil
        }
    }

    /// Line 3: the lowest H above which 5 of 5 neighbors never named a wrong project on the development data.
    public static func fitHigh(_ cases: [(signals: Signals, truth: String)]) -> Float? {
        let wrong = cases.filter { $0.signals.neighborsCount == 5 && $0.signals.neighbors != $0.truth }.map(\.signals.nearest)
        let h = (wrong.max() ?? -1) + 0.0001
        let right = cases.filter { $0.signals.neighborsCount == 5 && $0.signals.neighbors == $0.truth && $0.signals.nearest > h }
        return right.isEmpty ? nil : h
    }
}
