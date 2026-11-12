import Foundation

/// Phase 3, package S4: the mail read on the engine (spec 6.1, 7.4) and the new arrival for "waiting for" (8.7).
/// The read runs in the background through the source reader. The engine applies the result on its queue.
/// The PA never starts Mail, and never sends, moves, deletes, flags or marks a mail.
extension Engine {
    /// After this time with Mail in front, the PA reads one small batch.
    static let mailFrontWait: TimeInterval = 30 * 60
    /// At the first read, the PA makes this many flags or fewer (no flood).
    static let firstReadMaxFlags = 5

    /// The owner addresses in lower case: the setting, or the Mail accounts.
    func ownerAddresses(_ source: MailSource) -> Set<String> {
        let set = settings.owner.addresses
        let list = set.isEmpty ? ((try? source.accountAddresses()) ?? []) : set
        return Set(list.map { $0.lowercased() })
    }

    /// Call it from the tick. It starts a read if the time came, Mail runs, and no read runs.
    public func readMailIfDue() {
        guard settings.sources.mail, let source = mailSource, let store, !mailReading else { return }
        let now = clock.now
        if let last = lastMailRead, now.timeIntervalSince(last) < TimeInterval(max(1, settings.mail.everyMinutes) * 60) { return }
        guard source.isRunning else { return }
        var small = false
        if source.isFront {
            let since = mailFrontSince ?? now
            mailFrontSince = since
            guard now.timeIntervalSince(since) >= Engine.mailFrontWait else { return }
            small = true
        }
        lastMailRead = now
        let known = Set(((try? store.db.query("SELECT source_id FROM source_seen WHERE source = 'mail' AND result != 'retry'")) ?? [])
            .compactMap { $0[0].text })
        var plan = MailReadPlan(known: known, lastNewest: store.meta("mail.newest"), owner: [])
        plan.batch = max(1, settings.mail.batch)
        plan.maxLookBack = max(plan.batch, settings.mail.maxPerRead)
        if small { plan.maxMessages = 5; plan.maxTexts = 2 }
        let first = store.meta("mail.firstDone") == nil
        if first { plan.since = now.addingTimeInterval(-TimeInterval(settings.mail.firstDays) * 86400) }
        plan.openFlagIDs = store.openFlags().filter { $0.source == .mail }.map(\.sourceID)
        let reader = mailReader
        mailReading = true
        background { [weak self] in
            let outcome = reader.run { () -> MailReadPlan.Result in
                var p = plan
                p.owner = self?.ownerAddresses(source) ?? []
                return p.run(source)
            }
            self?.runLater(0) { [weak self] in
                guard let self else { return }
                self.mailReading = false
                switch outcome {
                case .done(let r):
                    self.applyMailRead(r, first: first)
                    if small { self.mailFrontSince = nil }
                case .failed, .timedOut, .busy:
                    self.log.write(self.clock.now, "mail-read-failed")
                }
            }
        }
    }

    /// Runs on the engine queue. Records what the read saw, sets answered flags, and makes the arrival flags.
    func applyMailRead(_ r: MailReadPlan.Result, first: Bool) {
        guard let store else { return }
        let now = clock.now
        var made = 0
        var budget = Int.max
        if first {
            budget = max(0, Engine.firstReadMaxFlags - (Int(store.meta("mail.firstFlags") ?? "0") ?? 0))
        }
        for id in r.failed { try? store.markSeen(.mail, id, .retry, at: now) }
        var forProject: [MailMessage] = []
        for s in r.seen {
            var result: SeenResult = s.bulk == nil ? .noRequest : .bulk
            if s.bulk == nil, made < budget, let it = waitingItem(for: s.message) {
                if (try? arrivalFlag(s.message, item: it)) != nil {
                    made += 1
                    result = .flag
                }
            }
            try? store.markSeen(.mail, s.message.id, result, at: now)
            if s.bulk == nil, s.hasText, result != .flag { forProject.append(s.message) }
        }
        for id in r.answered {
            for var f in store.openFlags() where f.source == .mail && f.sourceID == id {
                f.state = .answered
                f.answeredAt = now
                try? store.updateFlag(f)
                store.log("flag-answered", .flag, f.id, at: now)
            }
        }
        if r.complete, let n = r.newest { try? store.setMeta("mail.newest", n) }
        if first {
            try? store.setMeta("mail.firstFlags", String((Int(store.meta("mail.firstFlags") ?? "0") ?? 0) + made))
            if r.complete { try? store.setMeta("mail.firstDone", "1") }
        }
        log.write(now, "mail-read", ["seen": String(r.seen.count), "events": String(r.events), "flags": String(made),
                                     "ms": String(Int(r.seconds * 1000)), "complete": r.complete ? "1" : "0"])
        if made > 0 { markPagesDirty() }
        if !forProject.isEmpty, budget - made > 0 { projectArrivals(forProject, budget: budget - made, first: first) }
    }

