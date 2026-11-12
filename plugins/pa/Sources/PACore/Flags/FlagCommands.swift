import Foundation

// Phase 3 (build spec 8.6): "what is new", "keep N", "drop N" for flags. A flag is a proposal (R-PA-5): it makes no
// reminder and no to-do before the owner says "keep".

extension Engine {
    static let flagOnly = "That is a flag. Say \"keep\" or \"drop\" with its number."
    /// The longest sentence on a flag line.
    static let flagSentenceMax = 120

    /// One flag line.
    /// A request: `Request · Sam Lee · Could you send me the signed form before the 20th? · 20 Nov?`
    /// An arrival for a project: `New in Kitchen? · mail · Sam Lee · Quote for the tiles`
    /// An arrival for a "waiting for" item: `Arrived? · Sam Lee · Quote for the tiles`
    func flagLine(_ f: Flag) -> String {
        switch f.kind {
        case .request:
            var parts = ["Request"]
            if !f.sender.isEmpty { parts.append(f.sender) }
            parts.append(Engine.cut(f.sentence.isEmpty ? f.subject : f.sentence, Engine.flagSentenceMax))
            if let d = f.dueOn { parts.append(TimeText.shortDay(d) + "?") }
            return parts.joined(separator: " · ")
        case .arrival:
            if f.itemID != nil, f.projectID == nil {
                return ["Arrived?", f.sender, f.subject].filter { !$0.isEmpty }.joined(separator: " · ")
            }
            let head = projectName(f.projectID).map { "New in \($0)?" } ?? "New?"
            return [head, f.source.rawValue, f.sender, f.subject].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// "what is new": the open flags, newest first.
    func whatIsNew(id: String) -> Outgoing {
        guard let store else { return .note(id, "The PA store does not open.") }
        let flags = store.openFlags()
        guard !flags.isEmpty else { return .note(id, "Nothing new.") }
        return listAnswer(id, title: "New", records: flags.map { (.flag, $0.id, flagLine($0)) })
    }

    /// "keep 2", "keep 2 for kitchen", "keep 2 as call Sam about the form". "keep" with other words saves a note
    /// (spec 7.1): the PA never loses a capture.
    func keepFlag(id: String, text raw: String, context: [String: String]) -> Outgoing {
        guard let store else { return .note(id, "The PA store does not open. Nothing saved.") }
        let text = Engine.clean(raw)
        guard let (n, restWords) = Engine.leadingNumber(text) else {
            guard !text.isEmpty else { return .note(id, "Say the number of a flag: \"keep 2\".") }
            let saved = capture(.note, id: id, text: text, context: context)
            if case .answer(_, _, let t, _) = saved, t.hasPrefix("Note") {
                return .note(id, "Saved as a note. To keep a flag, say its number.")
            }
            return saved
        }
        guard let (kind, rid) = store.lastList(n), kind == .flag, let flag = store.flag(rid) else {
            return .note(id, "No flag \(n) in the last list. Say \"what is new\".")
        }
        guard flag.state == .new else { return .note(id, "Flag \(n) is \(flag.state.rawValue) already.") }
        // The words after the number: "as <title>" and "for <project>".
        var rest = restWords.trimmingCharacters(in: .whitespaces)
        var project: Project?
        if !rest.isEmpty {
            let (p, cut) = readProject("x " + rest)
            if let p { project = p; rest = String(cut.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        }
        var title = flag.sentence.isEmpty ? flag.subject : flag.sentence
        if rest.lowercased().hasPrefix("as ") {
            let own = String(rest.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if !own.isEmpty { title = own }
        }
        let now = clock.now
        var it = Item(kind: .todo, said: title, title: String(title.prefix(Engine.maxTitle)), createdAt: now)
        it.dueOn = flag.dueOn
        if let project { it.projectID = project.id; it.projectBy = "owner" }
        else if let pid = flag.projectID { it.projectID = pid; it.projectBy = "owner" }
        // The link to the mail.
        if let link = flag.mailLink {
            let doc = Doc(address: link, title: flag.subject.isEmpty ? "Mail" : flag.subject, app: "com.apple.mail",
                          projectID: it.projectID, createdAt: now)
            it.docID = try? store.insertDoc(doc)
        }
        do { it.id = try store.insert(it, event: "keep-flag") } catch {
            return .note(id, "The store had an error. Nothing saved.")
        }
        var f = flag
        f.state = .kept
        f.answeredAt = now
        f.itemID = it.id
        try? store.updateFlag(f)
        store.log("flag-keep", .flag, f.id, at: now)
        itemChanged(it, old: nil)
        flagAnswered(f, kept: true)
        return .note(id, captureNote(it, unsure: false))
    }

    func dropFlag(id: String, _ flag: Flag) -> Outgoing {
        guard let store else { return .note(id, "The PA store does not open.") }
        var f = flag
        f.state = .dropped
        f.answeredAt = clock.now
        do { try store.updateFlag(f) } catch { return .note(id, "The store had an error. Nothing changed.") }
        store.log("flag-drop", .flag, f.id, at: clock.now)
        markPagesDirty()
        flagAnswered(f, kept: false)
        return .note(id, "Dropped · " + Engine.cut(f.sentence.isEmpty ? f.subject : f.sentence, Engine.flagSentenceMax))
    }

    /// The learning (spec 8.8) adds its example here. Package S5.
    func flagAnswered(_ f: Flag, kept: Bool) {}
}
