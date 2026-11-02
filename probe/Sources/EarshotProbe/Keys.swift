import Carbon.HIToolbox
import CoreGraphics

/// Posts keyboard and mouse events. The front app receives them.
/// The process that runs the probe needs the Accessibility permission.
enum Keys {
    struct Combo {
        let key: CGKeyCode
        let flags: CGEventFlags
    }

    static let codes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        // No "return" here: apps.json can never name a key combination with Return,
        // for example Command-Return, which sends a message in Messages (R-NV-5).
        "escape": kVK_Escape, "tab": kVK_Tab, "space": kVK_Space,
        "delete": kVK_Delete, "down": kVK_DownArrow, "up": kVK_UpArrow,
    ]

    static let escape = Combo(key: CGKeyCode(kVK_Escape), flags: [])
    static let returnKey = Combo(key: CGKeyCode(kVK_Return), flags: [])
    static let selectAll = Combo(key: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
    static let deleteKey = Combo(key: CGKeyCode(kVK_Delete), flags: [])

    /// Parses "cmd+k", "ctrl+opt+e" and similar text from apps.json.
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
                guard let code = codes[part] else { return nil }
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
        // Release the modifier flags. Without this event, macOS can report Command as held
        // after the probe stops, and the next command waits 1.5 s for the key (seen in Part A).
        if !combo.flags.isEmpty, let release = CGEvent(source: src) {
            release.type = .flagsChanged
            release.flags = []
            release.post(tap: .cghidEventTap)
        }
    }

    /// Types text as Unicode key events. Control characters are removed first,
    /// so this function can never press Return (R-NV-5).
    static func type(_ text: String) {
        let units = Array(Text.printable(text).utf16)
        let src = source()
        var i = 0
        while i < units.count {
            var end = min(i + 16, units.count)
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
            let chunk = Array(units[i..<end])
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: isDown) else { continue }
                event.flags = []
                chunk.withUnsafeBufferPointer { buffer in
                    event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                }
                event.post(tap: .cghidEventTap)
            }
            i = end
        }
    }

    /// True while you physically hold Command, Control, Option or Shift.
    static func modifiersDown() -> Bool {
        let f = CGEventSource.flagsState(.hidSystemState)
        return f.contains(.maskCommand) || f.contains(.maskControl) || f.contains(.maskAlternate) || f.contains(.maskShift)
    }
}

enum Mouse {
    static func click(_ point: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}

/// Global hot keys through the Carbon hot-key service.
/// This service does not need the Input Monitoring permission.
enum HotKeys {
    nonisolated(unsafe) static var handler: (@MainActor (UInt32, Bool) -> Void)?
    nonisolated(unsafe) private static var refs: [EventHotKeyRef?] = []
    nonisolated(unsafe) private static var installed = false

    static let control = UInt32(controlKey)
    static let option = UInt32(optionKey)

    static func install() {
        guard !installed else { return }
        installed = true
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let callback: EventHandlerUPP = { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKey = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKey)
            if status != noErr { return status }
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let id = hotKey.id
            MainActor.assumeIsolated { HotKeys.handler?(id, pressed) }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, specs.count, &specs, nil, nil)
    }

    @discardableResult
    static func register(id: UInt32, key: Int, modifiers: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4541_5253), id: id) // "EARS"
        let status = RegisterEventHotKey(UInt32(key), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
        return status == noErr
    }
}
