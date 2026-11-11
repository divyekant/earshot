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
        // The names of projects with no numbers yet are embedded in the same job.
        let have = index?.vectorOwners(.project, model: models.modelID) ?? []
        let names = propose ? (store?.projects() ?? []).filter { !have.contains($0.id) } : []
        let texts = [title] + names.map(\.name)
        let model = models.modelID
        background { [weak self] in
            let vectors = models.embed(texts, kind: .passage)
            self?.runLater(0) { [weak self] in
                guard let self, let vectors, vectors.count == texts.count else { return }
                try? self.index?.putVectors(.item, [(it.id, vectors[0])], model: model)
                self.vectorCache?.items[it.id] = vectors[0]
                if !names.isEmpty {
                    try? self.index?.putVectors(.project, zip(names.map(\.id), vectors.dropFirst()).map { ($0, $1) }, model: model)
                }
                self.secondNote(it.id, vectors[0], propose: propose, duplicates: duplicates, rules: rules, model: model)
            }
        }
    }

    /// Runs on the engine queue. Sends at most one note with the proposal and the duplicate.
    func secondNote(_ itemID: Int64, _ v: [Float], propose: Bool, duplicates: Bool, rules: ModelRules, model: String) {
        guard let store, let index, var it = store.item(itemID), it.state == .open else { return }
        var proposed: Project?
        if propose, it.projectID == nil {
            let profiles = projectProfiles(model: model)
            let scores = profiles.map { ($0.0, Vectors.dot(v, $0.1)) }
            let rule = ProjectRule(a: rules.projectA, b: rules.projectB)
            if let name = rule.propose(scores.map { (String($0.0.id), $0.1) }), let p = profiles.first(where: { String($0.0.id) == name })?.0 {
                let old = it
                it.projectID = p.id
                it.projectBy = "search"
                it.projectScore = Double(scores.first { $0.0.id == p.id }?.1 ?? 0)
                it.updatedAt = clock.now
                if (try? store.update(it, event: "proposal", at: clock.now)) != nil {
                    itemChanged(it, old: old)
                    proposed = p
                }
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

    /// The profile of each open project with 3 or more items or passages: the mean of the numbers of its name,
    /// its item titles and its passages (7.6). Projects with no numbers for the name are left out.
    func projectProfiles(model: String) -> [(Project, [Float])] {
        guard let store, let index else { return [] }
        let names = Dictionary(uniqueKeysWithValues: index.vectors(.project, model: model).map { ($0.0, $0.1) })
        let items = Dictionary(uniqueKeysWithValues: index.vectors(.item, model: model).map { ($0.0, $0.1) })
        let passages = Dictionary(uniqueKeysWithValues: index.vectors(.passage, model: model).map { ($0.0, $0.1) })
        var out: [(Project, [Float])] = []
        for p in store.projects() {
            guard let nv = names[p.id] else { continue }
            var parts: [[Float]] = [nv]
            // Only the items that the owner set: a proposal does not feed the next proposal.
            for it in store.items(where: "project_id = ? AND state != 'dropped' AND (project_by IS NULL OR project_by = 'owner')", [.int(p.id)]) {
                if let v = items[it.id] { parts.append(v) }
            }
            for d in store.docs(project: p.id) {
                for row in index.passages(doc: d.id) { if let v = passages[row.id] { parts.append(v) } }
            }
            guard parts.count - 1 >= 3 else { continue }
            // Not normalized: the bench found A and B with the plain mean (E10).
            out.append((p, Vectors.mean(parts)))
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
