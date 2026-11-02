import EarshotCore
import Foundation

/// Pure functions for the Apps and Names tabs. They keep the owner's edits when the discovery runs again (R-MT-2).
public enum CatalogueEdit {
    /// Merges new discovery rows into the saved rows.
    /// A saved row keeps the owner's choices (approved, enabled, aliases). Its other fields come from the discovery.
    /// A new row is not approved: the owner approves it in the Apps tab. Saved rows that the discovery
    /// did not find stay in the list.
    public static func merge(saved: [AppEntry], discovered: [AppEntry]) -> [AppEntry] {
        var result = saved
        for new in discovered {
            if let i = result.firstIndex(where: { $0.id == new.id }) {
                var row = new
                row.approved = result[i].approved
                row.enabled = result[i].enabled
                row.aliases = unique(result[i].aliases + new.aliases)
                result[i] = row
            } else {
                var row = new
                row.approved = false
                result.append(row)
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Replaces the names of one app with a new read. Manual names stay. A new read keeps the
    /// owner's isSelf mark and aliases for a name that it finds again.
    public static func replaceNames(_ saved: [NameEntry], appID: String, with found: [NameEntry]) -> [NameEntry] {
        let old = saved.filter { $0.appID == appID }
        var kept = saved.filter { $0.appID != appID || $0.source == .manual }
        for var n in found where n.appID == appID {
            let key = SafetyPolicy.normalize(n.name)
            if kept.contains(where: { $0.appID == appID && SafetyPolicy.normalize($0.name) == key }) { continue }
            if let prev = old.first(where: { SafetyPolicy.normalize($0.name) == key }) {
                n.isSelf = n.isSelf || prev.isSelf
                n.aliases = unique(prev.aliases + n.aliases)
            }
            kept.append(n)
        }
        return kept
    }

    /// Adds a name that the owner typed. It returns the list unchanged if the name is empty or already there.
    public static func addManual(_ saved: [NameEntry], appID: String, name: String, aliases: [String] = [], isSelf: Bool = false) -> [NameEntry] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = SafetyPolicy.normalize(trimmed)
        guard !key.isEmpty, !saved.contains(where: { $0.appID == appID && SafetyPolicy.normalize($0.name) == key }) else { return saved }
        return saved + [NameEntry(appID: appID, name: trimmed, aliases: aliases, isSelf: isSelf, source: .manual)]
    }

    /// The rows that match the search text and the scope. The search looks at the name, the bundle ID and the
    /// spoken names. Case and punctuation do not count.
    public static func filter(_ apps: [AppEntry], query: String, scope: AppScope) -> [AppEntry] {
        let q = SafetyPolicy.normalize(query)
        return apps.filter { app in
            switch scope {
            case .all: break
            case .needsApproval: if app.approved { return false }
            case .approved: if !app.approved { return false }
            case .chat: if !app.isChat { return false }
            case .off: if app.enabled { return false }
            }
            guard !q.isEmpty else { return true }
            let hay = SafetyPolicy.normalize(([app.name, app.bundleID] + app.aliases).joined(separator: " "))
            return hay.contains(q)
        }
    }

    /// Sets one Boolean field on every row whose id is in `ids`.
    public static func set(_ field: WritableKeyPath<AppEntry, Bool>, _ value: Bool, ids: Set<String>, in apps: [AppEntry]) -> [AppEntry] {
        apps.map { app in
            guard ids.contains(app.id) else { return app }
            var row = app
            row[keyPath: field] = value
            return row
        }
    }

    /// "imessage, text , ,Text" becomes ["imessage", "text"].
    public static func parseAliases(_ text: String) -> [String] {
        unique(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// Removes repeats. Case does not count. The first spelling stays.
    static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.lowercased()).inserted }
    }

    /// A short text for the way an app opens a chat.
    public static func describe(_ open: OpenChat) -> String {
        switch open {
        case .none: return "No chat opener"
        case .switcher(let keys): return "Switcher: \(keys)"
        case .link(let template): return "Link: \(template)"
        }
    }
}
