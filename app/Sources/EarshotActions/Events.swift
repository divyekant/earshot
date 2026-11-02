import Carbon.HIToolbox
import CoreGraphics

// Keyboard and mouse events. Ported from probe/Sources/EarshotProbe/Keys.swift.
// The front app receives the events. The process needs the Accessibility permission.

enum Keys {
    struct Combo: Equatable {
        let key: CGKeyCode
        let flags: CGEventFlags
    }

    /// The keys that catalogue data can name. There is no "return" and no "enter" here: the catalogue
    /// can never name a combination with Return, for example Command-Return, which sends in Messages (R-NV-5).
    static let codes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "escape": kVK_Escape, "tab": kVK_Tab, "space": kVK_Space,
        "delete": kVK_Delete, "down": kVK_DownArrow, "up": kVK_UpArrow,
        "/": kVK_ANSI_Slash, ".": kVK_ANSI_Period, ",": kVK_ANSI_Comma, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
    ]

    static let escape = Combo(key: CGKeyCode(kVK_Escape), flags: [])
    static let selectAll = Combo(key: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
    static let pageDown = Combo(key: CGKeyCode(kVK_PageDown), flags: [])
    static let pageUp = Combo(key: CGKeyCode(kVK_PageUp), flags: [])
    static let home = Combo(key: CGKeyCode(kVK_Home), flags: [])
    static let end = Combo(key: CGKeyCode(kVK_End), flags: [])
    /// Only two callers use Return: the chat switcher (after the safety check) and the "send" intent.
    static let returnKey = Combo(key: CGKeyCode(kVK_Return), flags: [])

    /// Parses "cmd+k", "ctrl+opt+e" and similar text from the catalogue. Nil for a key that is not in `codes`.
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

    private static func source() -> CGEventSource? { CGEventSource(stateID: .hidSystemState) }

    static func press(_ combo: Combo) {
        let src = source()
        let down = CGEvent(keyboardEventSource: src, virtualKey: combo.key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: combo.key, keyDown: false)
        down?.flags = combo.flags
        up?.flags = combo.flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        // Release the modifier flags. Without this event, macOS can report Command as held afterwards (E0, part A).
        if !combo.flags.isEmpty, let release = CGEvent(source: src) {
            release.type = .flagsChanged
            release.flags = []
            release.post(tap: .cghidEventTap)
        }
    }

    /// Types text as Unicode key events. Control characters are removed first,
    /// so this function can never press Return or Tab (R-NV-5).
    static func type(_ text: String) {
        let units = Array(ActionText.printable(text).utf16)
        let src = source()
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

    /// True while the owner physically holds Command, Control, Option or Shift, for example the hold key.
    static func modifiersDown() -> Bool {
        let f = CGEventSource.flagsState(.hidSystemState)
        return f.contains(.maskCommand) || f.contains(.maskControl) || f.contains(.maskAlternate) || f.contains(.maskShift)
    }
}

enum Mouse {
    static func location() -> CGPoint? { CGEvent(source: nil)?.location }

    static func move(_ p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// One left click at the point. The pointer then goes back to where it was.
    static func click(_ p: CGPoint) {
        let back = location()
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        if let back { move(back) }
    }

    /// Scroll-wheel events at the point. A positive `lines` value scrolls up. The pointer then goes back.
    static func scroll(at p: CGPoint, lines: Int32, times: Int) {
        let back = location()
        move(p)
        for _ in 0..<max(times, 1) {
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)?
                .post(tap: .cghidEventTap)
        }
        if let back { move(back) }
    }
}
