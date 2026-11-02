import AppKit
import EarshotCore
import Foundation

/// One command in the menu bar of an app, for menu commands by voice ("select all", "undo", "new note").
public struct MenuItem: Hashable, Sendable {
    /// The titles from the menu bar down, for example ["Edit", "Select All"].
    public var path: [String]
    public var title: String { path.last ?? "" }
    /// False if the app greys out the item now.
    public var enabled: Bool
    /// The key shortcut as text, for example "cmd+a", or nil.
    public var keys: String?

    public init(path: [String], enabled: Bool, keys: String? = nil) { self.path = path; self.enabled = enabled; self.keys = keys }
}

/// One node of a menu tree. The reader builds it from Accessibility. Tests build it by hand.
public struct MenuNode: Sendable {
    public var title: String
    public var enabled: Bool
    public var keys: String?
    /// The items of the submenu. Empty for a command.
    public var children: [MenuNode]
    /// True for a separator line.
    public var separator: Bool

    public init(title: String, enabled: Bool = true, keys: String? = nil, children: [MenuNode] = [], separator: Bool = false) {
        self.title = title; self.enabled = enabled; self.keys = keys; self.children = children; self.separator = separator
    }

    public static let line = MenuNode(title: "", separator: true)
}

/// The menu commands of the running apps. It reads only: it opens no menu and presses nothing.
/// It keeps one list for each app until `refresh(bundleID:)`.
public actor MenuIndex {
    /// The time limit of one read. One slow app must not hold up a command.
    public static let budgetMs = 1000

    private var cache: [String: [MenuItem]] = [:]
    /// The time of the last read of each app in ms, and whether it stopped at the limit.
    public private(set) var lastRead: [String: (ms: Double, timedOut: Bool)] = [:]

    public init() {}

    /// The menu commands of the app. It reads the menus if it has no list for the app.
    public func items(bundleID: String) -> [MenuItem] {
        if let c = cache[bundleID] { return c }
        return refresh(bundleID: bundleID)
    }

    /// Reads the menus of the app again. Returns an empty list if the app does not run or Accessibility is off.
    @discardableResult
    public func refresh(bundleID: String) -> [MenuItem] {
        guard AX.trusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            cache[bundleID] = nil
            return []
        }
        let t0 = Clock.nowNs()
        let el = AX.appElement(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.25)
        if MenuCatalogue.isElectron(app.bundleURL) { AX.askForTree(el) }
        let (bar, timedOut) = MenuIndex.readBar(el, budgetMs: MenuIndex.budgetMs)
        let items = MenuIndex.flatten(bar)
        cache[bundleID] = items
        lastRead[bundleID] = (Clock.round1(Clock.ms(since: t0)), timedOut)
        return items
    }

    /// Forgets the list of the app, for example when it quits.
    public func forget(bundleID: String) { cache[bundleID] = nil }

    // MARK: - Rules (pure)

    /// Menu titles that hold no commands: the Apple menu, the Services menu, and lists of recent files.
    public static let skippedMenus: Set<String> = ["apple", "services", "open recent", "recent items", "recent files",
                                                   "recent documents", "open recent file", "recent projects"]

    /// The commands of a menu bar: one item for each leaf. It skips separators, the menus in `skippedMenus`,
    /// and the list of open windows: the items after the last separator of the "Window" menu.
    public static func flatten(_ bar: [MenuNode]) -> [MenuItem] {
        var out: [MenuItem] = []
        func walk(_ nodes: [MenuNode], _ path: [String]) {
            var list = nodes
            // The window list is the last section of the Window menu.
            if path.count == 1, Words.normalize(path[0]) == "window", let last = list.lastIndex(where: \.separator) {
                list = Array(list[..<last])
            }
            for n in list where !n.separator {
                let title = Words.squash(n.title)
                guard !title.isEmpty, !skippedMenus.contains(Words.normalize(title)) else { continue }
                if n.children.isEmpty {
                    out.append(MenuItem(path: path + [title], enabled: n.enabled, keys: n.keys))
                } else {
                    walk(n.children, path + [title])
                }
            }
        }
        for top in bar {
            let title = Words.squash(top.title)
            guard !title.isEmpty, !skippedMenus.contains(Words.normalize(title)) else { continue }
            walk(top.children, [title])
        }
        return out
    }

    // MARK: - Accessibility

    /// Reads the menu bar into a tree. It stops at `budgetMs`, and then returns what it read.
    static func readBar(_ app: AXUIElement, budgetMs: Int) -> ([MenuNode], Bool) {
        guard let bar = AX.element(app, "AXMenuBar") else { return ([], false) }
        let t0 = Clock.nowNs()
        var timedOut = false
        // Menu items hold an AXMenu, and the AXMenu holds the items. The AXMenu has no title.
        func items(of element: AXUIElement, depth: Int) -> [MenuNode] {
            guard depth < 8 else { return [] }
            var out: [MenuNode] = []
            for child in AX.elements(element, "AXChildren") {
                if Clock.ms(since: t0) > Double(budgetMs) { timedOut = true; break }
                let role = AX.role(child)
                if role == "AXMenu" {
                    out += items(of: child, depth: depth + 1)
                    continue
                }
                guard role == "AXMenuItem" || role == "AXMenuBarItem" else { continue }
                let title = (AX.string(child, "AXTitle") ?? "").replacingOccurrences(of: "\u{200E}", with: "")
                if title.isEmpty, role == "AXMenuItem" {
                    out.append(.line)
                    continue
                }
                var keys: String?
                if let char = AX.string(child, "AXMenuItemCmdChar"), !char.isEmpty {
                    let mods = (AX.copy(child, "AXMenuItemCmdModifiers") as? NSNumber)?.intValue ?? 0
                    let code = (AX.copy(child, "AXMenuItemCmdVirtualKey") as? NSNumber)?.intValue
                    keys = MenuRules.shortcutText(char: char, modifiers: mods, keyCode: code)
                }
                out.append(MenuNode(title: title, enabled: AX.bool(child, "AXEnabled") ?? true, keys: keys,
                                    children: items(of: child, depth: depth + 1)))
            }
            return out
        }
        let tree = items(of: bar, depth: 0)
        return (tree, timedOut)
    }
}
