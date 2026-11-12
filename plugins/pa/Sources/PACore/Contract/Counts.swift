import Foundation

/// The counts of real use (phase 5, X5): `earshot-pa --counts`. The output is one JSON object with numbers only, for
/// the last 7 days and in total. It has no text of the store: no title, no sender, no address, no sentence.
///
/// The only string values are the date of the run and the version of the form. A test checks this.
public enum Counts {
    /// The version of the output form. Change it when a key changes.
    public static let version = "1"

    /// The counts that the PA cannot see. earshot opens a target itself (docs/PLUGINS.md, 5.2.1), so the PA does not
    /// know about "open 2" after a search. The value of each key is null.
    public static let notSeen = ["openAfterSearch"]

    /// Reads pa.sqlite and index.sqlite in the data folder, and the settings. It writes nothing.
    public static func compute(folder: URL, now: Date = Date()) -> [String: Any] {
        // Open only files that exist: a new file would be a write.
        func open(_ name: String) -> SQLite? {
            let path = folder.appendingPathComponent(name).path
            return FileManager.default.fileExists(atPath: path) ? try? SQLite(path: path) : nil
        }
        let pa = open("pa.sqlite"), index = open("index.sqlite")
        defer { pa?.close(); index?.close() }
        // Load writes a new settings file if none exists. This command writes nothing, so it reads only a file that exists.
        let settingsURL = folder.appendingPathComponent("settings.json")
        let settings = FileManager.default.fileExists(atPath: settingsURL.path) ? PASettings.load(settingsURL).settings : PASettings()
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        var out: [String: Any] = [
            "version": version,
            "at": ISO8601DateFormatter().string(from: now),
            "last7Days": section(pa: pa, index: index, since: weekAgo, settings: settings),
            "total": section(pa: pa, index: index, since: nil, settings: settings),
        ]
        // The day from which the command counts are true: the first event of a command.
        if let first = number(pa, "SELECT MIN(at) FROM event WHERE type LIKE 'command-%'", []) as Double?, first > 0 {
            out["commandCountsFrom"] = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: first))
        } else {
            out["commandCountsFrom"] = NSNull()
        }
        return out
    }

    /// One JSON line, keys sorted.
    public static func json(folder: URL, now: Date = Date()) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: compute(folder: folder, now: now), options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func section(pa: SQLite?, index: SQLite?, since: Date?, settings: PASettings) -> [String: Any] {
        let t = since?.timeIntervalSince1970 ?? -Double.greatestFiniteMagnitude
        func count(_ db: SQLite?, _ sql: String, _ params: [SQLValue] = []) -> Int {
            Int((number(db, sql, [.real(t)] + params) as Int64?) ?? 0)
        }
        func events(_ type: String, kind: String? = nil) -> Int {
            if let kind {
                return count(pa, "SELECT COUNT(*) FROM event WHERE at >= ? AND type = ? AND record_kind = ?", [.text(type), .text(kind)])
            }
            return count(pa, "SELECT COUNT(*) FROM event WHERE at >= ? AND type = ?", [.text(type)])
        }
        // Captures by kind. A file of a kept folder is not a capture of the owner.
        var captures: [String: Int] = [:]
        for k in ItemKind.allCases {
            captures[k.rawValue] = count(pa, "SELECT COUNT(*) FROM item WHERE created_at >= ? AND kind = ?", [.text(k.rawValue)])
        }
        captures["keptDocument"] = count(pa, """
            SELECT COUNT(*) FROM doc WHERE created_at >= ? AND kind IN ('file', 'folder') AND parent_doc_id IS NULL
            """)
        captures["keptPageWithText"] = count(pa, """
            SELECT COUNT(*) FROM doc WHERE created_at >= ? AND kind = 'page' AND text_state IN ('read', 'partial')
            """)
        captures["keptPageLinkOnly"] = count(pa, """
            SELECT COUNT(*) FROM doc WHERE created_at >= ? AND kind = 'page' AND text_state NOT IN ('read', 'partial')
            """)
        // Commands by lead (recorded from phase 5).
        var commands: [String: Int] = [:]
        for c in PACommand.allCases { commands[c.rawValue] = events("command-" + c.rawValue) }

        let answers = count(index, "SELECT COUNT(*) FROM flag_example WHERE created_at >= ? AND answer != 'open'")
        let answersAll = Int((number(index, "SELECT COUNT(*) FROM flag_example WHERE answer != 'open'", []) as Int64?) ?? 0)
        var out: [String: Any] = [
            "captures": captures,
            "commands": commands,
            "projectProposals": [
                "made": events("proposal"),
                "confirmed": events("proposal-confirmed"),
                "corrected": events("proposal-corrected"),
            ],
            "requestFlags": [
                "shown": count(pa, "SELECT COUNT(*) FROM flag WHERE created_at >= ? AND kind = 'request'"),
                "kept": count(pa, "SELECT COUNT(*) FROM flag WHERE answered_at >= ? AND kind = 'request' AND state = 'kept'"),
                "dropped": count(pa, "SELECT COUNT(*) FROM flag WHERE answered_at >= ? AND kind = 'request' AND state = 'dropped'"),
                "sendersMuted": events("flag-mute"),
            ],
            "arrivalFlags": ["shown": count(pa, "SELECT COUNT(*) FROM flag WHERE created_at >= ? AND kind = 'arrival'")],
            "nearEventAlerts": ["shown": events("alert-shown", kind: RecordKind.calEvent.rawValue)],
            "reminders": [
                "shown": events("alert-shown", kind: RecordKind.item.rawValue),
                "done": count(pa, "SELECT COUNT(*) FROM item WHERE done_at >= ? AND kind = 'reminder' AND state = 'done'"),
                "snoozed": count(pa, """
                    SELECT COUNT(*) FROM event e JOIN item i ON i.id = e.record_id
                    WHERE e.at >= ? AND e.type = 'snooze' AND e.record_kind = 'item' AND i.kind = 'reminder'
                    """),
                "missed": events("alert-missed"),
            ],
            "searches": ["count": events("command-" + PACommand.whereIs.rawValue), "openAfterSearch": NSNull()],
            "mainPoints": events("command-" + PACommand.mainPoints.rawValue),
            "flagLearning": [
                "answers": answers,
                // Started: the PA uses learned weights (they passed the guard).
                "started": settings.flagsLearn && answersAll >= FlagLearning.minAnswers
                    && ((number(pa, "SELECT COUNT(*) FROM meta WHERE key = 'flags.weights' AND value IS NOT NULL", []) as Int64?) ?? 0) > 0,
            ],
        ]
        if since == nil { out["mutedSendersNow"] = settings.flagsMuted.count }
        return out
    }

    static func number<T>(_ db: SQLite?, _ sql: String, _ params: [SQLValue]) -> T? {
        guard let db, let v = (try? db.query(sql, params))?.first?.first else { return nil }
        if T.self == Int64.self { return v.int as? T }
        if T.self == Double.self { return (v.real ?? v.int.map(Double.init)) as? T }
        return nil
    }
}
