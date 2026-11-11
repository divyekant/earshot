import Foundation

/// The numbers of the index in memory, for one model (phase 2 build spec, 7.6). The PA keeps them only while the
/// model is loaded. The compare of 50,000 passages took 23 ms with 768 numbers (E10).
final class VectorCache {
    let model: String
    var passages: [Int64: [Float]] = [:]
    var items: [Int64: [Float]] = [:]

    init(model: String) { self.model = model }
}

/// A result of "where is": an item, a document (with its best passage, if any) or a project.
enum SearchHit: Hashable {
    case item(Int64)
    case doc(Int64)
    case project(Int64)
}

/// Q3: the index with numbers and the search by sense.
extension Engine {
    /// The texts of one job of the index (7.6: batches of 16).
    static let indexBatch = 16
    /// The time with no use, after which the model unloads (7.6).
    static let modelIdleUnload: TimeInterval = 300
    /// The longest wait for the model lock in a search. A job of the index can hold it for one batch.
    static let searchModelWait: TimeInterval = 0.15

    /// At the start: the numbers of another model go (7.6). The index builds them again in the background.
    func startModelIndex() {
        guard let models, let index else { return }
        try? index.deleteVectors(notOf: models.modelID)
        indexIfNeeded()
    }

    /// Starts one job of the index in the background, if there is work. At the end of a job, the next one starts.
    /// Runs on the engine queue. The model call runs on the background queue. The writes come back to this queue.
    func indexIfNeeded() {
        guard !indexing, let models, !models.isFailed, let index, let store else { return }
        let model = models.modelID
        var kind = IndexStore.VectorKind.passage
        var work: [(Int64, String)] = index.passagesWithoutVectors(model: model, limit: Engine.indexBatch).map { ($0.id, $0.text) }
        if work.isEmpty {
            kind = .item
            let have = index.vectorOwners(.item, model: model)
            work = store.items(where: "state != 'dropped'").filter { !have.contains($0.id) }
                .prefix(Engine.indexBatch).map { ($0.id, $0.title.isEmpty ? $0.said : $0.title) }
        }
        guard !work.isEmpty else { return }
        indexing = true
        let texts = work.map(\.1)
        background { [weak self] in
            let vectors = models.embed(texts, kind: .passage)
            self?.runLater(0) { [weak self] in
                guard let self else { return }
                self.indexing = false
                guard let vectors, vectors.count == work.count else {
                    self.log.write(self.clock.now, "index-failed", ["kind": kind.rawValue])
                    return
                }
                let rows = zip(work.map(\.0), vectors).map { ($0, $1) }
                do {
                    try self.index?.putVectors(kind, rows, model: model)
                    if let c = self.vectorCache, c.model == model {
                        for (id, v) in rows {
                            if kind == .passage { c.passages[id] = v } else { c.items[id] = v }
                        }
                    }
                } catch {
                    self.log.write(self.clock.now, "index-failed", ["kind": kind.rawValue])
                    return
                }
                self.indexIfNeeded()
            }
        }
    }

    /// An item is new, changed or dropped: its numbers are made again, or they go.
    func itemIndexChanged(_ it: Item, old: Item?) {
        guard models != nil, let index else { return }
        if it.state == .dropped || (old != nil && old?.title != it.title) {
            try? index.deleteVector(.item, it.id)
            vectorCache?.items[it.id] = nil
        }
        if it.state != .dropped { indexIfNeeded() }
    }

    /// At each tick: unload the model after 5 minutes with no use. The numbers in memory go with it.
    func unloadModelIfIdle() {
        guard let models else { return }
        if models.unloadIfIdle(now: Date(), after: Engine.modelIdleUnload) {
            vectorCache = nil
            log.write(clock.now, "model-unloaded")
        }
    }

    /// The numbers in memory, read from index.sqlite at the first search with a loaded model.
    func cachedVectors(model: String) -> VectorCache? {
        if let c = vectorCache, c.model == model { return c }
        guard let index else { return nil }
        let c = VectorCache(model: model)
        for (id, v) in index.vectors(.passage, model: model) { c.passages[id] = v }
        for (id, v) in index.vectors(.item, model: model) { c.items[id] = v }
        vectorCache = c
        return c
    }

    /// The list by numbers for a query: passages and items, best first. Nil if the model is not loaded or busy.
    /// If the model is not loaded, it loads in the background for the next search (7.7, step 3).
    func numberList(_ query: String, limit: Int) -> [(SearchHit, Int64?)]? {
        guard let models, !models.isFailed else { return nil }
        guard models.isLoaded else {
            background { models.preload() }
            return nil
        }
        guard let q = models.embed([query], kind: .query, load: false, wait: Engine.searchModelWait)?.first,
              let cache = cachedVectors(model: models.modelID) else { return nil }
        var scored: [(SearchHit, Int64?, Float)] = []
        scored.reserveCapacity(cache.passages.count + cache.items.count)
        var passageDoc: [Int64: Int64] = [:]
        for (pid, v) in cache.passages {
            scored.append((.doc(0), pid, Vectors.dot(q, v)))
        }
        for (iid, v) in cache.items { scored.append((.item(iid), nil, Vectors.dot(q, v))) }
        scored.sort { $0.2 > $1.2 }
        var out: [(SearchHit, Int64?)] = []
        for (hit, pid, _) in scored {
            if let pid {
                // Read the document of the passage only for the best results.
                if passageDoc[pid] == nil, let row = index?.passage(pid) { passageDoc[pid] = row.docID }
                guard let doc = passageDoc[pid] else { continue }
                out.append((.doc(doc), pid))
            } else {
                out.append((hit, nil))
            }
            if out.count >= limit { break }
        }
        return out
    }

