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
        if which.contains("mail2") { result["mail2"] = mail2() }
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

    // MARK: - P2, run 2 (spec 6.1): small events, variants, "Mail stays usable"

    /// The pause between two Apple events (spec 6.1, rule 1).
    static let pause: TimeInterval = 0.2

    static func median(_ v: [Int]) -> Int {
        guard !v.isEmpty else { return -1 }
        return v.sorted()[v.count / 2]
    }

    /// The slowest 1 in 10: the value at 90 %.
    static func p90(_ v: [Int]) -> Int {
        guard !v.isEmpty else { return -1 }
        let s = v.sorted()
        return s[min(s.count - 1, Int((Double(s.count) * 0.9).rounded(.up)) - 1)]
    }

    static func stats(_ v: [Int]) -> [String: Int] {
        ["n": v.count, "median": median(v), "p90": p90(v), "max": v.max() ?? -1, "sum": v.reduce(0, +)]
    }

    /// One event and a pause. Every time goes into `all`, for the mark "one Apple event 1.5 s or less".
    static func timed(_ script: String, _ all: inout [Int], errors: inout Int) -> (NSAppleEventDescriptor?, Int) {
        let (d, t, e) = run(script)
        all.append(t)
        if e != nil { errors += 1 }
        Thread.sleep(forTimeInterval: pause)
        return (d, t)
    }

    /// A second process sends a small event to Mail (osascript). Gives its time in ms, or -1 for an error.
    static func ping() -> Int {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", AppleScripts.mailPing]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let t0 = Date()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus == 0 ? ms(t0) : -1
    }

    /// Runs one event while a second process pings Mail 100 ms after the start. Gives the event time and the ping.
    static func withPing(_ script: String, _ all: inout [Int], errors: inout Int) -> (NSAppleEventDescriptor?, Int, Int) {
        var pingMs = -1
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            pingMs = ping()
            done.signal()
        }
        let (d, t, e) = run(script)
        all.append(t)
        if e != nil { errors += 1 }
        _ = done.wait(timeout: .now() + 30)
        Thread.sleep(forTimeInterval: pause)
        return (d, t, pingMs)
    }

    static func mail2() -> [String: Any] {
        var r: [String: Any] = [:]
        r["runningBefore"] = running(mailID)
        guard running(mailID) else {
            r["skipped"] = "Mail does not run"
            return r
        }
        r["mailInFront"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == mailID
        r["access"] = automation(mailID, ask: false)
        guard r["access"] as? String == "allowed" else { return r }
        let start = Date()
        var all: [Int] = []
        var errors = 0

        // Ping with no read, as the base.
        var basePings: [Int] = []
        for _ in 0..<3 { basePings.append(ping()); Thread.sleep(forTimeInterval: pause) }
        r["pingNoRead"] = stats(basePings)

        // The cheap check: the unified inbox against the inbox of each account.
        var unified: [Int] = []
        for _ in 0..<10 { unified.append(timed(AppleScripts.mailNewestID, &all, errors: &errors).1) }
        r["cheapCheckUnified"] = stats(unified)
        let accounts = Int(timed(AppleScripts.mailAccountCount, &all, errors: &errors).0?.int32Value ?? 0)
        r["accounts"] = accounts
        var perAccount: [[String: Int]] = []
        for k in 1...max(1, min(accounts, 5)) where accounts > 0 {
            var v: [Int] = [], errs = 0
            for _ in 0..<5 {
                let (_, t, e) = run(AppleScripts.limited(AppleScripts.mailAccountNewestID, 1, account: k))
                v.append(t); all.append(t)
                if e != nil { errs += 1 }
                Thread.sleep(forTimeInterval: pause)
            }
            var s = stats(v); s["errors"] = errs
            perAccount.append(s)
        }
        r["cheapCheckAccountInbox"] = perAccount

        // The ids of the 10 newest: one list event against 10 single events.
        var listIDs: [Int] = []
        for _ in 0..<3 { listIDs.append(timed(AppleScripts.limited(AppleScripts.mailInboxIDs, 10), &all, errors: &errors).1) }
        r["ids10OneEvent"] = stats(listIDs)
        var singleIDs: [Int] = []
        for i in 1...10 { singleIDs.append(timed(AppleScripts.limited(AppleScripts.mailIDOne, i), &all, errors: &errors).1) }
        r["ids10SingleEvents"] = stats(singleIDs)

        // The id and the date: one event against two.
        var idDate: [Int] = [], dateOnly: [Int] = []
        for i in 1...10 {
            idDate.append(timed(AppleScripts.limited(AppleScripts.mailIDDateOne, i), &all, errors: &errors).1)
            dateOnly.append(timed(AppleScripts.limited(AppleScripts.mailDateOne, i), &all, errors: &errors).1)
        }
        r["idDateOneEvent"] = stats(idDate)
        r["idThenDateTwoEvents"] = stats(zip(singleIDs, dateOnly).map { $0 + $1 })

        // Headers: all headers against the header facts, and the full envelope that the reader needs.
        var allHeaders: [Int] = [], facts: [Int] = [], envelope: [Int] = [], envelopePings: [Int] = []
        var listHeader = 0, bulk = 0, auto = 0
        for i in 1...10 {
            allHeaders.append(timed(AppleScripts.limited(AppleScripts.mailAllHeadersOne, i), &all, errors: &errors).1)
            let (f, ft) = timed(AppleScripts.limited(AppleScripts.mailHeaderFactsOne, i), &all, errors: &errors)
            facts.append(ft)
            if let f, f.numberOfItems >= 3 {
                var names: [String] = []
                if let n = f.atIndex(1) {
                    for j in stride(from: 1, through: n.numberOfItems, by: 1) { names.append((n.atIndex(j)?.stringValue ?? "").lowercased()) }
                }
                if names.contains("list-unsubscribe") || names.contains("list-id") { listHeader += 1 }
                let prec = (f.atIndex(2)?.atIndex(1)?.stringValue ?? "").lowercased()
                if ["bulk", "list", "junk"].contains(where: { prec.contains($0) }) { bulk += 1 }
                let auto1 = (f.atIndex(3)?.atIndex(1)?.stringValue ?? "").lowercased()
                if !auto1.isEmpty && !auto1.hasPrefix("no") { auto += 1 }
            }
            let (_, et, ep) = withPing(AppleScripts.limited(AppleScripts.mailEnvelopeOne, i), &all, errors: &errors)
            envelope.append(et); envelopePings.append(ep)
        }
        r["allHeadersOne"] = stats(allHeaders)
        r["headerFactsOne"] = stats(facts)
        r["envelopeOne"] = stats(envelope)
        r["pingDuringEnvelope"] = stats(envelopePings)
        r["factsIn10"] = ["listHeader": listHeader, "bulkPrecedence": bulk, "autoSubmitted": auto]

        // Text, one message for each event, with a ping during each.
        var texts: [Int] = [], textPings: [Int] = [], chars = 0
        for i in 1...5 {
            let (d, t, p) = withPing(AppleScripts.limited(AppleScripts.mailContentOne, i), &all, errors: &errors)
            texts.append(t); textPings.append(p)
            chars += d?.stringValue?.count ?? 0
        }
        r["textOne"] = stats(texts)
        r["pingDuringText"] = stats(textPings)
        r["textChars"] = chars

        // A read as the plan does it: cheap check, ids, 5 envelopes, 2 texts, with the pauses.
        let t0 = Date()
        var readAE: [Int] = []
        var e2 = 0
        _ = timed(AppleScripts.mailNewestID, &readAE, errors: &e2)
        _ = timed(AppleScripts.limited(AppleScripts.mailInboxIDs, 10), &readAE, errors: &e2)
        for i in 6...10 { _ = timed(AppleScripts.limited(AppleScripts.mailEnvelopeOne, i), &readAE, errors: &e2) }
        for i in 6...7 { _ = timed(AppleScripts.limited(AppleScripts.mailContentOne, i), &readAE, errors: &e2) }
        all += readAE
        errors += e2
        r["read5And2"] = ["wallMs": ms(t0), "appleEventMs": readAE.reduce(0, +), "events": readAE.count]

        r["allEvents"] = stats(all)
        r["errors"] = errors
        r["totalMs"] = ms(start)
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
