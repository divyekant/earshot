import Foundation

/// Phase 2, Q2: "note this" (build spec 7.4), "what projects" and "finish project" (7.5).
extension Engine {
    /// The longest selection that the PA keeps as a note.
    static let maxSelection = 2000

    /// "note this" and "note this for <project>" with selected text: the selection is the note, with a link to the
    /// document or page of the context. Nil: not this form, or no selection. Then the words are a normal note.
    func noteThis(id: String, text: String, context: [String: String]) -> Outgoing? {
        guard let store else { return nil }
        let words = Engine.words(text)
        guard words.first == "this" else { return nil }
        var project: Project?
        if words.count > 1 {
            let (p, rest) = readProject(text)
            guard let p, Engine.words(rest) == ["this"] else { return nil }
            project = p
        }
        guard let raw = context["selection"] else { return nil }
        let selection = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Engine.maxSelection))
        guard !selection.isEmpty else { return nil }
        if let again = duplicateNote(.note, "selection|" + selection) { return .note(id, again) }
        let now = clock.now
        var it = Item(kind: .note, said: selection, title: String(selection.prefix(Engine.maxTitle)), createdAt: now)
        it.contextApp = context["app"]
        if let project { it.projectID = project.id; it.projectBy = "owner" }
        // The link: the kept reference of the same file or address, or a new reference (no text is read for it).
        if var ref = docFromContext(context, projectID: project?.id) {
            if let path = ref.path, let old = store.doc(path: path) {
                it.docID = old.id
            } else if let address = ref.address,
                      let old = store.docs(where: "dropped_at IS NULL AND address = ?", [.text(address)]).first {
                it.docID = old.id
            } else {
                ref.textState = .none
                it.docID = try? store.insertDoc(ref)
                docsChanged()
            }
        }
        do { it.id = try store.insert(it) } catch {
            spare(kind: .note, said: selection, at: now)
            return .note(id, "The store had an error. Your words are kept in a spare file.")
        }
        itemChanged(it, old: nil)
        let short = selection.count > 60 ? String(selection.prefix(60)) + "…" : selection
        var parts = ["Note"]
        if let project { parts.append(project.name) }
        parts.append(short)
        let note = parts.joined(separator: " · ")
        rememberCapture(.note, "selection|" + selection, note: note)
        return .note(id, note)
    }

    /// "what projects": the open projects, each with its count of open items.
    func whatProjects(id: String) -> Outgoing {
        guard let store else { return .note(id, "The PA store does not open.") }
        let projects = store.projects()
        guard !projects.isEmpty else { return .note(id, "No open projects.") }
        let counts = store.openCounts()
        let records = projects.map { p -> (RecordKind, Int64, String) in
            let n = counts[p.id, default: 0]
            return (.project, p.id, "\(p.name) · \(n) open")
        }
        return listAnswer(id, title: "Projects", records: records, more: "All open")
    }

    /// "finish project <name>": the project is closed. Its open items stay open and keep the project.
    func finishProject(id: String, text: String) -> Outgoing {
        guard let store else { return .note(id, "The PA store does not open.") }
        let name = Engine.dropFirst(Engine.clean(text), ["the", "project"])
        guard !name.isEmpty else { return .note(id, "Say the project: \"finish project kitchen\".") }
        guard let p = findProject(name) else {
            if let closed = store.project(named: name, includeClosed: true) { return .note(id, "Project \(closed.name) is closed already.") }
            return .note(id, "No project \(name.prefix(80)).")
        }
        do { try store.setProjectState(p.id, open: false, at: clock.now) } catch { return .note(id, "The store had an error. Nothing changed.") }
        projectsChanged()
        let n = store.openCounts()[p.id, default: 0]
        return .note(id, "Project closed · \(p.name) · \(n) \(n == 1 ? "item" : "items") still open")
    }
}
