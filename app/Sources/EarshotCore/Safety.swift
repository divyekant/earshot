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
        // Menu commands that end or erase something.
        "quit", "erase", "revert", "restart", "shutdown", "trash", "logoff",
    ]
    public static let riskyPhrases = ["sign out", "log out", "add to cart", "buy now", "place order", "pay now", "check out",
                                      "shut down", "empty trash", "move to trash", "force quit"]

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

    /// Roles that are not action controls: links, rows, cells and text. A label of these roles can hold
    /// message text, for example a chat row "Prakash Iyer · You: Sent a post". Every other role, and an unknown
    /// role, keeps the strict rule. Groups and images keep it too: a click on a group or an image can land on a
    /// child control, for example a group "Type a message Send" around a Send button.
    public static let nonControlRoles: Set<String> = ["AXLink", "AXRow", "AXCell", "AXStaticText", "AXOutlineRow",
                                                      "AXHeading", "AXListItem"]
    /// A non-control label of this many words or fewer is a command label ("Delete account"), so the strict rule applies.
    public static let shortLabelWords = 3

    /// True if the element names a page or a window, not a command: a tab button of a tab strip, or a menu item
    /// that names an open tab or window (MenuElements.titleSubrole, found by WindowTitles). A title uses the rule
    /// of the non-control roles: a page title "… transfer tips …" must not block a tab switch (R-NV-5).
    public static func isTitle(role: String?, subrole: String?) -> Bool {
        role == "AXTab" || (role == "AXRadioButton" && subrole == "AXTabButton") || subrole == MenuElements.titleSubrole
    }

    /// True if a press on an element with this label and role can change data, send something or spend money.
    /// - A control (button, menu item, checkbox, pop-up button and similar), or an unknown role: the strict rule.
    /// - A link, row, cell or text: risky only if the label is short (3 words or fewer) and has a risky word,
    ///   or if the label starts with a risky word or phrase ("Delete this repository and all its issues").
    /// - A title (`isTitle`): the same rule as a link.
    public static func isRisky(_ label: String, role: String?, subrole: String? = nil) -> Bool {
        guard let role, nonControlRoles.contains(role) || isTitle(role: role, subrole: subrole) else { return isRisky(label) }
        let words = normalize(label).split(separator: " ").map(String.init)
        if words.count <= shortLabelWords { return isRisky(label) }
        if let first = words.first, riskyWords.contains(first) { return true }
        let n = words.joined(separator: " ")
        return riskyPhrases.contains { n == $0 || n.hasPrefix($0 + " ") }
    }

    public static func isRisky(_ element: ScreenElement) -> Bool { isRisky(element.label, role: element.role, subrole: element.subrole) }

    /// True if earshot may press the element with this label.
    /// A risky label needs all of these: the rules made the decision, the owner said the exact label,
    /// and the hold key started the command (R-NV-5: "click Send"; R-ON-5: no risky press from always-on).
    /// `role` and `subrole` are the accessibility role and subrole of the element. A nil role keeps the strict rule.
    public static func mayPress(label: String, role: String? = nil, subrole: String? = nil, spokenTarget: String,
                                tier: RouterTier, mode: InputMode) -> Bool {
        guard isRisky(label, role: role, subrole: subrole) else { return true }
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
        // Menu items are not on the page: a menu "Passwords…" does not make every page a sign-in page.
        for e in elements where e.role != "AXLink" && !MenuElements.isMenu(e) {
            let l = e.label.lowercased()
            if sensitiveLabelWords.contains(where: { l.contains($0) }) { return "the label \"\(e.label)\"" }
        }
        return nil
    }

    /// The part of a file path that marks the data folder of the plugins (<store>/plugin-data/, docs/PLUGINS.md 5).
    public static let pluginDataPath = "/earshot/plugin-data/"

    /// True for a page that a plugin wrote: a file in the plugin data folder. Such a page holds the owner's private
    /// data, for example the to-dos or the mail flags of the PA.
    public static func pluginPage(url: String?) -> Bool {
        guard let url, let u = URL(string: url), u.isFileURL else { return false }
        return u.standardizedFileURL.path.contains(pluginDataPath)
    }

    /// The reason, if no part of the page may go to Jev: no labels for tier 2 and no picture (R-MD-1, D-10).
    /// A sign-in, code or payment page, or a page that a plugin wrote.
    public static func noCloud(_ screen: ScreenSnapshot?) -> String? {
        guard let screen else { return nil }
        if pluginPage(url: screen.url) { return "a plugin page" }
        return sensitive(url: screen.url, elements: screen.elements)
    }

    /// True if the address is on the host or one of its subdomains. "www." does not count.
    public static func onHost(_ url: String, _ host: String) -> Bool {
        let want = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard var h = URL(string: url)?.host else { return false }
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
        return h == want || h.hasSuffix("." + want)
    }
}
