import AppKit
import EarshotCore
import Foundation

/// What one sidebar read found.
public struct SidebarRead: Sendable {
    public var names: [SidebarName] = []
    /// True if the sidebar shows "loading". The app has not built its list yet.
    public var loading = false
    /// The placeholder of the message box, for extra spoken app names ("iMessage").
    public var placeholder: String?
    public var nodes = 0
    public var ms = 0.0
}

/// The result of the sidebar reads of one app, with its times.
public struct SidebarScan: Sendable {
    public var appID: String
    public var names: [SidebarName]
    /// Extra spoken names of the app, from the placeholder of its message box.
    public var appAliases: [String]
    /// The time of one read in ms.
    public var readMs: Double
    /// The time in ms until the list stopped changing.
    public var settleMs: Double
    public var reads: Int
    public var stillLoading: Bool
}

/// Reads the chat names in the sidebar of a chat app through Accessibility (E1, section 3.2).
/// It reads only. It does not bring the app to the front, and it presses nothing.
enum SidebarReader {
    /// The sidebar is at most the left 42 % of the main window. It ends where the message box starts.
    static let sidebarWidth = 0.42

    /// Reads the sidebars of the first two windows of the app, again every 300 ms until the list is stable.
    static func scan(_ app: AppEntry) async -> SidebarScan? {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first else { return nil }
        let t0 = Clock.nowNs()
        let el = AX.appElement(running.processIdentifier)
        if app.electron { AX.askForTree(el) }
        let windows = Array(AX.elements(el, "AXWindows").prefix(2))
        var check = SettleCheck()
        var oneRead = 0.0
        var placeholder: String?
        while true {
            var all: [SidebarName] = []
            var loading = false
            oneRead = 0
            for win in windows {
                let r = read(window: win)
                oneRead += r.ms
                loading = loading || r.loading
                placeholder = placeholder ?? r.placeholder
                for n in r.names where !all.contains(where: { Words.key($0.name) == Words.key(n.name) }) { all.append(n) }
            }
            if check.add(all, loading: loading) { break }
            await sleepMs(300)
        }
        let extra = NameRules.placeholderAliases(placeholder).filter { !app.aliases.contains($0) }
        return SidebarScan(appID: app.id, names: check.kept, appAliases: extra, readMs: Clock.round1(oneRead),
                           settleMs: Clock.round1(Clock.ms(since: t0)), reads: check.reads, stillLoading: check.stillLoading)
    }

    /// The texts of a list row, from the top left. Chat lists put the name there, and the last message after it.
    static func rowTexts(_ row: AXUIElement, maxNodes: Int = 120) -> [String] {
        var stack: [AXUIElement] = [row]
        var texts: [(String, Frame)] = []
        var count = 0
        while let el = stack.popLast(), count < maxNodes {
            count += 1
            let r = AX.role(el)
            let f = AX.frame(el) ?? Frame(x: 0, y: 0, w: 0, h: 0)
            if r == "AXStaticText", let v = AX.string(el, "AXValue"), !v.isEmpty {
                texts.append((v, f))
            } else if r != "AXRow", r != "AXCell" {
                // SwiftUI and Catalyst rows can carry the name as the description of a group.
                for attribute in ["AXTitle", "AXDescription"] {
                    if let s = AX.string(el, attribute), !s.isEmpty { texts.append((s, f)) }
                }
            }
            stack.append(contentsOf: AX.elements(el, "AXChildren"))
        }
        let sorted = texts.sorted { a, b in
            let ay = (a.1.y / 6).rounded(), by = (b.1.y / 6).rounded()
            return ay != by ? ay < by : a.1.x < b.1.x
        }
        var out = sorted.map(\.0)
        for attribute in ["AXTitle", "AXDescription"] {
            if let s = AX.string(row, attribute), !s.isEmpty { out.append(s) }
        }
        return out
    }

    /// Reads the sidebar of one window. It skips the main pane, the title bar, menus, images and live regions.
    static func read(window: AXUIElement, budgetMs: Int = 1500, maxNodes: Int = 20000) -> SidebarRead {
        var result = SidebarRead()
        guard let w = AX.frame(window) else { return result }
        let t0 = Clock.nowNs()
        var right = w.x + sidebarWidth * w.w
        let box = AX.findComposer(in: window)
        if let box, let b = AX.frame(box), b.x > w.x + 0.05 * w.w { right = min(right, b.x) }
        result.placeholder = box.flatMap { AX.string($0, "AXPlaceholderValue") }
        // Messages shows the placeholder as a text next to the box ("Text Message • SMS").
        let placeholderKey = result.placeholder.map { Words.key($0) } ?? ""
        let top = w.y + 0.03 * w.h
        var queue: [AXUIElement] = [window]
        var index = 0
        var seen = Set<String>()
        func add(_ raw: String?, fromRow: Bool, frame: Frame? = nil) -> Bool {
            guard let raw else { return false }
            // A text with no size is not on screen, for example a live region that says "loading…".
            if let f = frame, f.w == 0 || f.h == 0 { return false }
            if NameRules.isLoading(raw) { result.loading = true }
            if !placeholderKey.isEmpty, Words.key(raw) == placeholderKey { return false }
            guard let c = NameRules.clean(raw) else { return false }
            if seen.insert(Words.key(c.name)).inserted {
                result.names.append(SidebarName(name: c.name, isSelf: c.isSelf, fromRow: fromRow))
            }
            return true
        }
        while index < queue.count, index < maxNodes, Clock.ms(since: t0) < Double(budgetMs) {
            let el = queue[index]
            index += 1
            let r = AX.role(el)
            if ["AXMenuBar", "AXMenu", "AXImage", "AXScrollBar", "AXToolbar"].contains(r) { continue }
            if AX.liveRegions.contains(AX.subrole(el)) { continue }
            let frame = AX.frame(el)
            if let f = frame, f.w > 0, f.h > 0, !CFEqual(el, window) {
                if f.x >= right || f.maxY <= top { continue }
            }
            if r == "AXRow" || r == "AXCell" {
                for text in rowTexts(el) {
                    // The first part of a row name: "Ravi, 2 unread" gives "Ravi".
                    let part = text.split(separator: ",").first.map(String.init) ?? text
                    if add(part, fromRow: true) { break }
                }
                continue
            }
            if r == "AXStaticText" {
                // Messages (Catalyst) shows each chat as a text with an empty value and "Name, Unread, ..." as its description.
                let value = AX.string(el, "AXValue") ?? ""
                let text = value.isEmpty ? AX.string(el, "AXDescription")?.split(separator: ",").first.map(String.init) : value
                _ = add(text, fromRow: false, frame: frame)
            }
            if r == "AXLink" || r == "AXButton" {
                _ = add(AX.string(el, "AXTitle") ?? AX.string(el, "AXDescription"), fromRow: false, frame: frame)
            }
            queue.append(contentsOf: AX.elements(el, "AXChildren"))
        }
        result.nodes = index
        result.ms = Clock.ms(since: t0)
        return result
    }
}
