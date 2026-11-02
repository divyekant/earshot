import AppKit
import Carbon.HIToolbox
import EarshotCore
import Foundation

/// The result of one search in an app's own search.
public struct SearchScan: Sendable {
    public var appID: String
    public var term: String
    /// The chat names below the search field, best first.
    public var names: [String] = []
    public var failure: String?
    /// From the app in front to the name in the field, in ms.
    public var typedMs = 0.0
    /// From the app in front to the last change of the result list, in ms.
    public var resultsMs = 0.0
    /// True if the search closed after the read.
    public var closed = false
}

/// Key events for the search. There is no Return key here: the search can never open a chat
/// or send a message (R-NV-5). Typed text loses its control characters first.
enum SearchKeys {
    struct Combo { let key: CGKeyCode; let flags: CGEventFlags }

    static let codes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "escape": kVK_Escape, "tab": kVK_Tab, "space": kVK_Space, "delete": kVK_Delete,
        "down": kVK_DownArrow, "up": kVK_UpArrow, "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "/": kVK_ANSI_Slash, ".": kVK_ANSI_Period, ",": kVK_ANSI_Comma, ";": kVK_ANSI_Semicolon,
        "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal,
        "'": kVK_ANSI_Quote, "`": kVK_ANSI_Grave, "\\": kVK_ANSI_Backslash,
    ]

    static let escape = Combo(key: CGKeyCode(kVK_Escape), flags: [])
    static let selectAll = Combo(key: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
    static let deleteKey = Combo(key: CGKeyCode(kVK_Delete), flags: [])

    /// Parses "cmd+k", "ctrl+opt+e" and similar catalogue text. Returns nil for keys that it does not know.
    static func parse(_ text: String) -> Combo? {
        var flags: CGEventFlags = []
        var key: CGKeyCode?
        for part in text.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd", "command": flags.insert(.maskCommand)
            case "ctrl", "control": flags.insert(.maskControl)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default:
                guard key == nil, let code = codes[part] else { return nil }
                key = CGKeyCode(code)
            }
        }
        return key.map { Combo(key: $0, flags: flags) }
    }

    static func press(_ combo: Combo) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: combo.key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: combo.key, keyDown: false)
        down?.flags = combo.flags
        up?.flags = combo.flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        // Release the modifier flags, so that macOS does not report Command as held after the press (E0).
        if !combo.flags.isEmpty, let release = CGEvent(source: src) {
            release.type = .flagsChanged
            release.flags = []
            release.post(tap: .cghidEventTap)
        }
    }

    /// Types text as Unicode key events. It removes control characters first, so it can never press Return.
    static func type(_ text: String) {
        let units = Array(Words.printable(text).utf16)
        let src = CGEventSource(stateID: .hidSystemState)
        var i = 0
        while i < units.count {
            var end = min(i + 16, units.count)
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
            let chunk = Array(units[i..<end])
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: isDown) else { continue }
                event.flags = []
                chunk.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress) }
                event.post(tap: .cghidEventTap)
            }
            i = end
        }
    }

    static func modifiersDown() -> Bool {
        let f = CGEventSource.flagsState(.hidSystemState)
        return f.contains(.maskCommand) || f.contains(.maskControl) || f.contains(.maskAlternate) || f.contains(.maskShift)
    }
}