    /// The text for the project rule: the subject and the first 500 characters (spec 8.7).
    static func arrivalText(_ m: MailMessage) -> String { m.subject + "\n" + String(m.text.prefix(500)) }

    /// Spec 8.7, for a project: the project rule version 2 as it is, on the owner records only. It needs the model,
    /// so it runs in the background. Each project gets one open arrival flag for each conversation.
    func projectArrivals(_ msgs: [MailMessage], budget: Int, first: Bool) {
        guard let models, !models.isFailed, let rules = models.rules, settings.rules.newArrival != .off, store != nil else { return }
        let owner = ownerRecords(model: models.modelID)
        guard !owner.isEmpty else { return }
        let projects = (store?.projects() ?? []).filter { $0.state == "open" }.map { (id: String($0.id), name: $0.name) }
        var rule = ProjectRuleV2()
        rule.byName = settings.proposeByName
        background { [weak self] in
            let texts = msgs.map(Engine.arrivalText)
            guard let vectors = models.embed(texts, kind: .passage), vectors.count == msgs.count else { return }
            var found: [(MailMessage, Int64)] = []
            for (i, m) in msgs.enumerated() {
                if let p = rule.propose(title: texts[i], vector: vectors[i], records: owner, projects: projects, floor: rules.searchFloor),
                   let id = Int64(p.project) { found.append((m, id)) }
            }
            self?.runLater(0) { [weak self] in self?.saveProjectArrivals(found, budget: budget, first: first) }
        }
    }

    func saveProjectArrivals(_ found: [(MailMessage, Int64)], budget: Int, first: Bool) {
        guard let store else { return }
        let now = clock.now
        var made = 0
        for (m, pid) in found where made < budget {
            guard let p = store.project(pid), p.state == "open",
                  settings.rules(project: p.name).newArrival != .off else { continue }
            var f = Flag(kind: .arrival, source: .mail, sourceID: m.id, sender: m.fromName.isEmpty ? m.fromAddress : m.fromName,
                         subject: m.subject, sentence: "", sourceAt: m.date, createdAt: now)
            f.messageID = m.messageID
            f.projectID = pid
            f.projectBy = "rule"
            guard (try? store.upsertFlag(f)) != nil else { continue }
            try? store.markSeen(.mail, m.id, .flag, at: now)
            made += 1
        }
        if first, made > 0 {
            try? store.setMeta("mail.firstFlags", String((Int(store.meta("mail.firstFlags") ?? "0") ?? 0) + made))
        }
        log.write(now, "mail-arrivals", ["flags": String(made)])
        if made > 0 { markPagesDirty() }
    }

    /// The open "waiting for" item that names the sender of the mail, if exactly one does.
    func waitingItem(for m: MailMessage) -> Item? {
        guard let store else { return nil }
        let hits = store.items(where: "state = 'open'").filter {
            Engine.waitingMatch(sender: m.fromName, title: $0.title.isEmpty ? $0.said : $0.title)
                || Engine.waitingMatch(sender: m.fromName, title: $0.said)
        }
        return hits.count == 1 ? hits[0] : nil
    }

    /// Spec 8.7: the title starts with "waiting for", and the first or the last name of the sender (3 letters or
    /// more, not a stop word or a title) is a whole word of the title, with a capital letter as in a name.
    /// "waiting for the may invoice" does not match "May Chen". "waiting for Samantha" does not match "Sam Lee".
    public static func waitingMatch(sender: String, title: String) -> Bool {
        var raw: [String] = []
        var cur = ""
        for ch in title {
            if ch.isLetter || ch == "'" || ch == "’" { cur.append(ch) } else if !cur.isEmpty { raw.append(cur); cur = "" }
        }
        if !cur.isEmpty { raw.append(cur) }
        raw = raw.map { w in
            for s in ["'s", "’s"] where w.lowercased().hasSuffix(s) { return String(w.dropLast(2)) }
            return w.trimmingCharacters(in: CharacterSet(charactersIn: "'’"))
        }
        guard raw.count >= 3, raw[0].lowercased() == "waiting", raw[1].lowercased() == "for" else { return false }
        let names = EventLinker.names([sender])
        guard !names.isEmpty else { return false }
        return raw.dropFirst(2).contains { w in
            guard let f = w.first, f.isUppercase else { return false }
            return names.contains(w.lowercased())
        }
    }

    /// Makes the arrival flag for a "waiting for" item, and starts the silence time of the item again.
    @discardableResult
    func arrivalFlag(_ m: MailMessage, item: Item) throws -> Int64 {
        guard let store else { throw SourceError("no store") }
        let now = clock.now
        var f = Flag(kind: .arrival, source: .mail, sourceID: m.id, sender: m.fromName.isEmpty ? m.fromAddress : m.fromName,
                     subject: m.subject, sentence: "", sourceAt: m.date, createdAt: now)
        f.messageID = m.messageID
        f.itemID = item.id
        f.projectID = item.projectID
        let id = try store.upsertFlag(f)
        var it = item
        it.updatedAt = now
        try store.update(it, event: "arrival", at: now)
        return id
    }
}
