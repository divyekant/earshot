import EarshotCore

/// The owner's last answer breaks the same tie the next time (gap item 6). Data, not code: the answers are in
/// TieHabits (`habits.json`). No new verb and no app name in code (R-MT-1, DESIGN 3.0).
extension CommandRouter {
    /// Options within this score of the best one are a tie. The same margin as "two chats match" (ChatRouter).
    static let tieMargin = 0.05

    /// The decision with the tie broken by the owner's last answer, or nil if no habit applies.
    /// Only an unsure decision with a target, and only between the options that the rules score the same.
    /// The result is sure, at the tier `fuzzy`. A risky element has no key, so a habit never makes a risky press sure.
    static func breakTie(_ d: RulesDecision, habits: TieHabits, screen: ScreenSnapshot?) -> RulesDecision? {
        guard !d.sure, d.intent != .none, let best = d.options.map(\.score).max() else { return nil }
        let tied = d.options.filter { $0.score >= best - tieMargin }
        guard tied.count >= 2, tied.contains(where: { $0.intent == d.intent }) else { return nil }
        let keys = tied.compactMap { TieHabits.key($0.intent, screen: screen) }
        guard keys.count == tied.count, let i = habits.preferred(among: keys) else { return nil }
        let chosen = tied[i]
        var out = d
        out.intent = chosen.intent
        out.sure = true
        out.exact = false
        out.why = d.why + ", your last answer"
        out.options = [chosen] + d.options.filter { $0.intent != chosen.intent }
        return out
    }
}