/// Types a name into the app's own search, reads the result list, clears the field and closes the search
/// (E1, sections 3.5 to 5.6). The app's search knows every chat; the sidebar shows only some.
/// It presses the search keys, the name, Command-A, Delete and Escape. It never presses Return,
/// so it opens no chat and sends nothing (R-NV-5).
enum SearchReader {
    static func search(_ app: AppEntry, term: String) async -> SearchScan {
        var out = SearchScan(appID: app.id, term: term)
        let name = Words.squash(Words.printable(term))
        guard !name.isEmpty else { out.failure = "empty term"; out.closed = true; return out }
        guard AX.trusted() else { out.failure = "Accessibility is off"; out.closed = true; return out }
        guard await bringToFront(app.bundleID),
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first?.processIdentifier else {
            out.failure = "\(app.name) did not come to the front"
            out.closed = true
            return out
        }
        // Held modifier keys would change the keys that earshot sends, for example the hold key.
        if SearchKeys.modifiersDown() { _ = await waitUntil(timeoutMs: 1500) { !SearchKeys.modifiersDown() } }
        let el = AX.appElement(pid)
        if app.electron { AX.askForTree(el) }
        // A search that an earlier step left open would stop the focus check. Close it first.
        if searchOpen(el) { _ = await close(el) }
        let t0 = Clock.nowNs()
        let (found, failure) = await typeName(app: app, el: el, name: name)
        out.typedMs = Clock.round1(Clock.ms(since: t0))
        guard let field = found else {
            out.failure = failure
            // A failed search can stay open with the focus on one of its buttons. Escape closes it and sends nothing.
            SearchKeys.press(SearchKeys.escape)
            await sleepMs(150)
            out.closed = await close(el)
            return out
        }
        // Read the list until it stops changing: 3 equal reads, 60 ms apart, 1.5 s at most.
        var last: [String] = []
        var lastChange = Clock.ms(since: t0)
        var stable = 0
        let t1 = Clock.nowNs()
        while Clock.ms(since: t1) < 1500 {
            await sleepMs(60)
            let now = NameRules.results(resultLines(app: el, field: field), term: name, appName: app.name)
            if now == last {
                if !now.isEmpty { stable += 1 }
                if stable >= 2 { break }
            } else {
                stable = 0
                last = now
                lastChange = Clock.ms(since: t0)
            }
        }
        out.names = last
        out.resultsMs = Clock.round1(lastChange)
        // Clear the name only while the focus is still in the search field, never in a message box.
        if let f = AX.focused(el), let win = AX.window(el), AX.isSwitcherField(f, in: win), !AX.isComposer(f, in: win) {
            SearchKeys.press(SearchKeys.selectAll)
            SearchKeys.press(SearchKeys.deleteKey)
        }
        SearchKeys.press(SearchKeys.escape)
        await sleepMs(150)
        out.closed = await close(el, field: field)
        return out
    }

