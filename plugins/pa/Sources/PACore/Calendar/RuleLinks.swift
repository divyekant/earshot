import Foundation

/// Phase 3, package S3: links by a rule (9.2). The holdout run selected the lines L1+L2+L3: 24 alerts, 22 correct,
/// 2 wrong, 23 of 25 events with an alert (go mark passed). A link by a rule shows with "?".
extension Engine {
    static let ruleLines: EventLinker.Lines = [.l1, .l2, .l3]

    /// The state of the owner records. If it and the title of an event do not change, the links stay.
    func ruleLinkStamp() -> String {
        guard let store else { return "" }
        let r = (try? store.db.query("SELECT COUNT(*), MAX(updated_at) FROM item WHERE state = 'open'"))?.first
        let d = (try? store.db.query("SELECT COUNT(*) FROM doc WHERE dropped_at IS NULL AND project_id IS NOT NULL"))?.first
        return "\(r?[0].int ?? 0)/\(r?[1].real ?? 0)/\(d?[0].int ?? 0)"
    }

    /// Links the events of the next 14 days to the owner records by the rule. It reads the store on the engine queue,
    /// does the model work in the background, and writes the links on the engine queue. With no model, only the
    /// lines that need no model can link (L1 with a shared word, and L2).
    func linkEventsByRule() {
        guard settings.sources.calendar, settings.linkEvents, let store else { return }
        let now = clock.now
        let stamp = ruleLinkStamp()
        let events = store.events(from: now, to: now.addingTimeInterval(Engine.calendarDays))
            .filter { ruleLinkTitles[$0.id] != $0.title + "\n" + stamp }
        guard !events.isEmpty else { return }
        let projects = store.projects().filter { $0.state == "open" }
        let linkProjects = projects.map { EventLinker.Project(key: String($0.id), name: $0.name, aliases: $0.aliases) }
        var records: [EventLinker.Record] = []
        for it in store.items(where: "state = 'open'") {
            records.append(.init(key: "i\(it.id)", project: it.projectID.map { String($0) }, title: it.title.isEmpty ? it.said : it.title,
                                 due: it.dueOn, order: it.createdAt.timeIntervalSince1970))
        }
        for p in projects {
            for d in store.docs(project: p.id) where d.droppedAt == nil {
                records.append(.init(key: "d\(d.id)", project: String(p.id), title: d.title, isDoc: true,
                                     order: d.createdAt.timeIntervalSince1970))
            }
        }
        let models = self.models.flatMap { $0.isFailed ? nil : $0 }
        let rules = models?.rules
        let owner = models.map { ownerRecords(model: $0.modelID) } ?? []
        let ruleProjects = projects.map { (id: String($0.id), name: $0.name) }
        let cal = clock.calendar
        let linker = EventLinker(lines: Engine.ruleLines)
        background { [weak self] in
            var vectors: [[Float]]?
            if let models, rules != nil, !owner.isEmpty {
                vectors = models.embed(events.map(\.title), kind: .passage)?.map(Vectors.normalized)
            }
            var found: [(CalEvent, EventLinker.Result)] = []
            for (i, e) in events.enumerated() {
                var nearest: [String?] = []
                var ruleProject: String?
                if let vectors, vectors.count == events.count, let rules {
                    let v = vectors[i]
                    nearest = owner.indices.sorted { Vectors.dot(owner[$0].vector, v) > Vectors.dot(owner[$1].vector, v) }
                        .prefix(5).map { Optional(owner[$0].project) }
                    ruleProject = ProjectRuleV2().propose(title: e.title, vector: v, records: owner, projects: ruleProjects,
                                                          floor: rules.searchFloor)?.project
                }
                found.append((e, linker.link(title: e.title, people: e.people, day: Day(e.startsAt, cal), projects: linkProjects,
                                             records: records, nearest: nearest, ruleProject: ruleProject)))
            }
            self?.runLater(0) { [weak self] in self?.saveRuleLinks(found, stamp: stamp) }
        }
    }

    /// Runs on the engine queue. Replaces the links by a rule of each event.
    func saveRuleLinks(_ found: [(CalEvent, EventLinker.Result)], stamp: String) {
        guard let store else { return }
        let now = clock.now
        var linked = 0
        for (e, r) in found {
            // The event can be gone or changed since the start of the work.
            guard let cur = store.events(from: e.startsAt, to: e.startsAt.addingTimeInterval(1)).first(where: { $0.id == e.id }),
                  cur.title == e.title else { continue }
            do {
                try store.db.transaction {
                    try store.deleteRuleLinks(e.id)
                    let owned = store.eventLinks(e.id)
                    for k in r.items {
                        guard let id = Int64(k.dropFirst()), !owned.contains(where: { $0.itemID == id }) else { continue }
                        try store.addEventLink(EventLink(eventID: e.id, itemID: id, by: "rule"), at: now)
                    }
                    for k in r.docs {
                        guard let id = Int64(k.dropFirst()), !owned.contains(where: { $0.docID == id }) else { continue }
                        try store.addEventLink(EventLink(eventID: e.id, docID: id, by: "rule"), at: now)
                    }
                }
                ruleLinkTitles[e.id] = e.title + "\n" + stamp
                if !r.isEmpty { linked += 1 }
            } catch {
                log.write(now, "event-link-error")
            }
        }
        log.write(now, "event-rule-links", ["events": String(found.count), "linked": String(linked)])
    }

    /// The text of a linked record in the alert: with "?" if only the rule linked it.
    func linkedLine(_ title: String, byOwner: Bool) -> String { byOwner ? title : title + "?" }
}
