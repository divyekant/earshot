import AppKit
import ApplicationServices

// Helpers over the macOS Accessibility (AX) API. Ported from probe/Sources/EarshotProbe/AX.swift (E0 to E2).
// AX coordinates have their origin at the top left of the main screen.

/// A frame in screen points, with the origin at the top left of the main screen.
public struct Frame: Equatable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public var midX: Double { x + w / 2 }
    public var midY: Double { y + h / 2 }
    public func contains(_ p: CGPoint) -> Bool { p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY }
    /// True if the two frames share at least one point.
    public func overlaps(_ o: Frame) -> Bool { x < o.maxX && maxX > o.x && y < o.maxY && maxY > o.y }
}

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

    static func text(_ v: CFTypeRef?) -> String? {
        guard let v else { return nil }
        if let s = v as? String { return s }
        if let a = v as? NSAttributedString { return a.string }
        return nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? { text(copy(element, attribute)) }
    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? { (copy(element, attribute) as? NSNumber)?.boolValue }
    static func role(_ element: AXUIElement) -> String { string(element, "AXRole") ?? "" }
    static func subrole(_ element: AXUIElement) -> String { string(element, "AXSubrole") ?? "" }
    static func value(_ element: AXUIElement) -> String? { string(element, "AXValue") }

    static func frame(_ element: AXUIElement) -> Frame? {
        guard let p = copy(element, "AXPosition"), let s = copy(element, "AXSize") else { return nil }
        return frame(position: p, size: s)
    }

    static func frame(position p: CFTypeRef, size s: CFTypeRef) -> Frame? {
        guard CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
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

    /// The process id of the app that has keyboard focus.
    static func frontPid() -> pid_t? {
        let system = AXUIElementCreateSystemWide()
        guard let app = element(system, "AXFocusedApplication") else {
            return NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        return pid(app)
    }

    static func focused(_ app: AXUIElement) -> AXUIElement? { element(app, "AXFocusedUIElement") }
    static func window(_ app: AXUIElement) -> AXUIElement? { element(app, "AXFocusedWindow") ?? element(app, "AXMainWindow") }

    /// The actions that the element offers, for example "AXPress".
    static func actions(_ el: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success, let list = names as? [String] else { return [] }
        return list
    }

    @discardableResult
    static func perform(_ el: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(el, action as CFString) == .success
    }

    /// The top element on screen at the point, over all apps.
    static func hit(_ p: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &hit) == .success else { return nil }
        return hit
    }

    /// Reads many attributes in one call. Missing attributes are left out.
    static func multi(_ el: AXUIElement, _ names: [String]) -> [String: CFTypeRef] {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(el, names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
              let array = values as? [AnyObject] else { return [:] }
        var out: [String: CFTypeRef] = [:]
        for (i, v) in array.enumerated() where i < names.count {
            if CFGetTypeID(v) == AXValueGetTypeID(), AXValueGetType(v as! AXValue) == .axError { continue }
            out[names[i]] = v
        }
        return out
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

    /// The words that label a field: placeholder, description, title, help and role description.
    static func label(_ element: AXUIElement) -> String {
        ["AXPlaceholderValue", "AXDescription", "AXTitle", "AXHelp", "AXRoleDescription"]
            .compactMap { string(element, $0)?.lowercased() }
            .joined(separator: " ")
            .replacingOccurrences(of: "\u{200E}", with: "")
    }

    static func looksLikeSearch(_ element: AXUIElement) -> Bool { ActionRules.labelSaysSearch(label(element)) }
    static func looksLikeComposer(_ element: AXUIElement) -> Bool { ActionRules.labelSaysComposer(label(element)) }

    /// True if the app lets other apps set the field's text. Read-only text, such as a chat bubble, is not settable.
    static func valueSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, "AXValue" as CFString, &settable) == .success && settable.boolValue
    }

    /// The message-box rule (E0): an editable text field that is wide, sits in the lower half of the window,
    /// and is not a search field.
    static func isComposer(_ element: AXUIElement, in window: AXUIElement) -> Bool {
        guard isEditableText(element), let f = frame(element), let w = frame(window) else { return false }
        return ActionRules.composerShape(field: f, window: w) && !looksLikeSearch(element)
    }

    /// The switcher rule (E0): a settable text field in the upper part of the window. See the probe for the cases.
    static func isSwitcherField(_ element: AXUIElement, in window: AXUIElement) -> Bool {
        // WhatsApp shows its search field as AXStaticText with the AXSearchField subrole.
        let searchSubrole = subrole(element) == "AXSearchField"
        guard (isEditableText(element, allowSearch: true) && valueSettable(element)) || searchSubrole,
              let f = frame(element), let w = frame(window), f.midY < w.y + 0.6 * w.h else { return false }
        if searchSubrole || looksLikeSearch(element) { return true }
        if looksLikeComposer(element) { return false }
        // A field with no own name must be one line. Messages shows chat bubbles as unlabelled, settable AXTextArea elements.
        let named = ["AXPlaceholderValue", "AXDescription", "AXTitle"].contains {
            !(string(element, $0) ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
        return named || role(element) != "AXTextArea"
    }

    /// Roles of a result list. earshot can press Return on these, never on a text field or a button.
    static let listRoles: Set<String> = ["AXRow", "AXCell", "AXList", "AXTable", "AXOutline"]
    static let skipRoles: Set<String> = ["AXList", "AXTable", "AXOutline", "AXRow", "AXCell", "AXMenuBar", "AXMenu", "AXImage"]

    /// Breadth-first search of one window for the message box. It skips message lists and the upper half of the window.
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
                if best == nil || f.maxY > best!.1.maxY || (f.maxY == best!.1.maxY && f.w > best!.1.w) { best = (element, f) }
                continue
            }
            if skipRoles.contains(r) { continue }
            if let f = frame(element), f.w > 0, f.maxY < w.y + 0.5 * w.h, !CFEqual(element, window) { continue }
            queue.append(contentsOf: elements(element, "AXChildren").reversed())
        }
        return (best?.0, index)
    }

    /// Reads the names at a few points above the message box with hit tests in the top band of the window.
    /// One hit test is one call, so this is fast also in apps with a large tree (WhatsApp, E0).
    static func headerHits(app: AXUIElement, window: AXUIElement, column: Frame?, skip: AXUIElement?) -> [String] {
        guard let w = frame(window) else { return [] }
        let c = column ?? w
        var out: [String] = []
        for fy in [0.02, 0.04, 0.07] {
            for fx in [0.05, 0.15, 0.3, 0.5] {
                var hit: AXUIElement?
                guard AXUIElementCopyElementAtPosition(app, Float(c.x + fx * c.w), Float(w.y + fy * w.h), &hit) == .success,
                      let el = hit else { continue }
                if let skip, CFEqual(el, skip) { continue }
                let r = role(el)
                // A text field shows what someone typed, not the chat name.
                if textRoles.contains(r) && isEditableText(el, allowSearch: true) { continue }
                let attributes = r == "AXStaticText" || r == "AXHeading" ? ["AXValue", "AXTitle", "AXDescription"] : ["AXTitle", "AXDescription"]
                for attribute in attributes {
                    if let s = string(el, attribute)?.replacingOccurrences(of: "\u{200E}", with: ""),
                       !s.isEmpty, s.count < 80, !out.contains(s) { out.append(s) }
                }
            }
        }
        return out
    }

    /// The chat name sits in the top 15 % of the window. A larger band also reads messages (WhatsApp, E0).
    static let headerBand = 0.15

    /// Reads short visible texts in the header band, above `column` only, so that the chat list at the side is left out.
    /// `skip` is an element to leave out with its children, for example the field that earshot typed the name into.
    static func headerTexts(in window: AXUIElement, column: Frame? = nil, skip: AXUIElement? = nil,
                            budgetMs: Int = 120, maxNodes: Int = 1500) -> [String] {
        guard let w = frame(window) else { return [] }
        let t0 = Clock.nowNs()
        var queue: [AXUIElement] = [window]
        var index = 0
        var out: [String] = []
        while index < queue.count, index < maxNodes, Clock.ms(since: t0) < Double(budgetMs) {
            let element = queue[index]
            index += 1
            if let skip, CFEqual(element, skip) { continue }
            let r = role(element)
            if let f = frame(element), f.w > 0 {
                if f.y > w.y + headerBand * w.h { continue }
                if let c = column, f.x + f.w < c.x || f.x > c.x + c.w { continue }
            }
            let textRole = r == "AXStaticText" || r == "AXTextField" || r == "AXHeading"
            let namedRole = r == "AXButton" || r == "AXLink" || r == "AXGroup"
            if textRole || namedRole {
                if let f = frame(element), let c = column, f.midX < c.x || f.midX > c.x + c.w { continue }
                for attribute in textRole ? ["AXValue", "AXTitle", "AXDescription"] : ["AXTitle", "AXDescription"] {
                    if let s = string(element, attribute), !s.isEmpty, s.count < 80, !out.contains(s) { out.append(s) }
                }
            }
            if skipRoles.contains(r) { continue }
            queue.append(contentsOf: elements(element, "AXChildren"))
        }
        return out
    }

    /// The app's own search field: an editable field in the upper part of the window that is a search field
    /// or has "search" in its label. It returns the highest one.
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
                   let f = frame(element), best == nil || f.y < best!.1.y { best = (element, f) }
                continue
            }
            if skipRoles.contains(r) { continue }
            if let f = frame(element), f.w > 0, f.y > w.y + 0.6 * w.h { continue }
            queue.append(contentsOf: elements(element, "AXChildren"))
        }
        return best?.0
    }

    /// A short description of the focused element for the log. It holds no field text.
    static func describeFocus(_ app: AXUIElement) -> String {
        guard let el = focused(app) else { return "no focus" }
        let sub = subrole(el)
        return "focus: \(role(el))\(sub.isEmpty ? "" : "/" + sub) \"\(label(el).prefix(40))\""
    }

    // MARK: - Menus

    /// Finds an enabled menu item with this title in the menu bar, for example "Back".
    /// It reads only: it opens no menu. Depth: bar, bar item, menu, item, submenu, item.
    static func menuItem(_ app: AXUIElement, titled wanted: String, budgetMs: Int = 150) -> AXUIElement? {
        guard let bar = element(app, "AXMenuBar") else { return nil }
        let key = SafetyPolicy.normalize(wanted)
        let t0 = Clock.nowNs()
        var queue: [(AXUIElement, Int)] = [(bar, 0)]
        var index = 0
        while index < queue.count, Clock.ms(since: t0) < Double(budgetMs) {
            let (el, depth) = queue[index]
            index += 1
            if role(el) == "AXMenuItem", SafetyPolicy.normalize(string(el, "AXTitle") ?? "") == key, bool(el, "AXEnabled") != false {
                return el
            }
            if depth < 6 { queue.append(contentsOf: elements(el, "AXChildren").map { ($0, depth + 1) }) }
        }
        return nil
    }
}

// MARK: - Time

enum Clock {
    static func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    static func ms(since t0: UInt64) -> Double { Double(nowNs() &- t0) / 1_000_000 }
}

/// Records the time of each stage, in ms after the start of the command.
final class Stopwatch {
    let t0 = Clock.nowNs()
    private(set) var stages: [String: Double] = [:]
    func mark(_ name: String) { stages[name] = (Clock.ms(since: t0) * 10).rounded() / 10 }
}

func sleepMs(_ ms: Int) async {
    try? await Task.sleep(nanoseconds: UInt64(max(ms, 0)) * 1_000_000)
}

/// Polls `condition` until it is true or the time runs out. The sleep between polls lets the main run loop work.
@MainActor
func waitUntil(timeoutMs: Int, intervalMs: Int = 10, _ condition: () -> Bool) async -> Bool {
    let t0 = Clock.nowNs()
    while true {
        if condition() { return true }
        if Clock.ms(since: t0) >= Double(timeoutMs) { return false }
        await sleepMs(intervalMs)
    }
}
