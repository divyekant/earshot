import AppKit
import ApplicationServices

struct Frame {
    let x: Double, y: Double, w: Double, h: Double
    var maxY: Double { y + h }
    var midX: Double { x + w / 2 }
    var midY: Double { y + h / 2 }
}

/// Thin helpers over the macOS Accessibility (AX) API.
/// AX coordinates have their origin at the top left of the main screen.
enum AX {
    static func trusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return error == .success ? value : nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = copy(element, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let v = copy(element, attribute), CFGetTypeID(v) == CFArrayGetTypeID(),
              let array = v as? [AnyObject] else { return [] }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let v = copy(element, attribute) else { return nil }
        if let s = v as? String { return s }
        if let a = v as? NSAttributedString { return a.string }
        return nil
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (copy(element, attribute) as? NSNumber)?.boolValue
    }

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

    static func pid(_ element: AXUIElement) -> pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(element, &p)
        return p
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

    /// The process id of the app that has keyboard focus. AX reads it directly,
    /// so it is correct even while the run loop is busy.
    static func frontPid() -> pid_t? {
        let system = AXUIElementCreateSystemWide()
        guard let app = element(system, "AXFocusedApplication") else {
            return NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        return pid(app)
    }

    static func focused(_ app: AXUIElement) -> AXUIElement? { element(app, "AXFocusedUIElement") }

    static func window(_ app: AXUIElement) -> AXUIElement? {
        element(app, "AXFocusedWindow") ?? element(app, "AXMainWindow")
    }

    // MARK: - Text fields

    static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox"]

    static func isEditableText(_ element: AXUIElement, allowSearch: Bool = false) -> Bool {
        guard textRoles.contains(role(element)) else { return false }
        let sub = subrole(element)
        if sub == "AXSecureTextField" { return false }
        if sub == "AXSearchField" && !allowSearch { return false }
        if bool(element, "AXEnabled") == false { return false }
        return true
    }

    static func looksLikeSearch(_ element: AXUIElement) -> Bool {
        let words = ["AXPlaceholderValue", "AXDescription", "AXTitle", "AXHelp", "AXRoleDescription"]
            .compactMap { string(element, $0)?.lowercased() }
            .joined(separator: " ")
        return words.contains("search") || words.contains("jump to") || words.contains("find")
    }

    /// The generic message-box rule: an editable text field that is wide
    /// and sits in the lower half of the window, and is not a search field.
    static func isComposer(_ element: AXUIElement, in window: AXUIElement) -> Bool {
        guard isEditableText(element), let f = frame(element), let w = frame(window) else { return false }
        guard f.w >= 0.3 * w.w, f.midY >= w.y + 0.5 * w.h else { return false }
        return !looksLikeSearch(element)
    }

    /// The switcher rule: an editable field in the upper part of the window.
    /// A message box never matches, because it sits at the bottom.
    static func isSwitcherField(_ element: AXUIElement, in window: AXUIElement) -> Bool {
        guard isEditableText(element, allowSearch: true), let f = frame(element), let w = frame(window) else { return false }
        return f.midY < w.y + 0.6 * w.h
    }

    private static let skipRoles: Set<String> = ["AXList", "AXTable", "AXOutline", "AXRow", "AXCell", "AXMenuBar", "AXMenu", "AXImage"]

    /// Breadth-first search of one window for the message box. It skips message
    /// lists and the upper half of the window, and stops at the node or time budget.
    /// It returns the lowest, widest match and the number of nodes it read.
    static func findComposer(in window: AXUIElement, budgetMs: Int = 300, maxNodes: Int = 4000) -> (AXUIElement?, Int) {
        guard let w = frame(window) else { return (nil, 0) }
        let t0 = Clock.nowNs()
        var queue: [AXUIElement] = [window]
        var index = 0
        var best: (AXUIElement, Frame)?
        while index < queue.count, index < maxNodes, Clock.ms(since: t0) < Double(budgetMs) {
            let element = queue[index]
            index += 1
            let r = role(element)
            if textRoles.contains(r), isComposer(element, in: window), let f = frame(element) {
                if best == nil || f.maxY > best!.1.maxY || (f.maxY == best!.1.maxY && f.w > best!.1.w) {
                    best = (element, f)
                }
                continue
            }
            if skipRoles.contains(r) { continue }
            if let f = frame(element), f.w > 0, f.maxY < w.y + 0.5 * w.h, !CFEqual(element, window) { continue }
            queue.append(contentsOf: elements(element, "AXChildren").reversed())
        }
        return (best?.0, index)
    }

    /// Reads short visible texts in the top 30 % of the window, for the chat check.
    static func headerTexts(in window: AXUIElement, budgetMs: Int = 120, maxNodes: Int = 1500) -> [String] {
        guard let w = frame(window) else { return [] }
        let t0 = Clock.nowNs()
        var queue: [AXUIElement] = [window]
        var index = 0
        var out: [String] = []
        while index < queue.count, index < maxNodes, Clock.ms(since: t0) < Double(budgetMs) {
            let element = queue[index]
            index += 1
            let r = role(element)
            if let f = frame(element), f.w > 0, f.y > w.y + 0.3 * w.h { continue }
            if r == "AXStaticText" || r == "AXTextField" || r == "AXHeading" {
                for attribute in ["AXValue", "AXTitle", "AXDescription"] {
                    if let s = string(element, attribute), !s.isEmpty, s.count < 80 { out.append(s) }
                }
            }
            if skipRoles.contains(r) { continue }
            queue.append(contentsOf: elements(element, "AXChildren"))
        }
        return out
    }
}
