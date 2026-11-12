import Foundation

struct ModelNotRun: Error {}

/// The embedding model of the PA as an `Embedder`, for the rule of the main points. It loads the model if needed.
final class HostEmbedder: Embedder {
    let host: ModelHost
    init(_ host: ModelHost) { self.host = host }
    var id: String { host.modelID }
    var dimension: Int { 0 }
    func embed(_ texts: [String], kind: EmbedKind) throws -> [[Float]] {
        guard let out = host.embed(texts, kind: kind) else { throw ModelNotRun() }
        return out
    }
}

/// Q5: "main points" (phase 2 build spec, 8.4). The PA selects sentences of the document. It writes no new words.
extension Engine {
    /// The most characters of one line of the answer.
    static let pointLine = 140

    func mainPoints(id: String, text raw: String, context: [String: String]) -> Outgoing {
        guard let store else { return .note(id, "The PA store does not open.") }
        var words = Engine.clean(raw)
        words = Engine.dropFirst(words, ["of", "for", "from", "in"])
        let doc: Doc
        if let (n, _) = Engine.leadingNumber(words), words.split(separator: " ").count <= 2 {
            // "main points 2": item 2 of the last list, if it is a document.
            guard let (kind, rid) = store.lastList(n), kind == .doc, let d = store.doc(rid), d.droppedAt == nil else {
                return .note(id, "Item \(n) of the last list is not a document.")
            }
            doc = d
        } else if words.isEmpty || ["this", "that", "it", "this document", "this file"].contains(words.lowercased()) {
            // "main points of this": the document in front. If it is not kept, keep it first.
            guard let f = fileDoc(context, projectID: nil) else {
                // Phase 4: a web page in front.
                return mainPointsOfPage(id: id, context: context) ?? .note(id, "No document here. Nothing to show.")
            }
            if let d = f.path.flatMap(store.doc(path:)), d.droppedAt == nil {
                doc = d
            } else {
                var d = f
                d.textState = .queued
                do { d.id = try store.insertDoc(d) } catch { return .note(id, "The store had an error. Nothing kept.") }
                docsChanged()
                doc = d
            }
        } else {
            // "main points of <words>": the best kept document for the words (7.7).
            let w = Array(Fusion.unique(Engine.searchWords(String(words.prefix(Engine.maxRead)))).prefix(12))
            let found = searchResults(words: w, query: String(words.prefix(80)), limit: 10).results
            guard let first = found.first(where: { $0.record.0 == .doc }), let d = store.doc(first.record.1) else {
                return .note(id, "No kept document for \(String(words.prefix(80))).")
            }
            doc = d
        }
        return mainPoints(id: id, doc: doc)
    }

    func mainPoints(id: String, doc: Doc) -> Outgoing {
        if doc.kind == .page { return mainPointsOfKeptPage(id: id, doc: doc) }
        guard let path = doc.path, doc.kind == .file, let reader = textReader else {
            return .note(id, "No text for \(doc.title). Nothing to show.")
        }
        guard let models, !models.isFailed else { return .note(id, "Main points need the search model. It is not installed.") }
        let start = Date()
        // The text exactly as the reader gives it, so that each sentence is a part of the document.
        let outcome = reader.read(URL(fileURLWithPath: path))
        guard case .text(let pages) = outcome, doc.textState == .read || doc.textState == .queued else {
            return .note(id, "No text for \(doc.title). Nothing to show.")
        }
        if doc.textState == .queued {
            // A document kept by this command: save its passages now.
            var passages: [Passage] = []
            for p in pages { passages += TextCut.passages(p.text, page: p.page, startPosition: passages.count) }
            finishRead(doc.id, outcome: outcome, passages: passages, size: nil, modified: nil)
        }
        let full = pages.map(\.text).joined(separator: "\n\n")
        // Main points version 2 (follow-up R2): each sentence gets points for its features.
        let name = (doc.title as NSString).deletingPathExtension
        guard let points = try? MainPointsV2.select(full, title: name, embedder: HostEmbedder(models)), !points.isEmpty else {
            return .note(id, "No text for \(doc.title). Nothing to show.")
        }
        let withPages: [(String, Int?)] = points.map { s in (s, pages.first { $0.text.contains(s) }?.page) }
        writeMainPointsPage(doc: doc, points: withPages)
        sendTargets()
        log.write(clock.now, "main-points", ["doc": String(doc.id), "points": String(points.count),
                                             "ms": String(Int(Date().timeIntervalSince(start) * 1000))])
        return .list(id, "Main points · \(doc.title)", points.map { Engine.cut($0, Engine.pointLine) })
    }

    var mainPointsPageURL: URL { pagesFolder.appendingPathComponent("main-points.html") }

    /// pages/main-points.html: the full sentences, each with its page, and the path of the file.
    func writeMainPointsPage(doc: Doc, points: [(String, Int?)]) {
        try? FileManager.default.createDirectory(at: pagesFolder, withIntermediateDirectories: true)
        let lis = points.map { s, page in
            "<li><span>\(Engine.escape(s))</span>" + (page.map { "<span class=\"when\">p. \($0)</span>" } ?? "") + "</li>"
        }.joined()
        var sub = doc.path ?? ""
        if let p = projectName(doc.projectID) { sub = p + " · " + sub }
        var body = "<ul>\(lis)</ul>"
        if let path = doc.path {
            body += "<p class=\"sub\"><a href=\"\(Engine.escape(URL(fileURLWithPath: path).absoluteString))\">Open the file</a></p>"
        }
        // The title is the file name, as on the project page. It has no sentence of the document.
        write(page(title: "Main points", sub: doc.title + (sub.isEmpty ? "" : " · " + sub), body: body), "main-points.html")
    }
}
