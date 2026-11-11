import Foundation

/// Changes to an item: done, snooze, drop, move (build spec 9.6).
extension Engine {
    enum Pick {
        case item(Item)
        case doc(Doc)
        /// The answer to send: no item, or a list of choices.
        case answer(Outgoing)
    }

    /// A number at the start: "2", "two", "number 2", "#2". Gives the number and the words after it.
    static func leadingNumber(_ text: String) -> (Int, String)? {
        var parts = text.split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return nil }
        if ["number", "no", "item"].contains(parts[0].lowercased()), parts.count > 1 { parts.removeFirst() }
        let w = parts[0].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#.,"))
        let words: [String: Int] = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
                                    "eight": 8, "nine": 9, "ten": 10, "first": 1, "second": 2, "third": 3, "fourth": 4,
                                    "fifth": 5, "to": 2, "too": 2, "for": 4]
        var n = Int(w)
        // "to" and "for" are numbers only when they are the only word ("done to"): speech can write "2" as "to".
        if n == nil, let v = words[w], !(["to", "too", "for"].contains(w) && parts.count > 1) { n = v }
        guard let n else { return nil }
        return (n, parts.dropFirst().joined(separator: " "))
    }

    /// Finds the item of a change (build spec 9.6): a number in the last list; "that", "it" or no words; or words.
    func pick(_ cmd: PACommand, _ id: String, _ target: String) -> Pick {
        guard let store else { return .answer(.note(id, "The PA store does not open.")) }
        let t = TimeReader.tidy(target)
        if let (n, _) = Engine.leadingNumber(t), t.split(separator: " ").count <= 2 {
            guard let (kind, rid) = store.lastList(n) else { return .answer(.note(id, "No item \(n) in the last list.")) }
            if kind == .item, let it = store.item(rid) { return .item(it) }
            if kind == .doc, let d = store.doc(rid) { return .doc(d) }
            return .answer(.note(id, "No item \(n) in the last list."))
        }
        let lower = t.lowercased()
        if lower.isEmpty || ["that", "it", "this", "the last one", "that one", "this one"].contains(lower) {
            if cmd == .done || cmd == .snooze, let it = lastAlertItem() { return .item(it) }
            if let last = store.lastEvent(["capture", "keep"]), let rid = last.id {
                if last.kind == .item, let it = store.item(rid), it.state != .dropped { return .item(it) }
                if last.kind == .doc, let d = store.doc(rid), d.droppedAt == nil { return .doc(d) }
            }
            return .answer(.note(id, "Say the number of the item."))
        }
        // Words: the open items that have all the words.
        let words = Engine.searchWords(t)
        let open = store.openItems().filter { it in
            let hay = Engine.words(it.title + " " + it.said)
            return words.allSatisfy { w in hay.contains { $0.hasPrefix(w) } }
        }
        if open.count == 1 { return .item(open[0]) }
        if open.isEmpty { return .answer(.note(id, "No open item for \(t).")) }
        return .answer(listAnswer(id, title: "Which one? Say the command with a number.",
                                  records: open.map { (.item, $0.id, line($0)) }))
    }

    /// The item of the last alert in the last 10 minutes.
    func lastAlertItem() -> Item? {
        guard let store else { return nil }
        let since = clock.now.addingTimeInterval(-600).timeIntervalSince1970
        let a = store.alerts(where: "item_id IS NOT NULL AND shown_at IS NOT NULL AND shown_at >= ?", [.real(since)],
                             order: "shown_at DESC").first
        guard let iid = a?.itemID, let it = store.item(iid), it.state == .open else { return nil }
        return it
    }

    func save(_ it: Item, old: Item, event: String) -> Bool {
        guard let store else { return false }
        do { try store.update(it, event: event, at: clock.now) } catch { return false }
        itemChanged(it, old: old)
        return true
    }

    func done(id: String, text: String) -> Outgoing {
        switch pick(.done, id, Engine.clean(text)) {
        case .answer(let a): return a
        case .doc(let d): return .note(id, "\(d.title) is a document. Say \"drop\" to remove it.")
        case .item(var it):
            let old = it
            it.state = .done
            it.doneAt = clock.now
            it.updatedAt = clock.now
            guard save(it, old: old, event: "done") else { return .note(id, "The store had an error. Nothing changed.") }
            return .note(id, "Done · \(it.title)")
        }
    }

    func drop(id: String, text: String) -> Outgoing {
        switch pick(.drop, id, Engine.clean(text)) {
        case .answer(let a): return a
        case .doc(var d):
            d.droppedAt = clock.now
            do { try store?.updateDoc(d, event: "drop", at: clock.now) } catch { return .note(id, "The store had an error. Nothing changed.") }
            forgetText(d.id)
            docsChanged()
            return .note(id, "Dropped · \(d.title)")
        case .item(var it):
            let old = it
            it.state = .dropped
            it.droppedAt = clock.now
            it.updatedAt = clock.now
            guard save(it, old: old, event: "drop") else { return .note(id, "The store had an error. Nothing changed.") }
            return .note(id, "Dropped · \(it.title)")
        }
    }

    /// Splits the words of "snooze" into the target and the time words. Gives nil time words for the default time.
    /// "2 to tomorrow morning", "2 for 20 minutes", "the plumber until 5", "2 tomorrow", "tomorrow", "2", "".
    func splitSnooze(_ text: String) -> (target: String, time: String?) {
        let parts = text.split(separator: " ").map(String.init)
        let reader = TimeReader(calendar: clock.calendar, settings: settings)
        func readable(_ s: String) -> Bool {
            let r = reader.read(s, now: clock.now)
            return r.kind != .none && r.rest.isEmpty
        }
        for i in stride(from: parts.count - 1, through: 0, by: -1) where ["to", "until", "till", "for"].contains(parts[i].lowercased()) {
            var time = parts[(i + 1)...].joined(separator: " ")
            if parts[i].lowercased() == "for" { time = "in " + time }
            if readable(time) { return (parts[..<i].joined(separator: " "), time) }
            if parts[i].lowercased() != "for" && readable("at " + time) { return (parts[..<i].joined(separator: " "), "at " + time) }
        }
        if let (n, rest) = Engine.leadingNumber(text) {
            return (String(n), rest.isEmpty ? nil : rest)
        }
        if !text.isEmpty && readable(text) { return ("", text) }
        return (text, nil)
    }

    func snooze(id: String, text: String) -> Outgoing {
        let now = clock.now
        let (target, timeWords) = splitSnooze(Engine.clean(text))
        var at: Date
        if let timeWords {
            let r = TimeReader(calendar: clock.calendar, settings: settings).read(timeWords, now: now)
            guard r.kind != .none, r.rest.isEmpty else { return .note(id, "No time. Nothing changed.") }
            if let a = r.at { at = a }
            else if let d = r.day {
                let m = settings.dayParts.morning
                at = d.date(clock.calendar, hour: m.hour, minute: m.minute)
            } else { return .note(id, "No time. Nothing changed.") }
        } else {
            at = now.addingTimeInterval(TimeInterval(settings.defaultSnoozeMinutes * 60))
        }
        switch pick(.snooze, id, target) {
        case .answer(let a): return a
        case .doc(let d): return .note(id, "\(d.title) is a document. It has no time.")
        case .item(var it):
            let old = it
            it.remindAt = at
            it.hasClock = true
            if it.kind == .todo || it.dueOn != nil { it.dueOn = Day(at, clock.calendar) }
            if it.kind == .note { it.kind = .reminder }
            it.updatedAt = now
            guard save(it, old: old, event: "snooze") else { return .note(id, "The store had an error. Nothing changed.") }
            return .note(id, "Snoozed · \(TimeText.moment(at, now: now, clock.calendar, locale: clock.locale)) · \(it.title)")
        }
    }

    func move(id: String, text: String) -> Outgoing {
        guard let store else { return .note(id, "The PA store does not open.") }
        let t = Engine.clean(text)
        let parts = t.split(separator: " ").map(String.init)
        guard let toIndex = parts.lastIndex(where: { ["to", "into", "in"].contains($0.lowercased()) }) else {
            return .note(id, "Say the project: \"move 2 to kitchen\".")
        }
        let target = parts[..<toIndex].joined(separator: " ")
        let name = Engine.dropFirst(parts[(toIndex + 1)...].joined(separator: " "), ["the", "project"])
        var project: Project?
        if !["no project", "none", "nothing"].contains(name.lowercased()) {
            guard let p = store.project(named: name) else { return .note(id, "No project \(name).") }
            project = p
        }
        switch pick(.move, id, target) {
        case .answer(let a): return a
        case .doc(var d):
            d.projectID = project?.id
            do { try store.updateDoc(d, event: "move", at: clock.now) } catch { return .note(id, "The store had an error. Nothing changed.") }
            docsChanged()
            return .note(id, "Moved · \(project?.name ?? "no project") · \(d.title)")
        case .item(var it):
            let old = it
            it.projectID = project?.id
            it.projectBy = project == nil ? nil : "owner"
            it.projectScore = nil
            it.updatedAt = clock.now
            countCorrection(old: old, new: it)
            guard save(it, old: old, event: "move") else { return .note(id, "The store had an error. Nothing changed.") }
            if project == nil { endFocus() }
            return .note(id, "Moved · \(project?.name ?? "no project") · \(it.title)")
        }
    }
}
