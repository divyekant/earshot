import AppKit
import ApplicationServices
import Foundation

struct Frame: Sendable {
    let x: Double, y: Double, w: Double, h: Double
    var maxY: Double { y + h }
    var midX: Double { x + w / 2 }
    var midY: Double { y + h / 2 }
}

enum Clock {
    static func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    static func ms(since t0: UInt64) -> Double { Double(nowNs() &- t0) / 1_000_000 }
    static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
}

func sleepMs(_ ms: Int) async {
    try? await Task.sleep(nanoseconds: UInt64(max(ms, 0)) * 1_000_000)
}

/// Polls `condition` until it is true or the time runs out.
func waitUntil(timeoutMs: Int, intervalMs: Int = 10, _ condition: () -> Bool) async -> Bool {
    let t0 = Clock.nowNs()
    while true {
        if condition() { return true }
        if Clock.ms(since: t0) >= Double(timeoutMs) { return false }
        await sleepMs(intervalMs)
    }
}

/// Thin helpers over the macOS Accessibility (AX) API, ported from probe/Sources/EarshotProbe/AX.swift.
/// The discovery module keeps its own copy, because a module does not import another task's module.
/// AX coordinates have their origin at the top left of the main screen.
enum AX {
    static func trusted() -> Bool { AXIsProcessTrusted() }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = copy(element, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let v = copy(element, attribute), CFGetTypeID(v) == CFArrayGetTypeID(), let array = v as? [AnyObject] else { return [] }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let v = copy(element, attribute) else { return nil }
        if let s = v as? String { return s }
        if let a = v as? NSAttributedString { return a.string }
        return nil
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? { (copy(element, attribute) as? NSNumber)?.boolValue }
    static func role(_ element: AXUIElement) -> String { string(element, "AXRole") ?? "" }
    static func subrole(_ element: AXUIElement) -> String { string(element, "AXSubrole") ?? "" }
    static func value(_ element: AXUIElement) -> String? { string(element, "AXValue") }

    static func frame(_ element: AXUIElement) -> Frame? {
        guard let p = copy(element, "AXPosition"), let s = copy(element, "AXSize"),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return Frame(x: point.x, y: point.y, w: size.width, h: size.height)
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    static func same(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
        guard let a, let b else { return false }
        return CFEqual(a, b)
    }

    static func appElement(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.5)
        return element
    }

    /// The process id of the app that has keyboard focus.
    static func frontPid() -> pid_t? {
        let system = AXUIElementCreateSystemWide()
        guard let app = element(system, "AXFocusedApplication") else {
            return NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        var p: pid_t = 0
        AXUIElementGetPid(app, &p)
        return p
    }

    static func focused(_ app: AXUIElement) -> AXUIElement? { element(app, "AXFocusedUIElement") }
    static func window(_ app: AXUIElement) -> AXUIElement? { element(app, "AXFocusedWindow") ?? element(app, "AXMainWindow") }

    /// Electron apps build their accessibility tree only when asked.
    static func askForTree(_ app: AXUIElement) { set(app, "AXManualAccessibility", kCFBooleanTrue) }

    // MARK: - Text fields

    static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox"]
    static let liveRegions: Set<String> = ["AXApplicationAlert", "AXApplicationLog", "AXApplicationStatus",
                                           "AXApplicationTimer", "AXApplicationMarquee"]

    static func isEditableText(_ element: AXUIElement, allowSearch: Bool = false) -> Bool {
        guard textRoles.contains(role(element)) else { return false }
        let sub = subrole(element)
        if sub == "AXSecureTextField" { return false }
        if sub == "AXSearchField" && !allowSearch { return false }
        return bool(element, "AXEnabled") != false
    }

    /// The words that label a field: placeholder, description, title, help and role description.
    static func label(_ element: AXUIElement) -> String {
        ["AXPlaceholderValue", "AXDescription", "AXTitle", "AXHelp", "AXRoleDescription"]
            .compactMap { string(element, $0)?.lowercased() }
            .joined(separator: " ")
            .replacingOccurrences(of: "\u{200E}", with: "")
    }

    static func looksLikeSearch(_ element: AXUIElement) -> Bool {
        let words = label(element)
        return words.contains("search") || words.contains("jump to") || words.contains("find") || words.contains("go to")
    }

    /// A field whose label says that it writes a message, for example "Message to #general" or "Reply to thread".
    static func looksLikeComposer(_ element: AXUIElement) -> Bool {
        let words = label(element)
        return ["message", "reply", "compose", "write", "send"].contains { words.contains($0) }
    }

    static func valueSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, "AXValue" as CFString, &settable) == .success && settable.boolValue
    }

