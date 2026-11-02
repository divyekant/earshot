import Foundation

/// The safety rules that every action obeys (R-NV-5, R-ON-5). The E0 to E2 experiments found each rule.
public enum SafetyPolicy {
    /// Below this confidence the app shows the result and does nothing.
    public static let minimumConfidence = 0.6

    // MARK: - Risky labels (from probe WebRouter, E2)

    /// Words of labels that can change data, send something or spend money.
    public static let riskyWords: Set<String> = [
        "send", "pay", "buy", "purchase", "order", "checkout", "submit", "delete", "remove", "publish", "post", "merge",
        "close", "archive", "approve", "accept", "decline", "reject", "confirm", "donate", "subscribe", "unsubscribe",
        "install", "upload", "share", "report", "block", "mute", "transfer", "upvote", "downvote", "vote", "flag", "hide",
        "favorite", "favourite", "like", "follow", "unfollow", "star", "unstar", "fork", "watch", "unwatch", "sponsor",
        "logout", "signout", "save", "discard", "reply", "comment", "invite", "leave", "cancel", "reset", "revoke",
        "disconnect", "unpublish", "retweet", "repost",
    ]
    public static let riskyPhrases = ["sign out", "log out", "add to cart", "buy now", "place order", "pay now", "check out"]

    /// Lower case, letters and digits only, single spaces. "Owner's" becomes "owners".
    public static func normalize(_ s: String) -> String {
        let lowered = s.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
        let scalars = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    /// The strict rule: the label has a risky word or phrase anywhere.
    public static func isRisky(_ label: String) -> Bool {
        let n = normalize(label)
        if !Set(n.split(separator: " ").map(String.init)).isDisjoint(with: riskyWords) { return true }
        return riskyPhrases.contains { " \(n) ".contains(" \($0) ") }
    }

    /// Roles that are not action controls: links, rows, cells, groups and text. A label of these roles can hold
    /// message text, for example a chat row "Darshan Pania · You: Sent a post". Every other role, and an unknown
    /// role, keeps the strict rule.
    public static let nonControlRoles: Set<String> = ["AXLink", "AXRow", "AXCell", "AXGroup", "AXStaticText",
                                                      "AXOutlineRow", "AXHeading", "AXImage", "AXListItem"]
    /// A non-control label of this many words or fewer is a command label ("Delete account"), so the strict rule applies.
    public static let shortLabelWords = 3

    /// True if a press on an element with this label and role can change data, send something or spend money.
    /// - A control (button, menu item, checkbox, pop-up button and similar), or an unknown role: the strict rule.
    /// - A link, row, cell, group or text: risky only if the label is short (3 words or fewer) and has a risky word,
    ///   or if the label starts with a risky word or phrase ("Delete this repository and all its issues").
    public static func isRisky(_ label: String, role: String?) -> Bool {
        guard let role, nonControlRoles.contains(role) else { return isRisky(label) }
        let words = normalize(label).split(separator: " ").map(String.init)
        if words.count <= shortLabelWords { return isRisky(label) }
        if let first = words.first, riskyWords.contains(first) { return true }
        let n = words.joined(separator: " ")
        return riskyPhrases.contains { n == $0 || n.hasPrefix($0 + " ") }
    }

    public static func isRisky(_ element: ScreenElement) -> Bool { isRisky(element.label, role: element.role) }

    /// True if earshot may press the element with this label.
    /// A risky label needs all of these: the rules made the decision, the owner said the exact label,
    /// and the hold key started the command (R-NV-5: "click Send"; R-ON-5: no risky press from always-on).
    /// `role` is the accessibility role of the element. Nil keeps the strict rule.
    public static func mayPress(label: String, role: String? = nil, spokenTarget: String, tier: RouterTier, mode: InputMode) -> Bool {
        guard isRisky(label, role: role) else { return true }
        return tier == .rules && mode == .hold && normalize(spokenTarget) == normalize(label)
    }

    /// Return sends the message in a message box. Return is allowed in a message box only for an explicit
    /// "send" intent. In other places, for example the search field of a chat switcher, Return is allowed (E0).
    public static func mayPressReturn(for intent: Intent, inMessageBox: Bool) -> Bool {
        intent == .send || !inMessageBox
    }

    // MARK: - Sign-in, code and payment pages (from probe WebPage.sensitive, E2)

    /// Words in the address path that mark a sign-in, code check or payment page.
    public static let sensitivePathWords = ["signin", "sign-in", "sign_in", "login", "log-in", "logon", "password", "twofactor",
                                            "two-factor", "2fa", "mfa", "otp", "verify", "checkout", "payment", "billing"]
    /// Words in the label of a field or a button that mark such a page. Links are not checked:
    /// a story title on Hacker News can have the word "password", and most pages have a "Log in" link.
    public static let sensitiveLabelWords = ["password", "verification code", "two-step", "two-factor", "one-time code",
                                             "security code", "card number", "cvv", "cvc"]

    /// The reason, if the page looks like a sign-in, code check or payment page. earshot does not act on such a page.
    public static func sensitive(url: String?, elements: [ScreenElement]) -> String? {
        if let url {
            let path = (URL(string: url)?.path ?? url).lowercased()
            if let w = sensitivePathWords.first(where: { path.contains($0) }) { return "the address has \"\(w)\"" }
        }
        if elements.contains(where: { $0.subrole == "AXSecureTextField" }) { return "a password field" }
        for e in elements where e.role != "AXLink" {
            let l = e.label.lowercased()
            if sensitiveLabelWords.contains(where: { l.contains($0) }) { return "the label \"\(e.label)\"" }
        }
        return nil
    }

    /// True if the address is on the host or one of its subdomains. "www." does not count.
    public static func onHost(_ url: String, _ host: String) -> Bool {
        let want = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard var h = URL(string: url)?.host else { return false }
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
        return h == want || h.hasSuffix("." + want)
    }
}
