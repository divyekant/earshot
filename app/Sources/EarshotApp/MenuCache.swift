import EarshotCore
import EarshotDiscovery
import Foundation

// T7: the menu items of the front app, for menu commands by voice (R-MT-1).
// A menu read takes up to MenuIndex.budgetMs (1 s), so it runs off the command path: when an app comes to the
// front, at start, and after each command. A command reads only this cache. It reads only. It presses nothing.

final class MenuCache: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [String: [ScreenElement]] = [:]
    private let read: @Sendable (String) async -> [MenuItem]

    /// `read` reads the menus of an app, for example MenuIndex.refresh(bundleID:).
    init(read: @escaping @Sendable (String) async -> [MenuItem]) { self.read = read }

    /// The cached menu elements of the app. It never reads. Empty if the app has no list yet.
    func cached(_ bundleID: String) -> [ScreenElement] {
        lock.withLock { elements[bundleID] ?? [] }
    }

    /// Reads the menus of the app again, in the background.
    func refresh(_ bundleID: String) {
        Task.detached { [self] in await self.load(bundleID) }
    }

    /// Reads the menus of the app now. Tests call it directly.
    func load(_ bundleID: String) async {
        let items = await read(bundleID)
        let found = Self.elements(items)
        lock.withLock { elements[bundleID] = found }
    }

    /// The enabled items as screen elements (MenuElements.elements). An item that T4 marks risky
    /// ("Empty Trash", "Wipe") stays risky, also when SafetyPolicy does not list its word (R-NV-5).
    static func elements(_ items: [MenuItem]) -> [ScreenElement] {
        let entries = items.filter(\.enabled).map { MenuEntry(path: $0.path, enabled: true, shortcut: $0.keys, isTitle: $0.isTitle) }
        let risky = Set(items.filter(\.risky).map { MenuElements.id($0.path) })
        return MenuElements.elements(entries).map { e in
            var e = e
            if risky.contains(e.id) { e.risky = true }
            return e
        }
    }
}