    /// The generic message-box rule: an editable text field that is wide, in the lower half of the window, not a search field.
    static func isComposer(_ element: AXUIElement, in window: AXUIElement) -> Bool {
        guard isEditableText(element), let f = frame(element), let w = frame(window) else { return false }
        guard f.w >= 0.3 * w.w, f.midY >= w.y + 0.5 * w.h else { return false }
        return !looksLikeSearch(element)
    }

    /// The switcher rule from E0: a settable text field in the upper part of the window.
    static func isSwitcherField(_ element: AXUIElement, in window: AXUIElement) -> Bool {
        let searchSubrole = subrole(element) == "AXSearchField"
        guard (isEditableText(element, allowSearch: true) && valueSettable(element)) || searchSubrole,
              let f = frame(element), let w = frame(window), f.midY < w.y + 0.6 * w.h else { return false }
        if searchSubrole || looksLikeSearch(element) { return true }
        if looksLikeComposer(element) { return false }
        let named = ["AXPlaceholderValue", "AXDescription", "AXTitle"].contains {
            !(string(element, $0) ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
        return named || role(element) != "AXTextArea"
    }

    private static let skipRoles: Set<String> = ["AXList", "AXTable", "AXOutline", "AXRow", "AXCell", "AXMenuBar", "AXMenu", "AXImage"]

    /// Finds the message box: the lowest, widest composer in the lower half of the window.
    static func findComposer(in window: AXUIElement, budgetMs: Int = 300, maxNodes: Int = 4000) -> AXUIElement? {
        guard let w = frame(window) else { return nil }
        let t0 = Clock.nowNs()
        var queue: [AXUIElement] = [window]
        var index = 0
        var best: (AXUIElement, Frame)?
        while index < queue.count, index < maxNodes, Clock.ms(since: t0) < Double(budgetMs) {
            let element = queue[index]
            index += 1
            let r = role(element)
            if textRoles.contains(r), isComposer(element, in: window), let f = frame(element) {
                if best == nil || f.maxY > best!.1.maxY || (f.maxY == best!.1.maxY && f.w > best!.1.w) { best = (element, f) }
                continue
            }
            if skipRoles.contains(r) { continue }
            if let f = frame(element), f.w > 0, f.maxY < w.y + 0.5 * w.h, !CFEqual(element, window) { continue }
            queue.append(contentsOf: elements(element, "AXChildren").reversed())
        }
        return best?.0
    }

    /// Finds the app's own search field: the highest switcher field with "search" in its label or the search subrole.
    static func findSearchField(in window: AXUIElement, budgetMs: Int = 300, maxNodes: Int = 4000) -> AXUIElement? {
        guard let w = frame(window) else { return nil }
        let t0 = Clock.nowNs()
        var queue: [AXUIElement] = [window]
        var index = 0
        var best: (AXUIElement, Frame)?
        while index < queue.count, index < maxNodes, Clock.ms(since: t0) < Double(budgetMs) {
            let element = queue[index]
            index += 1
            let r = role(element)
            if textRoles.contains(r) {
                if isSwitcherField(element, in: window), subrole(element) == "AXSearchField" || looksLikeSearch(element),
                   let f = frame(element), best == nil || f.y < best!.1.y {
                    best = (element, f)
                }
                continue
            }
            if skipRoles.contains(r) { continue }
            if let f = frame(element), f.w > 0, f.y > w.y + 0.6 * w.h { continue }
            queue.append(contentsOf: elements(element, "AXChildren"))
        }
        return best?.0
    }

    // MARK: - Menus

    /// Reads the menu bar of an app: each menu item that has a key shortcut.
    /// It reads only. It opens no menu and presses nothing.
    static func menuShortcuts(_ app: AXUIElement) -> [MenuShortcut] {
        guard let bar = element(app, "AXMenuBar") else { return [] }
        var out: [MenuShortcut] = []
        func walk(_ element: AXUIElement, _ path: [String], depth: Int) {
            // Bar item, menu, item, submenu, item: "Edit > Find > Find..." is 5 levels down.
            guard depth < 8 else { return }
            for child in elements(element, "AXChildren") {
                let title = (string(child, "AXTitle") ?? "").replacingOccurrences(of: "\u{200E}", with: "")
                let next = title.isEmpty ? path : path + [title]
                if role(child) == "AXMenuItem", let char = string(child, "AXMenuItemCmdChar"), !char.isEmpty {
                    let mods = (copy(child, "AXMenuItemCmdModifiers") as? NSNumber)?.intValue ?? 0
                    let code = (copy(child, "AXMenuItemCmdVirtualKey") as? NSNumber)?.intValue
                    out.append(MenuShortcut(path: next, keys: MenuRules.shortcutText(char: char, modifiers: mods, keyCode: code)))
                }
                walk(child, next, depth: depth + 1)
            }
        }
        walk(bar, [], depth: 0)
        return out
    }
}
