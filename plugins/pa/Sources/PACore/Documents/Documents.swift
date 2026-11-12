import Foundation

/// Phase 2, Q2 (build spec 7.3): kept files and their text. The PA reads the text in the background and keeps it
/// in index.sqlite. The text never goes to a log, a target name or a page title.
extension Engine {
    /// The most passages for one file. A file with more is `too_large`; the reference stays.
    static let maxPassages = 2000
    /// The time between two checks of the kept files.
    static let fileCheckEvery: TimeInterval = 3600

    var indexURL: URL { folder.appendingPathComponent("index.sqlite") }

    /// Opens index.sqlite. If it had an error, the PA builds the text again from the kept files.
    func openIndex() {
        do {
            let ix = try IndexStore(url: indexURL)
            index = ix
            if ix.rebuilt, let store {
                log.write(clock.now, "index-rebuilt")
                for d in store.docs(where: "dropped_at IS NULL AND kind = 'file' AND text_state = 'read'") { queueRead(d) }
            }
        } catch {
            log.write(clock.now, "index-failed")
        }
    }

    /// A file reference from the context key `document` (a path). Nil if the key is absent or is a folder.
    func fileDoc(_ context: [String: String], projectID: Int64?) -> Doc? {
        guard let path = context["document"], path.hasPrefix("/") else { return nil }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { return nil }
        let url = URL(fileURLWithPath: path)
        var d = Doc(address: nil, title: url.lastPathComponent, app: context["app"], projectID: projectID, createdAt: clock.now)
        d.path = path
        d.kind = .file
        return d
    }

    /// "keep this" with a file in front: save the reference, answer at once, then read the text in the background.
    func keepFile(id: String, _ doc: Doc, project: Project?) -> Outgoing {
        guard let store else { return .note(id, "The PA store does not open. Nothing saved.") }
        var parts = ["Kept"]
        if let p = project { parts.append(p.name) }
        parts.append(doc.title)
        if var old = doc.path.flatMap(store.doc(path:)) {
            // The same file again: one reference. A new project in the words moves it.
            if let p = project, old.projectID != p.id {
                old.projectID = p.id
                try? store.updateDoc(old, event: "move", at: clock.now)
                docsChanged()
            }
            return .note(id, parts.joined(separator: " · "))
        }
        var d = doc
        d.textState = .queued
        do { d.id = try store.insertDoc(d) } catch { return .note(id, "The store had an error. Nothing kept.") }
        docsChanged()
        queueRead(d)
        return .note(id, parts.joined(separator: " · "))
    }

    /// Reads the text of a kept file in the background. The result comes back to the engine queue.
    func queueRead(_ doc: Doc) {
        guard let path = doc.path, let reader = textReader else { return }
        let id = doc.id
        background { [weak self] in
            let url = URL(fileURLWithPath: path)
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let outcome = reader.read(url)
            var passages: [Passage] = []
            if case .text(let pages) = outcome {
                for p in pages {
                    passages += TextCut.passages(p.text, page: p.page, startPosition: passages.count)
                    if passages.count > Engine.maxPassages { break }
                }
            }
            let size = (attrs?[.size] as? NSNumber)?.int64Value
            let modified = attrs?[.modificationDate] as? Date
            self?.runLater(0) { [weak self] in
                self?.finishRead(id, outcome: outcome, passages: passages, size: size, modified: modified)
            }
        }
    }

    /// Saves the result of a read. Runs on the engine queue.
    func finishRead(_ id: Int64, outcome: ReadOutcome, passages: [Passage], size: Int64?, modified: Date?) {
        guard let store, var d = store.doc(id), d.droppedAt == nil else { return }
        let now = clock.now
        var state: TextState
        switch outcome {
        case .text: state = passages.count > Engine.maxPassages ? .tooLarge : .read
        case .noText: state = .noText
        case .tooLarge: state = .tooLarge
        case .noAccess: state = .noAccess
        case .gone: state = .gone
        case .unsupported: state = .none
        }
        if state == .read, let index {
            do {
                try index.replacePassages(doc: id, passages)
                d.passages = passages.count
            } catch {
                state = .queued
            }
        } else if state != .gone {
            // A file that has no text now: the old passages go. A gone file keeps them (7.3).
            try? index?.deleteDoc(id)
            d.passages = 0
        }
        if state == .noAccess { noAccessNote(d) }
        d.textState = state
        if state != .gone {
            d.size = size
            d.modifiedAt = modified
        }
        try? store.updateDoc(d, event: "doc-read", at: now)
        log.write(now, "doc-read", ["doc": String(id), "state": state.rawValue, "passages": String(d.passages)])
        docsChanged()
        // The passages of the old text left the numbers in memory: read them again at the next search.
        vectorCache = nil
        if state == .read { indexIfNeeded() }
    }

    /// One note for each folder that macOS does not let the PA read. The PA does not ask again.
    func noAccessNote(_ d: Doc) {
        guard let store, let path = d.path else { return }
        let folderKey = String(HashEmbedder.fnv((path as NSString).deletingLastPathComponent))
        var seen = Set((store.meta("no_access_folders") ?? "").split(separator: ",").map(String.init))
        guard !seen.contains(folderKey) else { return }
        seen.insert(folderKey)
        try? store.setMeta("no_access_folders", seen.sorted().joined(separator: ","))
        output.send(.note(nil, "The PA cannot read this folder. The reference is kept."))
    }

    /// At each start and one time each hour: read a kept file again if its size or change time is different.
    /// A file that is not there is `gone`: the reference and the old passages stay.
    func checkFilesIfDue(force: Bool = false) {
        guard let store else { return }
        let now = clock.now
        if !force, let last = lastFileCheck, now.timeIntervalSince(last) < Engine.fileCheckEvery { return }
        lastFileCheck = now
        let fm = FileManager.default
        for d in store.docs(where: "dropped_at IS NULL AND kind = 'file' AND path IS NOT NULL AND text_state != 'none'") {
            guard let path = d.path else { continue }
            guard let attrs = try? fm.attributesOfItem(atPath: path) else {
                if d.textState != .gone {
                    var g = d
                    g.textState = .gone
                    try? store.updateDoc(g, event: "doc-gone", at: now)
                    docsChanged()
                }
                continue
            }
            let size = (attrs[.size] as? NSNumber)?.int64Value
            let modified = attrs[.modificationDate] as? Date
            let changed = size != d.size || !Engine.sameTime(modified, d.modifiedAt)
            if changed || d.textState == .gone || d.textState == .queued { queueRead(d) }
        }
    }

    static func sameTime(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.timeIntervalSince(b)) < 0.001
    }

    /// Deletes the text and the numbers of a dropped document at once (R-PA-9).
    func forgetText(_ docID: Int64) {
        try? index?.deleteDoc(docID)
        vectorCache = nil
    }
}
