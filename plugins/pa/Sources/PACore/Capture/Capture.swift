import Foundation

/// The capture rules (build spec 9.1 to 9.4). No model is in the path. The PA saves the words in all cases.
extension Engine {
    /// The longest title. A longer text stays in full in `said`.
    static let maxTitle = 200
    /// The longest text that the PA reads for a time and a project.
    static let maxRead = 2000

    /// Lower-case words, for a match only.
    static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") }).map(String.init)
    }

    /// Removes a "please" at the start and a full stop at the end. The other words stay as the owner said them.
    static func clean(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: #"^please[\s,]+"#, options: [.regularExpression, .caseInsensitive]) { t.removeSubrange(r) }
        while t.hasSuffix(".") { t.removeLast() }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes a first word of the list ("to", "about") from the start.
    static func dropFirst(_ text: String, _ words: [String]) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        for w in words {
            if t.lowercased() == w { return "" }
            if t.lowercased().hasPrefix(w + " ") { return String(t.dropFirst(w.count + 1)).trimmingCharacters(in: .whitespaces) }
        }
        return t
    }

    /// Build spec 9.3: a project only if the words end with "for <name>" or "in <name>", and the name is a project
    /// or an alias. Gives the project and the words with "for <name>" cut.
    func readProject(_ text: String) -> (Project?, String) {
        guard let store else { return (nil, text) }
        let parts = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return (nil, text) }
        // The last "for" or "in" first: "for the kitchen in the old house" can only end with one name.
        for i in stride(from: parts.count - 2, through: 0, by: -1) {
            let w = parts[i].lowercased()
            guard w == "for" || w == "in" else { continue }
            var name = Array(parts[(i + 1)...])
            if name.first?.lowercased() == "the" || name.first?.lowercased() == "my", name.count > 1 {
                if let p = store.project(named: name.joined(separator: " ")) {
                    return (p, TimeReader.tidy(parts[..<i].joined(separator: " ")))
                }
                name.removeFirst()
            }
            if let p = store.project(named: name.joined(separator: " ")) {
                return (p, TimeReader.tidy(parts[..<i].joined(separator: " ")))
            }
        }
        return (nil, text)
    }

    /// The time text of a note: "today 17:00", "Fri 13 Nov", "due Fri 13 Nov 09:00", "no time".
    func timeText(_ it: Item) -> String? {
        let cal = clock.calendar
        let now = clock.now
        if it.kind == .todo {
            guard let d = it.dueOn else { return nil }
            if it.hasClock, let at = it.remindAt { return "due " + TimeText.moment(at, now: now, cal, locale: clock.locale) }
            return "due " + TimeText.day(d, now: now, cal)
        }
        if let at = it.remindAt {
            if it.hasClock { return TimeText.moment(at, now: now, cal, locale: clock.locale) }
            return TimeText.moment(at, now: now, cal, locale: clock.locale)
        }
        if let d = it.dueOn { return TimeText.day(d, now: now, cal) }
        return nil
    }

    func projectName(_ id: Int64?) -> String? { id.flatMap { store?.project($0)?.name } }

    /// The note for a saved item: the label, the time, the project, the title.
    func captureNote(_ it: Item, unsure: Bool) -> String {
        var parts: [String] = []
        switch it.kind {
        case .reminder: parts.append("Reminder")
        case .todo: parts.append("To-do")
        case .note: parts.append("Note")
        }
        if let t = timeText(it) { parts.append(t) }
        else if it.kind == .reminder || unsure { parts.append("no time") }
        if let p = projectName(it.projectID) { parts.append(p) }
        parts.append(it.title.isEmpty ? it.said : it.title)
        return parts.joined(separator: " · ")
    }

    /// The same lead and the same text two times in 60 s: the PA keeps one.
    func duplicateNote(_ lead: PACommand, _ text: String) -> String? {
        guard let last = lastCapture, last.lead == lead, last.text == text,
              clock.now.timeIntervalSince(last.at) < 60 else { return nil }
        return last.note
    }

    func rememberCapture(_ lead: PACommand, _ text: String, note: String) {
        lastCapture = LastCapture(lead: lead, text: text, at: clock.now, note: note)
    }

    /// "remind me", "todo", "task", "note".
    func capture(_ cmd: PACommand, id: String, text raw: String, context: [String: String]) -> Outgoing {
        guard let store else { return .note(id, "The PA store does not open. Nothing saved.") }
        let text = Engine.clean(raw)
        guard !text.isEmpty else { return .note(id, "No words. Nothing saved.") }
        if cmd == .note, let answer = noteThis(id: id, text: text, context: context) { return answer }
        if let again = duplicateNote(cmd, text) { return .note(id, again) }
        let now = clock.now
        let kind: ItemKind = cmd == .remindMe ? .reminder : (cmd == .note ? .note : .todo)
        var it = Item(kind: kind, said: text, title: text, createdAt: now)
        it.contextApp = context["app"]
        var unsure = false
        // A very long text: save all of it, and do not read it for a time or a project.
        if text.count > Engine.maxRead {
            it.title = String(text.prefix(Engine.maxTitle))
        } else {
            var rest = text
            if kind != .note {
                let reader = TimeReader(calendar: clock.calendar, settings: settings)
                let r = reader.read(rest, now: now, todo: kind == .todo)
                unsure = r.unsure
                if r.kind != .none {
                    rest = r.rest
                    it.hasClock = r.hasClock
                    if kind == .todo || r.kind == .due {
                        it.dueOn = r.day
                        if r.hasClock { it.remindAt = r.at }
                    } else {
                        it.remindAt = r.at
                        if r.at == nil { it.dueOn = r.day }
                    }
                }
            }
            if kind == .reminder { rest = Engine.dropFirst(rest, ["to", "about", "that"]) }
            let (project, cut) = readProject(rest)
            if let project { it.projectID = project.id; it.projectBy = "owner"; rest = cut }
            // "remind me about this", "todo this": the document or page in front.
            if kind != .note, rest.lowercased() == "this" {
                guard let doc = docFromContext(context, projectID: it.projectID) else {
                    return .note(id, "Nothing saved. No page or document here.")
                }
                do { it.docID = try store.insertDoc(doc) } catch { }
                rest = doc.title
            }
            it.title = String((rest.isEmpty ? text : rest).prefix(Engine.maxTitle))
        }
        do {
            it.id = try store.insert(it)
        } catch {
            // The PA never loses a capture: keep the words in the spare file, and save them at the next start.
            spare(kind: kind, said: text, at: now)
            return .note(id, "The store had an error. Your words are kept in a spare file.")
        }
        itemChanged(it, old: nil)
        let note = captureNote(it, unsure: unsure)
        rememberCapture(cmd, text, note: note)
        return .note(id, note)
    }

    /// A document reference from the context: the address and the window title. The PA does not read the page or
    /// the file, and does not fetch the address.
    func docFromContext(_ context: [String: String], projectID: Int64?) -> Doc? {
        if let file = fileDoc(context, projectID: projectID) { return file }
        let url = context["url"].flatMap { $0.isEmpty ? nil : $0 }
        let title = context["windowTitle"].flatMap { $0.isEmpty ? nil : $0 }
        guard url != nil || title != nil else { return nil }
        let shown = title ?? url.map { URL(string: $0)?.lastPathComponent ?? $0 } ?? "page"
        return Doc(address: url, title: shown, app: context["app"], projectID: projectID, createdAt: clock.now)
    }

    /// "keep this [for <project>]".
    func keep(id: String, text raw: String, context: [String: String]) -> Outgoing {
        guard let store else { return .note(id, "The PA store does not open. Nothing saved.") }
        let text = Engine.clean(raw)
        let (project, _) = readProject("x " + text)
        // Phase 2: a file in front (context key "document"). The PA reads its text in the background.
        if let file = fileDoc(context, projectID: project?.id), textReader != nil {
            return keepFile(id: id, file, project: project)
        }
        guard var doc = docFromContext(context, projectID: project?.id) else {
            return .note(id, "Nothing kept. No page or document here.")
        }
        if let again = duplicateNote(.keepThis, text + "|" + (doc.address ?? doc.title)) { return .note(id, again) }
        do { doc.id = try store.insertDoc(doc) } catch { return .note(id, "The store had an error. Nothing kept.") }
        docsChanged()
        var parts = ["Kept"]
        if let p = project { parts.append(p.name) }
        parts.append(doc.title)
        let note = parts.joined(separator: " · ")
        rememberCapture(.keepThis, text + "|" + (doc.address ?? doc.title), note: note)
        return .note(id, note)
    }

    /// "new project <name>".
    func newProject(id: String, text raw: String) -> Outgoing {
        guard let store else { return .note(id, "The PA store does not open. Nothing saved.") }
        var name = Engine.dropFirst(Engine.clean(raw), ["called", "named"])
        name = TimeReader.tidy(name)
        guard !name.isEmpty else { return .note(id, "No words. Nothing saved.") }
        if let p = store.project(named: name) { return .note(id, "Project \(p.name) is there already.") }
        if let p = store.project(named: name, includeClosed: true) {
            do { try store.setProjectState(p.id, open: true, at: clock.now) } catch { return .note(id, "The store had an error. Nothing saved.") }
            projectsChanged()
            return .note(id, "Project · \(p.name) · open again")
        }
        // Only the first letter changes to a capital, for the name on screen. The words stay the owner's.
        let shown = name.prefix(1).uppercased() + name.dropFirst()
        do { _ = try store.insertProject(String(shown), at: clock.now) } catch { return .note(id, "The store had an error. Nothing saved.") }
        projectsChanged()
        return .note(id, "Project · \(shown)")
    }

    // MARK: - The spare file

    var spareURL: URL { folder.appendingPathComponent("spare-captures.jsonl") }

    /// Keeps a capture that the store could not save. The PA saves it at the next start.
    func spare(kind: ItemKind, said: String, at: Date) {
        let obj: [String: Any] = ["kind": kind.rawValue, "said": said, "at": at.timeIntervalSince1970]
        guard var line = try? JSONSerialization.data(withJSONObject: obj) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: spareURL) {
            _ = try? h.seekToEnd(); try? h.write(contentsOf: line); try? h.close()
        } else {
            try? line.write(to: spareURL)
        }
        log.write(at, "capture-spare")
    }

    /// Saves the captures of the spare file in the store, then removes the file.
    func saveSpares() {
        guard let store, let data = try? Data(contentsOf: spareURL) else { return }
        var saved = 0
        for line in data.split(separator: 0x0A) {
            guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let said = o["said"] as? String, let k = (o["kind"] as? String).flatMap(ItemKind.init(rawValue:)) else { continue }
            let at = Date(timeIntervalSince1970: o["at"] as? Double ?? clock.now.timeIntervalSince1970)
            if (try? store.insert(Item(kind: k, said: said, title: String(said.prefix(Engine.maxTitle)), createdAt: at))) != nil { saved += 1 }
        }
        try? FileManager.default.removeItem(at: spareURL)
        log.write(clock.now, "spare-saved", ["count": String(saved)])
    }
}

/// The last capture, for the rule "the same capture two times in 60 s".
struct LastCapture {
    var lead: PACommand
    var text: String
    var at: Date
    var note: String
}
