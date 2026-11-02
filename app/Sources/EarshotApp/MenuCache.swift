import AppKit
import EarshotCore
import EarshotDiscovery
import Foundation

// T7: the menu items of the front app, for menu commands by voice (R-MT-1).
// A menu read takes up to MenuIndex.budgetMs (1 s), so it runs off the command path: when an app comes to the
// front, at start, and after each command. A command reads only this cache. It reads only. It presses nothing.

/// The last app in front that is not earshot. If earshot's own window (Manage) is in front when a voice command
/// starts, the command acts on that app (live test: "type …" with the Manage window in front).
final class FrontTracker: @unchecked Sendable {
    let own: String?
    private let lock = NSLock()
    private var last: NSRunningApplication?

    init(own: String?, current: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        self.own = own
        if let current { activated(current) }
    }

    /// Called on NSWorkspace.didActivateApplication.
    func activated(_ app: NSRunningApplication) {
        guard app.bundleIdentifier != own else { return }
        lock.withLock { last = app }
    }

    /// If earshot is in front, activates the last other app and waits up to `waitMs` until it is in front.
    /// Returns the time in ms, or nil if earshot was not in front. With no other app, earshot stays in front,
    /// and the pipeline then ignores earshot's own window.
    func restore(waitMs: Double = 500) async -> Double? {
        guard let own, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == own else { return nil }
        let clock = Stopwatch()
        guard let app = lock.withLock({ last }), !app.isTerminated else { return clock.ms }
        app.activate()
        while clock.ms < waitMs, NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return clock.ms
    }
}

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
