import Foundation

/// The values of the rules with numbers for one model (phase 2 build spec, 8.1 and 8.2). The bench finds them on
/// the made-up development files (E10), never on the holdout files.
public struct ModelRules: Equatable, Sendable {
    /// The project proposal: the best score must be above `a`, and the gap to the second above `b`.
    public var projectA: Float
    public var projectB: Float
    /// The duplicate notice: an open item of the same kind with a score above `duplicateC`.
    public var duplicateC: Float
    /// The search: a result of the list by numbers with a lower score does not count, so that a question that
    /// matches nothing gets no result (E10, "Search holdout with the floor").
    public var searchFloor: Float

    public init(projectA: Float, projectB: Float, duplicateC: Float, searchFloor: Float = -1) {
        self.projectA = projectA
        self.projectB = projectB
        self.duplicateC = duplicateC
        self.searchFloor = searchFloor
    }
}

/// Q4: the project focus, the project proposals and the duplicate notice.
extension Engine {
    // MARK: - The project focus (8.3)

    static let focusProjectKey = "focus_project_id"
    static let focusUntilKey = "focus_until"

    /// After "new project <name>": the project is the focus for some minutes. Gives the text for the answer.
    func setFocus(_ p: Project) -> String? {
        guard let store, settings.projectFocusMinutes > 0 else { return nil }
        let m = settings.projectFocusMinutes
        try? store.setMeta(Engine.focusProjectKey, String(p.id))
        try? store.setMeta(Engine.focusUntilKey, String(clock.now.addingTimeInterval(Double(m) * 60).timeIntervalSince1970))
        return "your next captures go here for \(m) minute\(m == 1 ? "" : "s")"
    }

    /// The focus project, if the time did not end and the project is open.
    func focusProject() -> Project? {
        guard let store, settings.projectFocusMinutes > 0,
              let id = store.meta(Engine.focusProjectKey).flatMap(Int64.init),
              let until = store.meta(Engine.focusUntilKey).flatMap(Double.init),
              clock.now.timeIntervalSince1970 < until,
              let p = store.project(id), p.state == "open" else { return nil }
        return p
    }

    /// A capture starts the minutes of the focus again.
    func renewFocus() {
        guard let store, focusProject() != nil else { return }
        let m = settings.projectFocusMinutes
        try? store.setMeta(Engine.focusUntilKey, String(clock.now.addingTimeInterval(Double(m) * 60).timeIntervalSince1970))
    }

    func endFocus() {
        try? store?.setMeta(Engine.focusProjectKey, nil)
        try? store?.setMeta(Engine.focusUntilKey, nil)
    }

    // MARK: - The second note after a capture (8.1, 8.2)

    /// After a capture: in the background, embed the title, then look for a project and for a similar open item.
    /// The capture is already saved and answered. A second note comes only if there is something to say.
    func afterCapture(_ it: Item) {
        guard let models, !models.isFailed, let rules = models.rules, index != nil else { return }
        let propose = settings.proposeProject && it.projectID == nil
        let duplicates = it.kind != .note
        guard propose || duplicates else { return }
        let title = it.title.isEmpty ? it.said : it.title
        let model = models.modelID
        background { [weak self] in
            let vectors = models.embed([title], kind: .passage)
            self?.runLater(0) { [weak self] in
                guard let self, let vectors, vectors.count == 1 else { return }
                try? self.index?.putVectors(.item, [(it.id, vectors[0])], model: model)
                self.vectorCache?.items[it.id] = vectors[0]
                self.secondNote(it.id, vectors[0], propose: propose, duplicates: duplicates, rules: rules, model: model)
            }
        }
    }

    /// Runs on the engine queue. Reads the records of the owner, then finds the proposal in the background
    /// (project rule version 2, follow-up R1), then sends at most one note with the proposal and the duplicate.
    func secondNote(_ itemID: Int64, _ v: [Float], propose: Bool, duplicates: Bool, rules: ModelRules, model: String) {
        guard let store, let it = store.item(itemID), it.state == .open else { return }
        guard propose, it.projectID == nil else {
            finishNote(itemID, v, proposal: nil, duplicates: duplicates, rules: rules, model: model)
            return
        }
        let records = ownerRecords(model: model)
        let projects = store.projects().map { (id: String($0.id), name: $0.name) }
        let title = it.title.isEmpty ? it.said : it.title
        var rule = ProjectRuleV2()
        rule.byName = settings.proposeByName
        background { [weak self] in
            let found = rule.propose(title: title, vector: v, records: records, projects: projects,
                                                floor: rules.searchFloor)
            self?.runLater(0) { [weak self] in
                self?.finishNote(itemID, v, proposal: found, duplicates: duplicates, rules: rules, model: model)
            }
        }
    }

