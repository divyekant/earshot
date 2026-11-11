import Foundation

/// The commands of the PA. Each lead of plugin.json gives one command. The PA adds no verb to earshot: earshot sends
/// all of them with the one intent `handOff` (docs/PLUGINS.md).
public enum PACommand: String, CaseIterable, Sendable {
    case remindMe, todo, note, keepThis, newProject, whatIsDue, whatAbout, whereIs, done, snooze, drop, move, quiet

    /// The leads of plugin.json for each command. "whats due" and "wheres" are the forms with an apostrophe
    /// ("what's due", "where's"): earshot removes the apostrophe before it reads a lead.
    public static let leads: [String: PACommand] = [
        "remind me": .remindMe, "todo": .todo, "task": .todo, "note": .note, "keep this": .keepThis,
        "new project": .newProject, "what is due": .whatIsDue, "whats due": .whatIsDue, "what about": .whatAbout,
        "where is": .whereIs, "wheres": .whereIs, "done": .done, "snooze": .snooze, "drop": .drop, "move": .move,
        "quiet": .quiet,
    ]

    /// The command for a lead that earshot sent. The match ignores case, spaces, hyphens and apostrophes,
    /// as the lead match of earshot does.
    public static func from(lead: String) -> PACommand? {
        let k = Store.key(lead)
        return leads.first { Store.key($0.key) == k }?.value
    }
}