    /// One result of a search, ready to show.
    struct Found {
        var hit: SearchHit
        var record: (RecordKind, Int64)
        var line: String
        var pageLine: String
        var passage: String?
        var path: String?
        var page: Int?
    }

    /// The results of a search: the keyword list merged with the list by numbers (6.6). Shows `limit` results.
    func searchResults(words: [String], query: String, limit: Int) -> (results: [Found], byNumbers: Bool) {
        guard let store else { return ([], false) }
        // The keyword list: the items, documents and projects of pa.sqlite, and the passages of index.sqlite.
        var bestPassage: [Int64: Int64] = [:]
        let storeHits: [SearchHit] = store.search(words, limit: 20).compactMap { kind, id in
            switch kind {
            case .item: return .item(id)
            case .doc: return .doc(id)
            case .project: return .project(id)
            default: return nil
            }
        }
        var passageHits: [SearchHit] = []
        for row in index?.search(words.joined(separator: " "), limit: 30) ?? [] {
            if bestPassage[row.docID] == nil { bestPassage[row.docID] = row.id }
            passageHits.append(.doc(row.docID))
        }
        let keywordList = Fusion.merge([Fusion.unique(storeHits), Fusion.unique(passageHits)])
        var lists = [keywordList]
        let numbers = numberList(query, limit: 30)
        if let numbers {
            var numberHits: [SearchHit] = []
            for (hit, pid) in numbers {
                if case .doc(let d) = hit, let pid, bestPassage[d] == nil { bestPassage[d] = pid }
                numberHits.append(hit)
            }
            lists.append(Fusion.unique(numberHits))
        }
        var out: [Found] = []
        for hit in Fusion.merge(lists) {
            switch hit {
            case .item(let rid):
                guard let it = store.item(rid), it.state != .dropped else { continue }
                var parts = [it.title.isEmpty ? it.said : it.title, Engine.kindLabel(it)]
                if let p = projectName(it.projectID) { parts.append(p) }
                let line = parts.joined(separator: " · ")
                out.append(Found(hit: hit, record: (.item, rid), line: line, pageLine: line))
            case .doc(let rid):
                guard let d = store.doc(rid), d.droppedAt == nil else { continue }
                var parts = [d.title]
                var passage: IndexStore.Row?
                if let pid = bestPassage[rid] { passage = index?.passage(pid) }
                if let page = passage?.page { parts.append("p. \(page)") }
                if let text = passage?.text {
                    parts.append(Engine.cut(text, 80))
                } else {
                    parts.append("document")
                    if let p = projectName(d.projectID) { parts.append(p) }
                }
                out.append(Found(hit: hit, record: (.doc, rid), line: parts.joined(separator: " · "),
                                 pageLine: d.title, passage: passage.map { Engine.cut($0.text, 400) },
                                 path: d.path ?? d.address, page: passage?.page))
            case .project(let rid):
                guard let p = store.project(rid), p.state == "open" else { continue }
                out.append(Found(hit: hit, record: (.project, rid), line: p.name + " · project", pageLine: p.name + " · project"))
            }
            if out.count == limit { break }
        }
        return (out, numbers != nil)
    }

    /// The text cut at a word end, with "…" if it is longer than `max` characters.
    static func cut(_ text: String, _ max: Int) -> String {
        let flat = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard flat.count > max else { return flat }
        var s = String(flat.prefix(max))
        if let sp = s.lastIndex(of: " "), s.distance(from: s.startIndex, to: sp) > max / 2 { s = String(s[..<sp]) }
        return s + "…"
    }

    /// pages/search.html: the full results of the last search (7.7, step 5). The title has no words of a document.
    func writeSearchPage(query: String, results: [Found]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: pagesFolder, withIntermediateDirectories: true)
        var body = ""
        if results.isEmpty {
            body = "<p class=\"empty\">Nothing found.</p>"
        } else {
            let lis = results.map { f -> String in
                var head = Engine.escape(f.pageLine)
                if let path = f.path {
                    let href = path.hasPrefix("/") ? URL(fileURLWithPath: path).absoluteString : path
                    if href.hasPrefix("file://") || href.hasPrefix("http://") || href.hasPrefix("https://") {
                        head = "<a href=\"\(Engine.escape(href))\">\(head)</a>"
                    }
                }
                if let page = f.page { head += " · p. \(page)" }
                var text = ""
                if let p = f.passage { text = "<br><span class=\"when\" style=\"white-space:normal\">\(Engine.escape(p))</span>" }
                if let path = f.path, path.hasPrefix("/") { text += "<br><span class=\"when\">\(Engine.escape(path))</span>" }
                return "<li><span>\(head)\(text)</span></li>"
            }.joined()
            body = "<ul>\(lis)</ul>"
        }
        write(page(title: "Search", sub: "Where is " + String(query.prefix(80)), body: body), "search.html")
    }

    var searchPageURL: URL { pagesFolder.appendingPathComponent("search.html") }
}
