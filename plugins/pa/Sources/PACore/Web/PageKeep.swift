import Foundation

/// One ask for page text that waits for earshot (phase 4 spec, section 9.2).
struct PendingPage {
    enum Purpose { case keep, points }
    var purpose: Purpose
    /// The kept reference (for `keep`).
    var docID: Int64?
    var title: String
    /// True if the page was kept before: the note says "Kept again".
    var again: Bool
    var askedAt: Date
    var parts = PageTextAssembler()
}

/// Phase 4, W4: the text of a kept web page. The PA selects the main text and keeps it as passages. It never writes
/// text. The log keeps counts and states only.
extension Engine {
    /// The time that the PA waits for the page text of one command.
    static let pageWait: TimeInterval = 10
    /// Put the nearest heading in front of each passage. Set from the development bench of E12 only.
    static let pageHeadingFront = false
    /// The variant of the main text rule. Set from the development bench of E12 only.
    static let pageVariant: MainText.Variant = .full
    /// The most kept pages in kept.html.
    static let keptListMax = 200

    static let notePageNoText = "Link kept. The PA has no text of this page."
    static let notePageChanged = "Link kept. The PA has no text of this page. Say \"keep this\" again."
    static let notePagePassword = "Link kept. The page has a password field, so earshot did not read it."

    var keptFolder: URL { pagesFolder.appendingPathComponent("kept", isDirectory: true) }
    func keptCopyURL(_ docID: Int64) -> URL { keptFolder.appendingPathComponent("\(docID).html") }

    /// True for an address that the PA asks page text for: http, https and file.
    static func isPageAddress(_ s: String?) -> Bool {
        guard let s = s?.lowercased() else { return false }
        return s.hasPrefix("http://") || s.hasPrefix("https://") || s.hasPrefix("file:")
    }

    /// True for an address that a PA page may link to.
    static func isWebAddress(_ s: String?) -> Bool {
        guard let s = s?.lowercased() else { return false }
        return s.hasPrefix("http://") || s.hasPrefix("https://")
    }

    /// The address without the part after `#` and without the parameters `utm_*`, `fbclid` and `gclid` (9.2, step 6).
    static func normalPageAddress(_ s: String) -> String {
        guard var c = URLComponents(string: s) else { return s }
        c.fragment = nil
        if let q = c.queryItems {
            let kept = q.filter { item in
                let n = item.name.lowercased()
                return !(n.hasPrefix("utm_") || n == "fbclid" || n == "gclid")
            }
            c.queryItems = kept.isEmpty ? nil : kept
        }
        return c.string ?? s
    }