    /// Runs on the engine queue. Sets the proposed project, looks for a duplicate, and sends the note.
    func finishNote(_ itemID: Int64, _ v: [Float], proposal: (project: String, score: Float)?, duplicates: Bool,
                    rules: ModelRules, model: String) {
        guard let store, let index, var it = store.item(itemID), it.state == .open else { return }
        var proposed: Project?
        if let proposal, it.projectID == nil, let id = Int64(proposal.project), let p = store.project(id), p.state == "open" {
            let old = it
            it.projectID = p.id
            it.projectBy = "search"
            it.projectScore = Double(proposal.score)
            it.updatedAt = clock.now
            if (try? store.update(it, event: "proposal", at: clock.now)) != nil {
                itemChanged(it, old: old)
                proposed = p
            }
        }
        var like: Item?
        if duplicates {
            let open = Dictionary(uniqueKeysWithValues: store.items(where: "state = 'open' AND kind = ? AND id != ?",
                                                                    [.text(it.kind.rawValue), .int(it.id)]).map { ($0.id, $0) })
            var best: (Item, Float)?
            for (id, w) in index.vectors(.item, model: model) {
                guard let other = open[id] else { continue }
                let s = Vectors.dot(v, w)
                if s > rules.duplicateC, s > (best?.1 ?? -1) { best = (other, s) }
            }
            if let b = best {
                like = b.0
                store.log("duplicate-notice", .item, it.id, at: clock.now)
            }
        }
        guard proposed != nil || like != nil else { return }
        var parts: [String] = [Engine.kindName(it.kind)]
        if let p = proposed { parts.append(p.name + "?") }
        if let like {
            parts.append("like one that you have: " + (like.title.isEmpty ? like.said : like.title))
        } else {
            parts.append(it.title.isEmpty ? it.said : it.title)
        }
        output.send(.note(nil, parts.joined(separator: " · ")))
    }

    static func kindName(_ k: ItemKind) -> String {
        switch k {
        case .reminder: return "Reminder"
        case .todo: return "To-do"
        case .note: return "Note"
        }
    }

    /// The records of the owner for the project rule: the items that the owner put in a project, and the passages
    /// of the documents with a project. A proposal does not feed the next proposal.
    func ownerRecords(model: String) -> [ProjectRuleV2.Record] {
        guard let store, let index else { return [] }
        let items = Dictionary(uniqueKeysWithValues: index.vectors(.item, model: model).map { ($0.0, $0.1) })
        let passages = Dictionary(uniqueKeysWithValues: index.vectors(.passage, model: model).map { ($0.0, $0.1) })
        var out: [ProjectRuleV2.Record] = []
        for p in store.projects() {
            let key = String(p.id)
            for it in store.items(where: "project_id = ? AND state != 'dropped' AND (project_by IS NULL OR project_by = 'owner')", [.int(p.id)]) {
                if let v = items[it.id] { out.append(.init(project: key, vector: v, text: it.title.isEmpty ? it.said : it.title)) }
            }
            for d in store.docs(project: p.id) {
                for row in index.passages(doc: d.id) {
                    if let v = passages[row.id] { out.append(.init(project: key, vector: v, text: row.text)) }
                }
            }
        }
        return out
    }

    /// "move it to <project>" after a proposal in the last 10 minutes: count a wrong proposal (8.1, step 5).
    /// A move to the same project confirms the proposal and is not wrong.
    func countCorrection(old: Item, new: Item) {
        guard old.projectBy == "search", let store else { return }
        if old.projectID != new.projectID, let last = store.lastEvent(["proposal"]), last.id == old.id,
           clock.now.timeIntervalSince(last.at) <= 600 {
            store.log("proposal-corrected", .item, old.id, at: clock.now)
        }
    }
}
