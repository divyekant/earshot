import Foundation

/// The safety rules that every action obeys (R-NV-5, R-ON-5). The E0-E2 experiments found each rule.
public enum SafetyPolicy {
    /// Below this confidence the app shows the result and does nothing.
    public static let minimumConfidence = 0.6

    /// Words of labels that the app never presses, unless the owner says the exact label after "click".
    public static let riskyWords: Set<String> = [
        "send", "submit", "pay", "buy", "purchase", "checkout", "order", "delete", "remove", "donate",
        "share", "star", "fork", "watch", "hide", "report", "block", "unsubscribe", "sign out", "log out",
        "logout", "transfer", "confirm", "publish", "post",
    ]

    /// Words that mark a sign-in, code or payment page. The app does not act on such a page.
    public static let blockedPageWords: [String] = [
        "password", "verification code", "two-step", "2-step", "one-time code", "sign in", "log in",
        "card number", "cvv", "billing", "checkout", "payment",
    ]

    public static func isRisky(_ label: String) -> Bool {
        let words = Set(label.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let lower = label.lowercased()
        return riskyWords.contains { $0.contains(" ") ? lower.contains($0) : words.contains($0) }
    }

    /// True if the page looks like a sign-in, code or payment page.
    public static func isBlockedPage(url: String, title: String, labels: [String]) -> Bool {
        let text = ([url, title] + labels).joined(separator: " ").lowercased()
        return blockedPageWords.contains { text.contains($0) }
    }

    /// Return or a Send button is allowed only for an explicit "send" intent.
    public static func mayPressReturn(for intent: Intent) -> Bool { intent == .send }
}
