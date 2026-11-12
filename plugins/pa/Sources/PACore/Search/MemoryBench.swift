import Foundation

/// Phase 5 (X1): a made-up store of the size of the owner's store, for the memory bench
/// (`earshot-pa --memory-bench`). The rows are made up. The counts come from the owner's store (numbers only).
public enum MemoryBench {
    /// The row counts of the owner's store on 2026-11-12: items, documents, passages, events.
    public static let ownerCounts = (items: 21, docs: 95, passages: 79, events: 503)

    static let words = ["garden", "invoice", "plumber", "lease", "tiles", "roof", "dentist", "passport", "budget",
                        "school", "car", "insurance", "holiday", "quote", "boiler", "renewal", "permit", "fence"]

    static func sentence(_ i: Int) -> String {
        (0..<12).map { words[($0 * 7 + i * 3) % words.count] }.joined(separator: " ") + " \(i)."
    }

    /// Fills the store of the engine with made-up rows. Gives the counts that it wrote.
    @discardableResult
    public static func fill(_ e: Engine, scale: Int = 1) -> (items: Int, docs: Int, passages: Int) {
        guard let store = e.store, let index = e.index else { return (0, 0, 0) }
        let now = e.clock.now
        let n = ownerCounts
        let kinds = ItemKind.allCases
        for i in 0..<(n.items * scale) {
            var it = Item(kind: kinds[i % kinds.count], said: sentence(i), title: sentence(i + 1), createdAt: now)
            it.updatedAt = now
            _ = try? store.insert(it)
        }
        var passages = 0
        let docs = n.docs * scale
        let perDoc = max(1, n.passages * scale / max(1, docs / 4))
        for i in 0..<docs {
            var d = Doc(address: "https://example.com/\(i)", title: sentence(i), app: nil, projectID: nil, createdAt: now)
            d.kind = .page
            guard let id = try? store.insertDoc(d) else { continue }
            // One document in four has passages, as in the owner's store.
            guard i % 4 == 0, passages < n.passages * scale else { continue }
            let ps = (0..<perDoc).map { Passage(position: $0, page: nil, text: sentence(i * 10 + $0)) }
            if (try? index.replacePassages(doc: id, ps)) != nil { passages += ps.count }
        }
        for i in 0..<(n.events * scale) { store.log("bench", .item, Int64(i), at: now) }
        return (n.items * scale, docs, passages)
    }
}
