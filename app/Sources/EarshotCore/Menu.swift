import Foundation

/// One item of an app's menu bar, for example ["Edit", "Select All"].
/// The discovery module reads the items. The app adds the front app's enabled items to the screen snapshot as
/// ScreenElements (MenuElements.elements), so menu commands use the same matcher and the same .click intent (R-MT-1).
public struct MenuEntry: Codable, Hashable, Sendable {
    /// The titles from the menu bar item to the item: ["File", "Export…"].
    public var path: [String]
    public var enabled: Bool
    /// The key shortcut as the menu shows it, for example "⌘A". For the note only: earshot never sends it.
    public var shortcut: String?
    /// True if the item names an open tab or window of the app (WindowTitles), for example a tab in a browser's
    /// Tab menu. It is a title, not a command (SafetyPolicy.isTitle).
    public var isTitle: Bool

    public var title: String { path.last ?? "" }

    public init(path: [String], enabled: Bool = true, shortcut: String? = nil, isTitle: Bool = false) {
        self.path = path; self.enabled = enabled; self.shortcut = shortcut; self.isTitle = isTitle
    }
}

/// Menu items as screen elements. The id is "m:" and the path joined with ">", for example "m:Edit>Select All".
/// The role is AXMenuItem, a control role, so the strict risky rule applies (SafetyPolicy.isRisky).
/// A title item (MenuEntry.isTitle) has the subrole `titleSubrole` and the rule of a link.
public enum MenuElements {
    public static let idPrefix = "m:"
    public static let separator: Character = ">"
    public static let role = "AXMenuItem"
    /// The subrole of a menu item that names a tab or a window. earshot sets it. Accessibility does not use it.
    public static let titleSubrole = "earshot.title"

    public static func id(_ path: [String]) -> String { idPrefix + path.joined(separator: String(separator)) }

    /// The path of a menu element id, or nil if the id is not a menu id.
    public static func path(_ id: String) -> [String]? {
        guard id.hasPrefix(idPrefix) else { return nil }
        let p = id.dropFirst(idPrefix.count).split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        return p.count >= 2 ? p : nil
    }

    public static func isMenu(_ e: ScreenElement) -> Bool { e.id.hasPrefix(idPrefix) }

    /// The enabled items with a title, as screen elements. They have no frame on screen.
    public static func elements(_ entries: [MenuEntry]) -> [ScreenElement] {
        entries.filter { $0.enabled && $0.path.count >= 2 && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }.map {
            ScreenElement(id: id($0.path), role: role, subrole: $0.isTitle ? titleSubrole : "", label: $0.title,
                          risky: SafetyPolicy.isRisky($0.title, role: role, subrole: $0.isTitle ? titleSubrole : nil),
                          x: 0, y: -1, w: 0, h: 0)
        }
    }
}

/// Finds the menu items that name an open tab or window, by data, not by menu names ("Window" and "Tab" are
/// localized and differ for each app). The titles are the window titles and the tab labels of the app.
/// Chrome (live read): a tab button adds " - Memory usage - 491 MB", a window adds " - Google Chrome - <profile>",
/// and the Tab menu cuts a long title in the middle with "…".
public enum WindowTitles {
    /// A cut title needs this many words before the "…", so that a short head does not match by chance.
    public static let cutHeadWords = 4

    /// True if the menu title names one of the titles:
    /// - the same text (case and spaces folded);
    /// - the text and an app suffix after " - ": "Apple" names "Apple - Google Chrome - Profile";
    /// - a title cut with "…": the head (at least 4 words) starts the title, and the tail follows it.
    public static func names(_ item: String, in titles: [String]) -> Bool {
        let t = fold(item)
        guard !t.isEmpty else { return false }
        let parts = t.split(separator: "…", maxSplits: 1, omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        for c in titles.map(fold) where !c.isEmpty {
            if c == t || c.hasPrefix(t + " - ") { return true }
            if parts.count == 2, parts[0].split(separator: " ").count >= cutHeadWords, c.hasPrefix(parts[0]),
               parts[1].isEmpty || c.dropFirst(parts[0].count).contains(parts[1]) { return true }
        }
        return false
    }

    static func fold(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
