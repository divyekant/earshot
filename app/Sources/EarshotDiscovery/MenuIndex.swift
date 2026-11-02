import AppKit
import EarshotCore
import Foundation

/// One command in the menu bar of an app, for menu commands by voice ("select all", "undo", "new note").
public struct MenuItem: Hashable, Sendable {
    /// The titles from the menu bar down, for example ["Edit", "Select All"].
    public var path: [String]
    public var title: String { path.last ?? "" }
    /// False if the app greyed out the item at the time of the read. An app in the background greys out
    /// many items, so read the state again when the command runs.
    public var enabled: Bool
    /// The key shortcut as text, for example "cmd+a", or nil.
    public var keys: String?
    /// True if the command can change data, send something or end work: SafetyPolicy.isRisky, or a word
    /// in `MenuIndex.riskyWords` ("Empty Trash", "Quit Slack"). Press it only on the owner's exact command (R-NV-5).
    /// A title item uses the rule of a link: risky only if it is short, or if it starts with a risky word.
    public var risky: Bool
    /// True if the item names an open tab or window of the app (WindowTitles), for example a tab in Chrome's Tab menu.
    public var isTitle: Bool

    public init(path: [String], enabled: Bool, keys: String? = nil, isTitle: Bool = false) {
        self.path = path; self.enabled = enabled; self.keys = keys; self.isTitle = isTitle
        let title = path.last ?? ""
        let words = Words.normalize(title).split(separator: " ").map(String.init)
        let menuWord = !Set(words).isDisjoint(with: MenuIndex.riskyWords)
        if isTitle {
            risky = SafetyPolicy.isRisky(title, role: MenuElements.role, subrole: MenuElements.titleSubrole)
                || (menuWord && words.count <= SafetyPolicy.shortLabelWords)
                || MenuIndex.riskyWords.contains(words.first ?? "")
        } else {
            risky = SafetyPolicy.isRisky(title) || menuWord
        }
    }
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
        let items = MenuIndex.flatten(bar, titles: MenuIndex.readTitles(el))
        cache[bundleID] = items
        lastRead[bundleID] = (Clock.round1(Clock.ms(since: t0)), timedOut)
        return items
    }

    /// Forgets the list of the app, for example when it quits.
    public func forget(bundleID: String) { cache[bundleID] = nil }

    // MARK: - Rules (pure)

    /// Menu words that SafetyPolicy does not list, but that end work or remove data.
    public static let riskyWords: Set<String> = ["quit", "empty", "trash", "erase", "restart", "shutdown", "shut",
                                                 "logout", "terminate", "kill", "revert", "overwrite", "wipe", "format"]

    /// Menu titles that hold no commands: the Apple menu, the Services menu, and lists of recent files.
    /// Bookmarks and History hold page titles, not commands: a bookmark "… 10,000 …" matched "plan GW 10" (live test).
    public static let skippedMenus: Set<String> = ["apple", "services", "open recent", "recent items", "recent files",
                                                   "recent documents", "open recent file", "recent projects",
                                                   "bookmarks", "history"]

    /// The commands of a menu bar: one item for each leaf. It skips separators, the menus in `skippedMenus`,
    /// and the list of open windows: the items after the last separator of the "Window" menu.
    /// `titles` are the window titles and tab labels of the app. An item that names one is a title (WindowTitles).
    public static func flatten(_ bar: [MenuNode], titles: [String] = []) -> [MenuItem] {
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
                    out.append(MenuItem(path: path + [title], enabled: n.enabled, keys: n.keys,
                                        isTitle: WindowTitles.names(title, in: titles)))
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

    /// The window titles and the tab labels of the app, for WindowTitles. It reads only, and stops at `budgetMs`.
    /// Chrome: 1 window, 17 tab buttons in 23 ms (live read). It does not go into web pages.
    static func readTitles(_ app: AXUIElement, budgetMs: Int = 150) -> [String] {
        let t0 = Clock.nowNs()
        var out: [String] = []
        func walk(_ e: AXUIElement, _ depth: Int) {
            guard depth < 12 else { return }
            for c in AX.elements(e, "AXChildren") {
                if Clock.ms(since: t0) > Double(budgetMs) { return }
                let role = AX.role(c)
                if SafetyPolicy.isTitle(role: role, subrole: AX.string(c, "AXSubrole")) {
                    if let t = AX.string(c, "AXTitle") ?? AX.string(c, "AXDescription"), !t.isEmpty { out.append(t) }
                    continue
                }
                if role != "AXWebArea" { walk(c, depth + 1) }
            }
        }
        for w in AX.elements(app, "AXWindows") {
            if let t = AX.string(w, "AXTitle"), !t.isEmpty { out.append(t) }
            walk(w, 0)
        }
        return out
    }

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
