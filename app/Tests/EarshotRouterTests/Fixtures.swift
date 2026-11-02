import EarshotCore
@testable import EarshotRouter

/// Test data in the shape of the E1 index (section 5.3) and the E2 pages (section 5).
/// This is test data only. The router itself has no app and no name in its code (R-MT-1, R-MT-2).
enum Fixtures {
    static let apps: [AppEntry] = [
        AppEntry(id: "slack", name: "Slack", bundleID: "com.tinyspeck.slackmacgap", aliases: ["slack"], isChat: true,
                 openChat: .switcher(keys: "cmd+k"), electron: true, approved: true),
        AppEntry(id: "messages", name: "Messages", bundleID: "com.apple.MobileSMS", aliases: ["messages", "imessage"],
                 isChat: true, openChat: .switcher(keys: "cmd+n"), approved: true),
        AppEntry(id: "notes", name: "Notes", bundleID: "com.apple.Notes", aliases: ["notes"], approved: true),
        AppEntry(id: "calendar", name: "Calendar", bundleID: "com.apple.iCal", aliases: ["calendar"], approved: true),
        AppEntry(id: "lockscreen", name: "Lock Screen", bundleID: "com.example.lock", aliases: ["lock screen"], approved: true),
        AppEntry(id: "tigervnc", name: "TigerVNC", bundleID: "com.tigervnc.viewer", aliases: ["tigervnc"], approved: true),
        // Not approved: the router must not route to it.
        AppEntry(id: "discord", name: "Discord", bundleID: "com.hnc.Discord", aliases: ["discord"], isChat: true, approved: false),
    ]

    static let names: [NameEntry] = [
        NameEntry(appID: "messages", name: "Udita", source: .sidebar),
        NameEntry(appID: "messages", name: "Mrunal", source: .sidebar),
        NameEntry(appID: "messages", name: "Felix", source: .sidebar),
        NameEntry(appID: "messages", name: "Partiful", source: .sidebar),
        NameEntry(appID: "messages", name: "Owner", isSelf: true, source: .sidebar),
        NameEntry(appID: "slack", name: "Prakash Iyer", source: .sidebar),
        NameEntry(appID: "slack", name: "Ravi Kumar", source: .search),
        NameEntry(appID: "slack", name: "PostHog", source: .sidebar),
        NameEntry(appID: "slack", name: "alerts", source: .sidebar),
        NameEntry(appID: "slack", name: "Owner (you)", isSelf: true, source: .sidebar),
        NameEntry(appID: "discord", name: "Zed", source: .sidebar),
    ]

    /// The E1 group chat that made the one wrong chat of the rules.
    static let group = NameEntry(appID: "messages", name: "Manel & Mrunal", source: .sidebar)

    static var context: RouteContext { RouteContext(apps: apps, names: names) }

    static func el(_ id: String, _ role: String, _ label: String, y: Double, x: Double = 0, subrole: String = "",
                   url: String? = nil, inHeading: Bool = false) -> ScreenElement {
        ScreenElement(id: id, role: role, subrole: subrole, label: label, url: url, inHeading: inHeading,
                      risky: SafetyPolicy.isRisky(label), x: x, y: y, w: 50, h: 12)
    }

    /// A page in the shape of the Hacker News front page in E2.
    static let news = ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "Hacker News", url: "https://news.ycombinator.com/",
                                     elements: [
        el("e1", "AXLink", "Hacker News", y: 10),
        el("e2", "AXLink", "new", y: 10, x: 100),
        el("e3", "AXLink", "past", y: 10, x: 130),
        el("e4", "AXLink", "comments", y: 10, x: 160),
        el("e5", "AXLink", "ask", y: 10, x: 220),
        el("e6", "AXLink", "jobs", y: 10, x: 250),
        el("e7", "AXLink", "submit", y: 10, x: 280),
        el("e8", "AXLink", "login", y: 10, x: 900),
        el("e9", "AXLink", "A new approach to garbage collection in Swift", y: 40, url: "https://example.org/gc"),
        el("e10", "AXLink", "382 comments", y: 52, x: 300, url: "https://news.ycombinator.com/item?id=1"),
        el("e11", "AXLink", "hide", y: 52, x: 250),
        el("e12", "AXLink", "Show HN: A tiny text editor written in Zig", y: 70, url: "https://example.org/zig"),
        el("e13", "AXLink", "384 comments", y: 82, x: 300, url: "https://news.ycombinator.com/item?id=2"),
        el("e14", "AXLink", "Why the history of maps still matters today", y: 100, url: "https://example.org/maps"),
        el("e15", "AXLink", "12 comments", y: 112, x: 300, url: "https://news.ycombinator.com/item?id=3"),
        el("e16", "AXLink", "More", y: 400),
        el("e17", "AXTextField", "Search", y: 450, subrole: "AXSearchField"),
        el("e18", "AXLink", "2", y: 420, x: 10),
        el("e19", "AXLink", "12", y: 420, x: 30),
    ])

    /// A page in the shape of a Wikipedia article in E2.
    static let wiki = ScreenSnapshot(bundleID: "com.google.Chrome", windowTitle: "Swift - Wikipedia", url: "https://en.wikipedia.org/wiki/Swift",
                                     elements: [
        el("w1", "AXLink", "Main page", y: 10),
        el("w2", "AXLink", "Contents", y: 30),
        el("w3", "AXLink", "Talk", y: 60, x: 300),
        el("w4", "AXLink", "Read", y: 60, x: 360),
        el("w5", "AXSearchField", "Search Wikipedia", y: 10, x: 500, subrole: "AXSearchField"),
        el("w6", "AXButton", "Donate now to keep Wikipedia free", y: 120),
        el("w7", "AXLink", "View history", y: 60, x: 420),
        el("w8", "AXRadioButton", "Article", y: 60, x: 200, subrole: "AXTabButton"),
    ])
}
