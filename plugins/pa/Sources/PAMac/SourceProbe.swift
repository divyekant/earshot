#if os(macOS)
import AppKit
import CoreServices
import EventKit
import Foundation
import PACore

/// Phase 3, package S1: the probes P1 to P4 (phase 3 build spec, section 6). Each probe gives numbers only: counts,
/// times and permission states. It gives no subject, sender, title or text (rule 5).
/// The PA runs the probes when the file `probe-request` is in its data folder (one line: the sources, for example
/// "calendar,mail,notes"). It writes `probe-result.json` and deletes the request.
public enum SourceProbe {
    public static let mailID = "com.apple.mail"
    public static let notesID = "com.apple.Notes"

    /// Runs the probes of the request file, if it exists. Call it off the main thread.
    public static func runIfRequested(folder: URL) {
        let req = folder.appendingPathComponent("probe-request")
        guard let line = try? String(contentsOf: req, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: req)
        let which = Set(line.split(whereSeparator: { ",; \n".contains($0) }).map { $0.lowercased() })
        var result: [String: Any] = ["started": ISO8601DateFormatter().string(from: Date())]
        if which.contains("calendar") { result["calendar"] = calendar() }
        if which.contains("mail") { result["mail"] = mail() }
        if which.contains("notes") { result["notes"] = notes() }
        result["reminders"] = reminderState()
        result["ended"] = ISO8601DateFormatter().string(from: Date())
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("probe-result.json"))
        }
    }

    static func ms(_ t0: Date) -> Int { Int(Date().timeIntervalSince(t0) * 1000) }

    static func reminderState() -> String {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return "allowed"
        case .notDetermined: return "not asked"
        case .writeOnly: return "write only"
        default: return "denied"
        }
    }

    // MARK: - P1 Calendar

    static func calendar() -> [String: Any] {
        var r: [String: Any] = [:]
        func state() -> String {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: return "allowed"
            case .notDetermined: return "not asked"
            case .writeOnly: return "write only"
            default: return "denied"
            }
        }
        r["accessBefore"] = state()
        let store = EKEventStore()
        if state() == "not asked" {
            let sem = DispatchSemaphore(value: 0)
            let t0 = Date()
            store.requestFullAccessToEvents { _, _ in sem.signal() }
            _ = sem.wait(timeout: .now() + 300)
            r["askMs"] = ms(t0)
        }
        r["accessAfter"] = state()
        guard state() == "allowed" else { return r }
        let t0 = Date()
        let cals = store.calendars(for: .event)
        let pred = store.predicateForEvents(withStart: Date(), end: Date().addingTimeInterval(7 * 86400), calendars: cals)
        let events = store.events(matching: pred)
        r["events7Days"] = events.count
        r["allDay"] = events.filter(\.isAllDay).count
        r["calendars"] = cals.count
        r["readMs"] = ms(t0)
        return r
    }

    // MARK: - Apple events

    static func running(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// The Automation permission for an app: "allowed", "would ask", "denied", "not running" or an error code.
    /// With `ask`, macOS shows the question if it was not asked. It never starts the app (only a running app).
    static func automation(_ bundleID: String, ask: Bool) -> String {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return "no target" }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        switch status {
        case noErr: return "allowed"
        case OSStatus(errAEEventWouldRequireUserConsent): return "would ask"
        case OSStatus(errAEEventNotPermitted): return "denied"
        case OSStatus(procNotFound): return "not running"
        default: return "error \(status)"
        }
    }

    /// Runs one fixed script on the main thread. Gives the result and the time.
    static func run(_ source: String) -> (NSAppleEventDescriptor?, Int, Int?) {
        var out: NSAppleEventDescriptor?
        var code: Int?
        let t0 = Date()
        let work = {
            var err: NSDictionary?
            out = NSAppleScript(source: source)?.executeAndReturnError(&err)
            if let e = err?[NSAppleScript.errorNumber] as? Int { code = e }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        return (out, ms(t0), code)
    }

    static func listCount(_ d: NSAppleEventDescriptor?) -> Int {
        guard let d else { return 0 }
        return d.numberOfItems
    }

    static func textLength(_ d: NSAppleEventDescriptor?) -> Int {
        guard let d else { return 0 }
        var n = 0
        for i in stride(from: 1, through: d.numberOfItems, by: 1) { n += d.atIndex(i)?.stringValue?.count ?? 0 }
        return n
    }

    // MARK: - P2 Mail

    static func mail() -> [String: Any] {
        var r: [String: Any] = [:]
        r["runningBefore"] = running(mailID)
        guard running(mailID) else {
            r["skipped"] = "Mail does not run"
            return r
        }
        r["accessBefore"] = automation(mailID, ask: false)
        let t0 = Date()
        r["accessAfter"] = automation(mailID, ask: true)
        r["askMs"] = ms(t0)
        guard r["accessAfter"] as? String == "allowed" else { return r }
        let (count, countMs, countErr) = run(AppleScripts.mailInboxCount)
        let total = Int(count?.int32Value ?? 0)
        r["inboxCount"] = total
        r["countMs"] = countMs
        if let countErr { r["countError"] = countErr }
        let n = min(50, total)
        guard n > 0 else { return r }
        let (ids, idsMs, idsErr) = run(AppleScripts.limited(AppleScripts.mailInboxIDs, n))
        r["ids"] = listCount(ids); r["idsMs"] = idsMs
        if let idsErr { r["idsError"] = idsErr }
        let (dates, datesMs, _) = run(AppleScripts.limited(AppleScripts.mailInboxDates, n))
        r["datesMs"] = datesMs
        // The order of the inbox: true if each message is as new as the next one or newer.
        var times: [Double] = []
        if let dates {
            for i in stride(from: 1, through: dates.numberOfItems, by: 1) {
                if let d = dates.atIndex(i)?.dateValue { times.append(d.timeIntervalSince1970) }
            }
        }
        r["newestFirst"] = times.count > 1 && zip(times, times.dropFirst()).allSatisfy { $0 >= $1 }
        let (headers, headersMs, headersErr) = run(AppleScripts.limited(AppleScripts.mailInboxHeaders, n))
        r["headers"] = listCount(headers); r["headersMs"] = headersMs
        if let headersErr { r["headersError"] = headersErr }
        // The header facts of section 7.4, as counts only.
        var unsub = 0, bulk = 0, auto = 0
        if let headers {
            for i in stride(from: 1, through: headers.numberOfItems, by: 1) {
                let h = (headers.atIndex(i)?.stringValue ?? "").lowercased()
                if h.contains("\nlist-unsubscribe:") || h.contains("\nlist-id:") || h.hasPrefix("list-unsubscribe:") { unsub += 1 }
                if h.contains("\nprecedence: bulk") || h.contains("\nprecedence: list") || h.contains("\nprecedence: junk") { bulk += 1 }
                if h.contains("\nauto-submitted:") && !h.contains("\nauto-submitted: no") { auto += 1 }
            }
        }
        r["withListHeader"] = unsub; r["withBulkPrecedence"] = bulk; r["autoSubmitted"] = auto
        r["headerReadMs"] = idsMs + datesMs + headersMs
        let m = min(20, total)
        let (content, contentMs, contentErr) = run(AppleScripts.limited(AppleScripts.mailInboxContent, m))
        r["texts"] = listCount(content); r["textMs"] = contentMs; r["textChars"] = textLength(content)
        if let contentErr { r["textError"] = contentErr }
        r["runningAfter"] = running(mailID)
        return r
    }

    // MARK: - P3 Notes

    static func notes() -> [String: Any] {
        var r: [String: Any] = [:]
        r["runningBefore"] = running(notesID)
        guard running(notesID) else {
            r["skipped"] = "Notes does not run"
            return r
        }
        r["accessBefore"] = automation(notesID, ask: false)
        let t0 = Date()
        r["accessAfter"] = automation(notesID, ask: true)
        r["askMs"] = ms(t0)
        guard r["accessAfter"] as? String == "allowed" else { return r }
        let (count, countMs, _) = run(AppleScripts.notesCount)
        let total = Int(count?.int32Value ?? 0)
        r["notesCount"] = total; r["countMs"] = countMs
        let n = min(50, total)
        guard n > 0 else { return r }
        let start = Date()
        let (locked, lockedMs, lockedErr) = run(AppleScripts.limited(AppleScripts.notesLocked, n))
        r["lockedMs"] = lockedMs
        if let lockedErr { r["lockedError"] = lockedErr }
        let (names, namesMs, _) = run(AppleScripts.limited(AppleScripts.notesNames, n))
        let (_, datesMs, _) = run(AppleScripts.limited(AppleScripts.notesDates, n))
        r["names"] = listCount(names); r["namesMs"] = namesMs; r["datesMs"] = datesMs
        var lockedCount = 0, read = 0, chars = 0, errors = 0
        for i in 1...n {
            if locked?.atIndex(i)?.booleanValue == true { lockedCount += 1; continue }
            let (text, _, err) = run(AppleScripts.limited(AppleScripts.notesPlainText, i))
            if err != nil { errors += 1; continue }
            read += 1
            chars += text?.stringValue?.count ?? 0
        }
        r["locked"] = lockedCount; r["textsRead"] = read; r["textChars"] = chars; r["textErrors"] = errors
        r["totalMs"] = ms(start)
        r["runningAfter"] = running(notesID)
        return r
    }
}
#endif
