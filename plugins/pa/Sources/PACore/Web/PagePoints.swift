import Foundation

/// Phase 4, W5: main points of a web page (spec section 10). The PA selects 5 sentences of the main text with the
/// main points rule, version 2. It writes no new words. A page that is not kept does not keep its text.
extension Engine {
    static let notePointsFilesOnly = "Main points work for kept files only."
    static let notePointsWait = "Main points · reading this page"
    static let notePointsNoText = "No text of this page. Nothing to show."

    /// "main points of this" with a web page in front and no document. Nil if the context has no page address.
    func mainPointsOfPage(id: String, context: [String: String]) -> Outgoing? {
        guard Engine.isPageAddress(context["url"]) else { return nil }
        guard settings.pagePoints, settings.pageText else { return .note(id, Engine.notePointsFilesOnly) }
        guard let models, !models.isFailed else { return .note(id, "Main points need the search model. It is not installed.") }
        let title = context["windowTitle"].flatMap { $0.isEmpty ? nil : $0 } ?? "this page"
        askPageText(id, PendingPage(purpose: .points, docID: nil, title: title, again: false, askedAt: clock.now))
        return .note(id, Engine.notePointsWait)
    }

    func pointsNoText(_ p: PendingPage, reason: String?) {
        output.send(.note(nil, Engine.notePointsNoText))
    }

    /// The blocks came: select the main text and the main points. The text is not kept.
    func pointsPage(_ p: PendingPage, _ page: WebPageText) {
        let sel = MainText.select(page.blocks, variant: Engine.pageVariant)
        guard !sel.noText else { output.send(.note(nil, Engine.notePointsNoText)); return }
        // One block is one line, so a sentence never goes across two blocks.
        let text = sel.blocks.map(\.text).joined(separator: "\n")
        let address = page.url ?? ""
        showPagePoints(re: nil, title: p.title, address: address, text: text)
    }

    /// The main text of a kept page, as the last read gave it.
    func keptPageText(_ d: Doc) -> String? {
        guard let text = try? String(contentsOf: keptTextURL(d.id), encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    /// "main points of <name>" or "main points 2" for a kept page.
    func mainPointsOfKeptPage(id: String, doc: Doc) -> Outgoing {
        guard settings.pagePoints else { return .note(id, Engine.notePointsFilesOnly) }
        guard let models, !models.isFailed else { return .note(id, "Main points need the search model. It is not installed.") }
        guard doc.textState == .read || doc.textState == .partial, let text = keptPageText(doc) else {
            return .note(id, "No text for \(doc.title). Nothing to show.")
        }
        return showPagePoints(re: id, title: doc.title, address: doc.address ?? "", text: text)
            ?? .note(id, "No text for \(doc.title). Nothing to show.")
    }

    /// Selects the points, writes main-points.html, and sends the list. With `re`, gives the answer back instead.
    @discardableResult
    func showPagePoints(re: String?, title: String, address: String, text: String) -> Outgoing? {
        let start = Date()
        guard let models, let points = try? MainPointsV2.select(text, title: title, embedder: HostEmbedder(models)),
              !points.isEmpty else {
            if re == nil { output.send(.note(nil, Engine.notePointsNoText)) }
            return nil
        }
        writePagePointsPage(title: title, address: address, points: points)
        sendTargets()
        log.write(clock.now, "main-points", ["page": "1", "points": String(points.count),
                                             "ms": String(Int(Date().timeIntervalSince(start) * 1000))])
        let answer = Outgoing.list(re, "Main points · \(title)", points.map { Engine.cut($0, Engine.pointLine) })
        if re == nil { output.send(answer) }
        return answer
    }

    /// pages/main-points.html for a page: the full sentences and the address. A link only for http and https.
    func writePagePointsPage(title: String, address: String, points: [String]) {
        try? FileManager.default.createDirectory(at: pagesFolder, withIntermediateDirectories: true)
        let lis = points.map { "<li><span>\(Engine.escape($0))</span></li>" }.joined()
        var body = "<ul>\(lis)</ul>"
        if Engine.isWebAddress(address) {
            body += "<p class=\"sub\"><a href=\"\(Engine.escape(address))\">Open the page on the web</a></p>"
        }
        write(page(title: "Main points", sub: title + (address.isEmpty ? "" : " · " + address), body: body), "main-points.html")
    }
}
