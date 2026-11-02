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

    public var title: String { path.last ?? "" }

    public init(path: [String], enabled: Bool = true, shortcut: String? = nil) {
        self.path = path; self.enabled = enabled; self.shortcut = shortcut
    }
}

/// Menu items as screen elements. The id is "m:" and the path joined with ">", for example "m:Edit>Select All".
/// The role is AXMenuItem, a control role, so the strict risky rule applies (SafetyPolicy.isRisky).
public enum MenuElements {
    public static let idPrefix = "m:"
    public static let separator: Character = ">"
    public static let role = "AXMenuItem"

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
            ScreenElement(id: id($0.path), role: role, subrole: "", label: $0.title,
                          risky: SafetyPolicy.isRisky($0.title, role: role), x: 0, y: -1, w: 0, h: 0)
        }
    }
}