    static func bringToFront(_ bundleID: String) async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        return await waitUntil(timeoutMs: 3000) {
            guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
            else { return false }
            return AX.frontPid() == pid
        }
    }

    /// Opens the search and types the name. The search keys must move the focus into a search field.
    /// If the focus stays where it was, for example in a reply box, earshot stops, so that it never
    /// types the name into a message box.
    static func typeName(app: AppEntry, el: AXUIElement, name: String) async -> (AXUIElement?, String?) {
        let before = AX.focused(el)
        var usedKeys = false
        if case .switcher(let keys) = app.openChat {
            guard MenuRules.isPressable(keys), let combo = SearchKeys.parse(keys) else { return (nil, "keys that earshot cannot press: \(keys)") }
            SearchKeys.press(combo)
            usedKeys = true
        } else {
            guard let win = AX.window(el), let field = AX.findSearchField(in: win),
                  AX.set(field, "AXFocused", kCFBooleanTrue) else { return (nil, "no search field found") }
        }
        var found: AXUIElement?
        let opened = await waitUntil(timeoutMs: 1200) {
            guard let f = AX.focused(el), let win = AX.window(el), AX.isSwitcherField(f, in: win), !AX.isComposer(f, in: win) else { return false }
            if usedKeys, AX.same(f, before) { return false }
            found = f
            return true
        }
        guard opened, let field = found else { return (nil, "the search field did not get focus") }
        // A search field can keep the last search. Select it, so that the name replaces it.
        if !(AX.value(field) ?? "").isEmpty { SearchKeys.press(SearchKeys.selectAll) }
        SearchKeys.type(name)
        let wanted = name.lowercased()
        // Some apps move the focus into an inner field when typing starts. Accept the same field,
        // or another search field that holds exactly the name.
        var typedInto: AXUIElement?
        let typed = await waitUntil(timeoutMs: 1000) {
            guard let f = AX.focused(el), let win = AX.window(el),
                  AX.value(f).map(Words.squash)?.lowercased() == wanted,
                  AX.same(f, field) || (AX.isSwitcherField(f, in: win) && !AX.isComposer(f, in: win)) else { return false }
            typedInto = f
            return true
        }
        guard typed, let target = typedInto else { return (nil, "the search field did not show the name") }
        return (target, nil)
    }

    /// True if a search field has the focus: a switcher field that is not a message box.
    static func searchOpen(_ el: AXUIElement) -> Bool {
        guard let f = AX.focused(el), let win = AX.window(el) else { return false }
        return AX.isSwitcherField(f, in: win) && !AX.isComposer(f, in: win)
    }

    /// Presses Escape while a search field has the focus, or while the typed-into field is still on screen,
    /// 3 times at most. Returns true if the search closed. Escape never sends a message.
    static func close(_ el: AXUIElement, field: AXUIElement? = nil) async -> Bool {
        func open() -> Bool {
            if searchOpen(el) { return true }
            guard let field, let f = AX.frame(field) else { return false }
            return f.w > 0 && f.h > 0
        }
        for _ in 0..<3 {
            if !open() { return true }
            SearchKeys.press(SearchKeys.escape)
            await sleepMs(200)
        }
        return !open()
    }

    /// Reads the screen lines below the search field, in the same column. It joins the texts of one line
    /// ("Prakash" + "Iyer"), and skips the field, message boxes, live regions and the sidebar to the left.
    static func resultLines(app: AXUIElement, field: AXUIElement, budgetMs: Int = 200, maxNodes: Int = 5000) -> [ResultLine] {
        guard let ff = AX.frame(field), let win = AX.window(app), let w = AX.frame(win) else { return [] }
        let right = ff.x + ff.w + 0.05 * w.w
        let bottom = ff.maxY + 0.6 * w.h
        var roots = AX.elements(app, "AXWindows")
        if roots.isEmpty { roots = [win] }
        let t0 = Clock.nowNs()
        var pieces: [(text: String, f: Frame, inRow: Bool)] = []
        var count = 0
        for root in roots {
            var queue: [(AXUIElement, Bool)] = [(root, false)]
            var i = 0
            while i < queue.count, count < maxNodes, Clock.ms(since: t0) < Double(budgetMs) {
                let (el, inRow) = queue[i]
                i += 1
                count += 1
                if CFEqual(el, field) { continue }
                let r = AX.role(el)
                if ["AXMenuBar", "AXImage", "AXScrollBar", "AXToolbar", "AXTextArea"].contains(r) { continue }
                if AX.liveRegions.contains(AX.subrole(el)) { continue }
                let frame = AX.frame(el)
                if let f = frame, f.w > 0, f.h > 0, !CFEqual(el, root) {
                    if f.maxY <= ff.maxY || f.x + f.w < ff.x - 4 || f.x > right || f.y > bottom { continue }
                }
                if let f = frame, f.w > 0, f.h > 0, f.midY > ff.maxY, f.midX >= ff.x - 0.03 * w.w, f.midX <= right {
                    var text: String?
                    if r == "AXStaticText" {
                        let v = AX.string(el, "AXValue") ?? ""
                        text = v.isEmpty ? AX.string(el, "AXDescription") : v
                    } else if r == "AXButton" || r == "AXLink" || r == "AXMenuItem" {
                        text = AX.string(el, "AXTitle") ?? AX.string(el, "AXDescription")
                    }
                    // A piece that is a screen label ("Select", "Give feedback") is not part of a result.
                    if let t = text.map(Words.squash), !t.isEmpty, !NameRules.uiWords.contains(Words.key(t)) {
                        pieces.append((t, f, inRow || r == "AXMenuItem"))
                    }
                }
                let childInRow = inRow || r == "AXRow" || r == "AXCell"
                queue.append(contentsOf: AX.elements(el, "AXChildren").map { ($0, childInRow) })
            }
        }
        return joinLines(pieces.map { ($0.text, $0.f.x, $0.f.midY, $0.f.h, $0.inRow) })
    }

    /// Groups text pieces into screen lines, then joins each line from left to right.
    /// A piece is (text, x, middle y, height, in a row).
    static func joinLines(_ pieces: [(String, Double, Double, Double, Bool)]) -> [ResultLine] {
        let sorted = pieces.sorted { $0.2 < $1.2 }
        var lines: [[(String, Double, Double, Double, Bool)]] = []
        for p in sorted {
            if let last = lines.last?.last, abs(p.2 - last.2) <= max(6, 0.5 * min(p.3, last.3)) {
                lines[lines.count - 1].append(p)
            } else {
                lines.append([p])
            }
        }
        return lines.map { line in
            var words: [String] = []
            for p in line.sorted(by: { $0.1 < $1.1 }) where words.last != p.0 { words.append(p.0) }
            return ResultLine(words.joined(separator: " "), inRow: line.contains { $0.4 })
        }
    }
}
