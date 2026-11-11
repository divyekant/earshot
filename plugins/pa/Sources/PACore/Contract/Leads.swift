import Foundation

/// The commands of the PA. Each lead of plugin.json gives one command. The PA adds no verb to earshot: earshot sends
/// all of them with the one intent `handOff` (docs/PLUGINS.md).
public enum PACommand: String, CaseIterable, Sendable {
    case remindMe, todo, note, keepThis, newProject, whatIsDue, whatAbout, whereIs, done, snooze, drop, move, quiet
    case whatProjects, finishProject, mainPoints

    /// The leads of plugin.json for each command. "what due" is the form with an apostrophe: earshot removes "'s"
    /// before it reads a lead, so "what's due" reaches the PA as the lead "what due". "where's" becomes "where",
    /// which is too wide for a lead (a dictated "where are you" would go to the PA), so it is not a lead.
    public static let leads: [String: PACommand] = [
        "remind me": .remindMe, "todo": .todo, "task": .todo, "note": .note, "keep this": .keepThis,
        "new project": .newProject, "what is due": .whatIsDue, "what due": .whatIsDue, "what about": .whatAbout,
        "where is": .whereIs, "done": .done, "snooze": .snooze, "drop": .drop, "move": .move,
        "quiet": .quiet,
        "what projects": .whatProjects, "finish project": .finishProject,
        "main points": .mainPoints, "summarize": .mainPoints, "summarise": .mainPoints,
    ]

    /// The command for a lead that earshot sent. The match ignores case, spaces, hyphens and apostrophes,
    /// as the lead match of earshot does.
    public static func from(lead: String) -> PACommand? {
        let k = Store.key(lead)
        return leads.first { Store.key($0.key) == k }?.value
    }
}
