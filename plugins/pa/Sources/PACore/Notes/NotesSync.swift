import Foundation

/// Phase 3, package S6: notes (spec 10). Each note is a document of the kind `note`, with passages and numbers in
/// index.sqlite, so that "where is" finds it. The PA reads only while Notes runs, and never starts or changes Notes.
/// It skips locked notes and the folder "Recently Deleted". Flags on notes are not built: the request flags failed
/// their go mark (E11), so the work on flags stopped.
extension Engine {
    /// The notes texts to read in one batch. The rest waits for the next read.
    static let notesBatch = 50

    /// The map from the id of a note in Notes to its document id and its change date, in the meta table.
    func notesMap() -> [String: (doc: Int64, modified: Double)] {
        guard let s = store?.meta("notes.map"), let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: [Double]]
        else { return [:] }
        var out: [String: (doc: Int64, modified: Double)] = [:]
        for (k, v) in obj where v.count == 2 { out[k] = (Int64(v[0]), v[1]) }
        return out
    }

    func saveNotesMap(_ map: [String: (doc: Int64, modified: Double)]) {
        let obj = map.mapValues { [Double($0.doc), $0.modified] }
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) {
            try? store?.setMeta("notes.map", String(decoding: d, as: UTF8.self))
        }
    }

    /// Call it from the tick. It starts a read if the time came, Notes runs, and no read runs.
    public func readNotesIfDue() {
        guard settings.sources.notes, let source = notesSource, store != nil, !notesReading else { return }
        let now = clock.now
        if let last = lastNotesRead, now.timeIntervalSince(last) < TimeInterval(max(1, settings.notes.everyMinutes) * 60) { return }
        guard source.isRunning else { return }
        lastNotesRead = now
        let known = notesMap()
        let reader = notesReader
        notesReading = true
        background { [weak self] in
            let outcome = reader.run { () -> (all: Set<String>, changed: [(NoteHeader, String)]) in
                let headers = try source.notes().filter { !$0.locked && $0.folder != "Recently Deleted" }
                var changed: [(NoteHeader, String)] = []
                for h in headers where changed.count < Engine.notesBatch {
                    if let k = known[h.id], k.modified >= h.modifiedAt.timeIntervalSince1970 { continue }
                    if let t = try? source.text(id: h.id) { changed.append((h, t)) }
                }
                return (Set(headers.map(\.id)), changed)
            }
            self?.runLater(0) { [weak self] in
                guard let self else { return }
                self.notesReading = false
                switch outcome {
                case .done(let r): self.applyNotes(all: r.all, changed: r.changed)
                case .failed, .timedOut, .busy: self.log.write(self.clock.now, "notes-read-failed")
                }
            }
        }
    }

    /// Runs on the engine queue. A new or changed note gets its passages again. A gone note loses its document and
    /// its passages at once.
    func applyNotes(all: Set<String>, changed: [(NoteHeader, String)]) {
        guard let store else { return }
        let now = clock.now
        var map = notesMap()
        var gone = 0
        for (id, entry) in map where !all.contains(id) {
            try? index?.deleteDoc(entry.doc)
            if var d = store.doc(entry.doc) {
                d.droppedAt = now
                d.passages = 0
                try? store.updateDoc(d, event: "note-gone", at: now)
            }
            map[id] = nil
            gone += 1
        }
        for (h, text) in changed {
            var passages: [Passage] = []
            passages = TextCut.passages(text, page: nil, startPosition: 0)
            if passages.count > Engine.maxPassages { passages = Array(passages.prefix(Engine.maxPassages)) }
            var doc: Doc
            if let entry = map[h.id], let d = store.doc(entry.doc), d.droppedAt == nil {
                doc = d
                doc.title = h.name
            } else {
                doc = Doc(address: nil, title: h.name, app: "Notes", projectID: nil, createdAt: now)
                doc.kind = .note
                guard let id = try? store.insertDoc(doc, event: "note-read") else { continue }
                doc.id = id
            }
            doc.modifiedAt = h.modifiedAt
            doc.textState = .read
            do {
                try index?.replacePassages(doc: doc.id, passages)
                doc.passages = passages.count
                try store.updateDoc(doc, event: "note-read", at: now)
                map[h.id] = (doc.id, h.modifiedAt.timeIntervalSince1970)
            } catch {
                log.write(now, "notes-index-error")
            }
        }
        saveNotesMap(map)
        log.write(now, "notes-read", ["changed": String(changed.count), "gone": String(gone), "notes": String(all.count)])
        if !changed.isEmpty || gone > 0 {
            vectorCache = nil
            indexIfNeeded()
        }
    }

    /// `sources.notes` is off: the note documents, their passages and their numbers go at once.
    func forgetNotes() {
        guard let store else { return }
        for d in store.docs(where: "kind = 'note'") {
            try? index?.deleteDoc(d.id)
            try? store.db.run("DELETE FROM doc WHERE id = ?", [.int(d.id)])
        }
        try? store.setMeta("notes.map", nil)
        vectorCache = nil
    }
}
