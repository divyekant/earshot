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

    /// A field whose label says that it writes a message, for example
    /// "Message to all-fplbros", "Reply to thread" or "Compose message".
    static func looksLikeComposer(_ element: AXUIElement) -> Bool {
        let words = label(element)
        return ["message", "reply", "compose", "write", "send"].contains { words.contains($0) }
    }

    /// True if the app lets other apps set the field's text. Read-only text, such as a chat bubble, is not settable.
    static func valueSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, "AXValue" as CFString, &settable) == .success && settable.boolValue
    }

    /// The generic message-box rule: an editable text field that is wide
    /// and sits in the lower half of the window, and is not a search field.
    static func isComposer(_ element: AXUIElement, in window: AXUIElement) -> Bool {
        guard isEditableText(element), let f = frame(element), let w = frame(window) else { return false }
        guard f.w >= 0.3 * w.w, f.midY >= w.y + 0.5 * w.h else { return false }
        return !looksLikeSearch(element)
    }

    /// The switcher rule: a settable text field in the upper part of the window.
    /// If its label says search, it matches. Else its label must not say message, reply or compose,
    /// because a thread reply box can sit high in the window (seen in Slack).
    static func isSwitcherField(_ element: AXUIElement, in window: AXUIElement) -> Bool {
        guard isEditableText(element, allowSearch: true), valueSettable(element),
              let f = frame(element), let w = frame(window), f.midY < w.y + 0.6 * w.h else { return false }
        if subrole(element) == "AXSearchField" || looksLikeSearch(element) { return true }
        return !looksLikeComposer(element)
    }

    /// Roles of a result list. The probe can press Return on these, never on a text field or a button.
    static let listRoles: Set<String> = ["AXRow", "AXCell", "AXList", "AXTable", "AXOutline"]

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
    /// If `column` is given, it reads only texts above that element, for example above the message box.
    /// This skips the chat list at the side, which shows the names of other chats.
    static func headerTexts(in window: AXUIElement, column: Frame? = nil, budgetMs: Int = 120, maxNodes: Int = 1500) -> [String] {
        guard let w = frame(window) else { return [] }
        let t0 = Clock.nowNs()
        var queue: [AXUIElement] = [window]
        var index = 0
        var out: [String] = []
        while index < queue.count, index < maxNodes, Clock.ms(since: t0) < Double(budgetMs) {
            let element = queue[index]
            index += 1
            let r = role(element)
            if let f = frame(element), f.w > 0 {
                if f.y > w.y + 0.3 * w.h { continue }
                if let c = column, f.x + f.w < c.x || f.x > c.x + c.w { continue }
            }
            if r == "AXStaticText" || r == "AXTextField" || r == "AXHeading" {
                if let f = frame(element), let c = column, f.midX < c.x || f.midX > c.x + c.w { continue }
                for attribute in ["AXValue", "AXTitle", "AXDescription"] {
                    if let s = string(element, attribute), !s.isEmpty, s.count < 80 { out.append(s) }
                }
            }
            if skipRoles.contains(r) { continue }
            queue.append(contentsOf: elements(element, "AXChildren"))
        }
        return out
    }

    // MARK: - Read-only inspection (the inspect command)

    struct MenuShortcut {
        let path: String
        let keys: String
    }

    /// Reads the menu bar of an app: each menu item that has a key shortcut.
    /// It reads only. It opens no menu and presses nothing.
    static func menuShortcuts(_ app: AXUIElement) -> [MenuShortcut] {
        guard let bar = element(app, "AXMenuBar") else { return [] }
        var out: [MenuShortcut] = []
        func walk(_ element: AXUIElement, _ path: [String], depth: Int) {
            // Bar item, menu, item, submenu, item: "Edit > Find > Find..." is 5 levels down.
            guard depth < 8 else { return }
            for child in elements(element, "AXChildren") {
                // Some apps start titles with an invisible left-to-right mark (U+200E).
                let title = (string(child, "AXTitle") ?? "").replacingOccurrences(of: "\u{200E}", with: "")
                let next = title.isEmpty ? path : path + [title]
                if role(child) == "AXMenuItem", let char = string(child, "AXMenuItemCmdChar"), !char.isEmpty {
                    let mods = (copy(child, "AXMenuItemCmdModifiers") as? NSNumber)?.intValue ?? 0
                    let code = (copy(child, "AXMenuItemCmdVirtualKey") as? NSNumber)?.intValue
                    out.append(MenuShortcut(path: next.joined(separator: " > "), keys: shortcutText(char, mods, code)))
                }
                walk(child, next, depth: depth + 1)
            }
        }
        walk(bar, [], depth: 0)
        return out
    }

    /// AXMenuItemCmdModifiers: 0 = Command only. Add 1 for Shift, 2 for Option, 4 for Control, 8 for no Command.
    private static func shortcutText(_ char: String, _ mods: Int, _ code: Int?) -> String {
        var parts: [String] = []
        if mods & 4 != 0 { parts.append("ctrl") }
        if mods & 2 != 0 { parts.append("opt") }
        if mods & 1 != 0 { parts.append("shift") }
        if mods & 8 == 0 { parts.append("cmd") }
        let names: [UInt32: String] = [0x0D: "return", 0x03: "enter", 0x09: "tab", 0x1B: "escape", 0x20: "space",
                                       0x08: "delete", 0x7F: "delete"]
        let codeNames: [Int: String] = [123: "left", 124: "right", 125: "down", 126: "up", 36: "return", 76: "enter"]
        if let scalar = char.unicodeScalars.first, let name = names[scalar.value] {
            parts.append(name)
        } else if let code, let name = codeNames[code] {
            parts.append(name)
        } else if let scalar = char.unicodeScalars.first, scalar.properties.generalCategory == .control
                    || scalar.properties.generalCategory == .privateUse {
            parts.append("key code \(code.map(String.init) ?? "?")")
        } else {
            parts.append(char.lowercased())
        }
        return parts.joined(separator: "+")
    }

    struct FieldInfo {
        let role: String
        let subrole: String
        let label: String
        let frame: Frame
        let kind: String
        let hasText: Bool
    }

    /// Lists the editable text fields of one window, with the probe's name for each.
    /// It reads only. It reads no field text: it reports only whether a field holds text.
    static func textFields(in window: AXUIElement, budgetMs: Int = 1500, maxNodes: Int = 6000) -> [FieldInfo] {
        let t0 = Clock.nowNs()
        var queue: [AXUIElement] = [window]
        var index = 0
        var out: [FieldInfo] = []
        while index < queue.count, index < maxNodes, Clock.ms(since: t0) < Double(budgetMs) {
            let element = queue[index]
            index += 1
            let r = role(element)
            if textRoles.contains(r), let f = frame(element) {
                let label = ["AXPlaceholderValue", "AXDescription", "AXTitle"]
                    .compactMap { string(element, $0) }.first(where: { !$0.isEmpty }) ?? ""
                let kind = isComposer(element, in: window) ? "message box"
                    : isSwitcherField(element, in: window) ? "search field" : "other"
                out.append(FieldInfo(role: r, subrole: subrole(element), label: String(label.prefix(40)),
                                     frame: f, kind: kind, hasText: !(value(element) ?? "").isEmpty))
                continue
            }
            if ["AXRow", "AXCell", "AXMenuBar", "AXMenu", "AXImage"].contains(r) { continue }
            queue.append(contentsOf: elements(element, "AXChildren"))
        }
        return out
    }

    /// Finds the app's own search field: an editable field in the upper part of the window
    /// that is a search field or has "search" in its label. It returns the highest one.
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

    /// Finds short texts that contain "(you)". Chat apps mark the owner's own chat this way.
    /// The result gives the name that the owner's own chat shows. It reads no other text.
    static func ownChatNames(in window: AXUIElement, budgetMs: Int = 1500, maxNodes: Int = 8000) -> [String] {
        let t0 = Clock.nowNs()
        var queue: [AXUIElement] = [window]
        var index = 0
        var out: [String] = []
        while index < queue.count, index < maxNodes, out.count < 5, Clock.ms(since: t0) < Double(budgetMs) {
            let element = queue[index]
            index += 1
            for attribute in ["AXValue", "AXTitle", "AXDescription"] {
                if let s = string(element, attribute), s.count < 60, s.lowercased().contains("(you)"), !out.contains(s) {
                    out.append(s)
                }
            }
            if ["AXMenuBar", "AXMenu", "AXImage"].contains(role(element)) { continue }
            queue.append(contentsOf: elements(element, "AXChildren"))
        }
        return out
    }
}
