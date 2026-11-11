import EarshotCore
import Foundation

/// The tier-0 rule for plugins (R-PL-2, R-PL-4, docs/PLUGINS.md). A command that starts with the lead words of an
/// approved plugin goes to that plugin as text. It is one intent for all plugins (`.handOff`), so no plugin adds a
/// verb (DESIGN 3.0).
///
/// A core command wins over a plugin lead. The rule for that is on the lead, not on the command: earshot refuses a
/// lead that starts with a core command word, a send word or an app name. So "remind me to open Slack" gives the
/// text "open Slack" to the plugin, and "open Slack" alone stays a core command.
public enum PluginRouter {
    /// Words that a lead must not start with: the verbs of the core commands, and the words of the fixed phrases.
    static let coreWords: Set<String> = CommandRouter.commandStarts
            .union(CommandRouter.sendPhrases.flatMap { $0.split(separator: " ").map(String.init) })
            .union(CommandRouter.showNumbers.flatMap { $0.split(separator: " ").map(String.init) })
            .union(CommandRouter.hideNumbers.flatMap { $0.split(separator: " ").map(String.init) })
            .union(["scroll", "back", "go", "undo", "stop", "yes", "no"])

    /// Why earshot refuses this lead, or nil if the lead is good. `apps` are the catalogue rows.
    /// - A lead has 1 to `PluginContract.maxLeadWords` words.
    /// - Its first word is not a filler: the router removes fillers before it reads the lead.
    /// - Its first word is not a core command word, and it does not start with an app name.
    public static func refusal(_ lead: String, apps: [AppEntry]) -> String? {
        let words = TextKit.words(lead)
        guard !words.isEmpty else { return "no words" }
        guard words.count <= PluginContract.maxLeadWords else { return "more than \(PluginContract.maxLeadWords) words" }
        if CommandRouter.leadFillers.contains(words[0]) || CommandRouter.fillers.contains(words[0]) {
            return "\"\(words[0])\" is a filler word"
        }
        if coreWords.contains(words[0]) { return "\"\(words[0])\" starts a core command" }
        for span in 1...min(3, words.count) {
            let key = words[0..<span].joined()
            if apps.contains(where: { ($0.aliases + [$0.name]).map(TextKit.key).contains(key) }) {
                return "\"\(words[0..<span].joined(separator: " "))\" is an app name"
            }
        }
        return nil
    }

    /// The leads of the plugins that the router can use: each good lead once. If two plugins have the same lead,
    /// the plugin with the first id keeps it.
    public static func usable(_ leads: [PluginLead], apps: [AppEntry]) -> [PluginLead] {
        var seen = Set<String>()
        var out: [PluginLead] = []
        for l in leads.sorted(by: { ($0.pluginID, $0.lead) < ($1.pluginID, $1.lead) }) where refusal(l.lead, apps: apps) == nil {
            let key = TextKit.words(l.lead).joined(separator: " ")
            if seen.insert(key).inserted { out.append(l) }
        }
        return out
    }

    /// The plugin, the lead and the raw words after it, if the command starts with a usable lead. The longest lead
    /// wins. The match ignores the spaces and hyphens between the words, because the speech engine can write one
    /// spoken word in more than one way ("todo", "to do", "to-do"). Lead fillers ("hey", "can you") before the lead
    /// do not count. Nil if no lead matches.
    public static func match(_ text: String, plugins: [PluginLead], apps: [AppEntry]) -> (lead: PluginLead, rest: String)? {
        guard !plugins.isEmpty else { return nil }
        let tokens = Tokens(text)
        let words = tokens.words
        // Each lead as one key with no spaces: "todo" matches the spoken "to do" and "to-do" too.
        let keys = usable(plugins, apps: apps).map { ($0, TextKit.words($0.lead).joined()) }
        var start = 0
        while start < words.count {
            var best: (lead: PluginLead, length: Int, end: Int)?
            for (p, key) in keys {
                var joined = ""
                var end = start
                while end < words.count, joined.count < key.count { joined += words[end]; end += 1 }
                if joined == key, best == nil || key.count > best!.length { best = (p, key.count, end) }
            }
            if let best { return (best.lead, tokens.raw(best.end..<words.count)) }
            // A lead filler ("hey", "can you") before the lead does not count. Try the lead after it.
            guard start < words.count - 1, CommandRouter.leadFillers.contains(words[start]) else { return nil }
            start += 1
        }
        return nil
    }

    /// The rules decision for a plugin lead, or nil.
    static func decide(_ text: String, context: RouteContext) -> RulesDecision? {
        guard let m = match(text, plugins: context.plugins, apps: context.apps) else { return nil }
        return RulesDecision(intent: .handOff(pluginID: m.lead.pluginID, lead: m.lead.lead, text: m.rest), sure: true,
                             exact: true, why: "plugin lead \"\(m.lead.lead)\"", options: [])
    }
}