    /// The site name of an address: the host without "www.".
    static func siteName(_ s: String?) -> String? {
        guard let s, let host = URLComponents(string: s)?.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// 1240 → "1,240".
    static func groupNumber(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        for (i, c) in s.enumerated() {
            if i > 0, (s.count - i) % 3 == 0 { out.append(",") }
            out.append(c)
        }
        return (n < 0 ? "-" : "") + out
    }

    /// The kept page with the same address (9.2, step 6), if there is one.
    func keptPage(address: String) -> Doc? {
        guard let store else { return nil }
        let key = Engine.normalPageAddress(address)
        return store.docs(where: "dropped_at IS NULL AND kind = 'page' AND address IS NOT NULL")
            .first { Engine.normalPageAddress($0.address ?? "") == key }
    }

    /// "keep this" for a web page. Saves the reference and answers at once. Asks earshot for the page text after the
    /// answer, if the setting is on.
    func keepPage(id: String, _ doc: Doc, project: Project?, words: String, context: [String: String]) -> Outgoing {
        guard let store else { return .note(id, "The PA store does not open. Nothing saved.") }
        let address = doc.address ?? ""
        let dupKey = words + "|" + address
        if let again = duplicateNote(.keepThis, dupKey) { return .note(id, again) }
        var parts: [String]
        var kept: Doc
        var again = false
        if var old = keptPage(address: address) {
            // The same page again: one reference. A new project in the words moves it.
            if let p = project, old.projectID != p.id {
                old.projectID = p.id
                try? store.updateDoc(old, event: "move", at: clock.now)
                docsChanged()
            }
            kept = old
            again = true
            parts = ["Kept again"]
        } else {
            kept = doc
            do { kept.id = try store.insertDoc(kept) } catch { return .note(id, "The store had an error. Nothing kept.") }
            docsChanged()
            parts = ["Kept"]
        }
        if let p = project { parts.append(p.name) }
        parts.append(kept.title)
        let note = parts.joined(separator: " · ")
        rememberCapture(.keepThis, dupKey, note: note)
        if settings.pageText, Engine.isPageAddress(context["url"]) {
            askPageText(id, PendingPage(purpose: .keep, docID: kept.id, title: kept.title, again: again, askedAt: clock.now))
        }
        return .note(id, note)
    }

    /// Records an ask. The ask goes to earshot after the answer of the command.
    func askPageText(_ re: String, _ pending: PendingPage) {
        pagePending[re] = pending
        pageAsksToSend.append(re)
    }

    /// Sends the asks of the last command, and starts the wait of 10 s for each.
    func sendPageAsks() {
        let asks = pageAsksToSend
        pageAsksToSend = []
        for re in asks {
            output.send(.askPageText(re: re))
            log.write(clock.now, "page-ask")
            runLater(Engine.pageWait) { [weak self] in self?.expirePageAsks() }
        }
    }

    /// Ends each ask that waited 10 s or more. The timer and the clock tick call it.
    func expirePageAsks() {
        let now = clock.now
        for (re, p) in pagePending where now.timeIntervalSince(p.askedAt) >= Engine.pageWait {
            pagePending[re] = nil
            log.write(now, "page-timeout")
            pageNoText(p, reason: nil)
        }
    }

    /// Phase 4: a page text message from earshot. The log keeps no text: only the part, the count of blocks and
    /// the length of the reason of an error.
    func receivePageText(_ m: PageTextMessage) {
        switch m {
        case .part(let re, let part, let of, let complete, _, _, let blocks):
            log.write(clock.now, "page-text", ["part": String(part), "of": String(of), "blocks": String(blocks.count),
                                               "complete": complete ? "1" : "0"])
            guard var p = pagePending[re] else { return }
            if let page = p.parts.add(m) {
                pagePending[re] = nil
                finishPage(p, page)
            } else {
                pagePending[re] = p
            }
        case .error(let re, let reason):
            log.write(clock.now, "page-text-error", ["chars": String(reason.count)])
            guard let p = pagePending.removeValue(forKey: re) else { return }
            pageNoText(p, reason: reason)
        }
    }

    /// No text came. The reference stays.
    func pageNoText(_ p: PendingPage, reason: String?) {
        switch p.purpose {
        case .keep:
            if let id = p.docID, var d = store?.doc(id), d.droppedAt == nil, d.textState == .none || d.textState == .queued {
                d.textState = .noText
                try? store?.updateDoc(d, event: "page-read", at: clock.now)
                docsChanged()
            }
            if reason == "the page changed" {
                output.send(.note(nil, Engine.notePageChanged))
            } else if reason == "sign-in, code or payment page" {
                output.send(.note(nil, Engine.notePagePassword))
            } else {
                output.send(.note(nil, Engine.notePageNoText))
            }
        case .points:
            pointsNoText(p, reason: reason)
        }
    }

    /// The blocks came: select the main text, write the passages and the text copy, then show the note.
    func finishPage(_ p: PendingPage, _ page: WebPageText) {
        guard p.purpose == .keep else { pointsPage(p, page); return }
        guard let store, let id = p.docID, var d = store.doc(id), d.droppedAt == nil else { return }
        let now = clock.now
        let sel = MainText.select(page.blocks, variant: Engine.pageVariant)
        if sel.noText {
            // A page kept before keeps its old text.
            if d.textState == .none || d.textState == .queued {
                d.textState = .noText
                try? store.updateDoc(d, event: "page-read", at: now)
                docsChanged()
            }
            log.write(now, "page-read", ["doc": String(id), "state": TextState.noText.rawValue, "words": String(sel.words)])
            output.send(.note(nil, Engine.notePageNoText))
            return
        }
        let cut = PageCut.passages(sel.blocks, headingFront: Engine.pageHeadingFront)
        let partial = cut.cut || !page.complete
        guard let index else {
            output.send(.note(nil, Engine.notePageNoText))
            return
        }
        do {
            try index.replacePassages(doc: id, cut.passages)
        } catch {
            log.write(now, "page-read", ["doc": String(id), "state": "index-error"])
            output.send(.note(nil, Engine.notePageNoText))
            return
        }
        d.passages = cut.passages.count
        d.textState = partial ? .partial : .read
        d.textAt = now
        d.textWords = sel.words
        try? store.updateDoc(d, event: "page-read", at: now)
        writeKeptCopy(d, sel.blocks)
        writeKeptText(d.id, sel.blocks)
        log.write(now, "page-read", ["doc": String(id), "state": d.textState.rawValue, "passages": String(d.passages),
                                     "words": String(sel.words)])
        docsChanged()
        vectorCache = nil
        indexIfNeeded()
        let words = Engine.groupNumber(sel.words) + " words"
        let note: String
        if p.again {
            note = "Kept again · \(d.title) · text updated"
        } else if partial {
            note = "Text kept in part · \(d.title) · \(words)"
        } else {
            note = "Text kept · \(d.title) · \(words)"
        }
        output.send(.note(nil, note))
    }

    // MARK: - The text copy and the list (9.3)

    static let pageCSP = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'\">"

    /// pages/kept/<doc id>.html: the main text of the page, as text. No script, no outside source.
    func writeKeptCopy(_ d: Doc, _ blocks: [PageBlock]) {
        try? FileManager.default.createDirectory(at: keptFolder, withIntermediateDirectories: true)
        var body = ""
        let address = d.address ?? ""
        body += "<p class=\"sub\">\(Engine.escape(address))"
        if Engine.isWebAddress(address) {
            body += "<br><a href=\"\(Engine.escape(address))\">Open the page on the web</a>"
        }
        if let at = d.textAt { body += "<br>Read \(Engine.escape(Engine.stamp(at, clock.calendar)))" }
        body += "<br>Text copy by the PA. The page on the web can be different now.</p>"
        var inList = false
        for b in blocks {
            if b.kind == .li {
                if !inList { body += "<ul class=\"text\">"; inList = true }
                body += "<li>\(Engine.escape(b.text))</li>"
                continue
            }
            if inList { body += "</ul>"; inList = false }
            switch b.kind {
            case .h:
                let level = min(6, max(2, (b.level ?? 2) + 1))
                body += "<h\(level) class=\"text\">\(Engine.escape(b.text))</h\(level)>"
            case .pre: body += "<pre>\(Engine.escape(b.text))</pre>"
            case .q: body += "<blockquote>\(Engine.escape(b.text))</blockquote>"
            default: body += "<p>\(Engine.escape(b.text))</p>"
            }
        }
        if inList { body += "</ul>" }
        let style = Engine.pageStyle + """
        h2.text,h3.text,h4.text,h5.text,h6.text{text-transform:none;letter-spacing:0;color:var(--fg);font-size:22px}
        ul.text{list-style:disc;padding-left:24px}ul.text li{display:list-item;border:0;padding:4px 0}
        pre{white-space:pre-wrap}blockquote{margin:0 0 16px;padding-left:16px;border-left:3px solid var(--line)}
        """
        let html = """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">\(Engine.pageCSP)<meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(Engine.escape(d.title)) · PA</title><style>\(style)</style></head>
        <body><main><h1>\(Engine.escape(d.title))</h1>
        \(body)
        <nav><a href="../kept.html">Kept pages</a> · <a href="../today.html">Today</a></nav>
        </main></body></html>
        """
        try? Data(html.utf8).write(to: keptCopyURL(d.id), options: .atomic)
    }

    /// A short time for the pages: "2026-11-12 05:40".
    static func stamp(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// The path of the text copy of a kept page, if the copy is there.
    func keptCopyPath(_ d: Doc) -> String? {
        guard d.kind == .page, d.textState == .read || d.textState == .partial else { return nil }
        let url = keptCopyURL(d.id)
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    /// pages/kept.html: the kept pages, newest first, 200 at most.
    func writeKeptList() {
        guard let store else { return }
        let docs = store.docs(where: "dropped_at IS NULL AND kind = 'page' AND address IS NOT NULL")
            .sorted { ($0.textAt ?? $0.createdAt) > ($1.textAt ?? $1.createdAt) }
            .prefix(Engine.keptListMax)
        var body = ""
        if docs.isEmpty {
            body = "<p class=\"empty\">No kept pages.</p>"
        } else {
            let lis = docs.map { d -> String in
                var head = Engine.escape(d.title)
                if Engine.isWebAddress(d.address) { head = "<a href=\"\(Engine.escape(d.address ?? ""))\">\(head)</a>" }
                var info: [String] = []
                if let site = Engine.siteName(d.address) { info.append(Engine.escape(site)) }
                if keptCopyPath(d) != nil {
                    if let at = d.textAt { info.append(Engine.escape(Engine.stamp(at, clock.calendar))) }
                    info.append(Engine.groupNumber(d.textWords ?? 0) + " words")
                    if d.textState == .partial { info.append("in part") }
                    info.append("<a href=\"kept/\(d.id).html\">text copy</a>")
                } else {
                    info.append("no text")
                }
                return "<li><span>\(head)<br><span class=\"when\">\(info.joined(separator: " · "))</span></span></li>"
            }.joined()
            body = "<ul>\(lis)</ul>"
        }
        write(page(title: "Kept pages", sub: "\(docs.count) page\(docs.count == 1 ? "" : "s")", body: body), "kept.html")
    }

    /// The main text of a kept page for "main points": one block on each line. It is in the data folder of the PA,
    /// not in the pages.
    var keptTextFolder: URL { folder.appendingPathComponent("kept-text", isDirectory: true) }
    func keptTextURL(_ docID: Int64) -> URL { keptTextFolder.appendingPathComponent("\(docID).txt") }

    func writeKeptText(_ docID: Int64, _ blocks: [PageBlock]) {
        try? FileManager.default.createDirectory(at: keptTextFolder, withIntermediateDirectories: true)
        try? Data(blocks.map(\.text).joined(separator: "\n").utf8).write(to: keptTextURL(docID), options: .atomic)
    }

    /// Removes the text copy and the main text of a page.
    func removeKeptCopy(_ docID: Int64) {
        try? FileManager.default.removeItem(at: keptCopyURL(docID))
        try? FileManager.default.removeItem(at: keptTextURL(docID))
    }
}
