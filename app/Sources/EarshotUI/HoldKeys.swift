import EarshotCore
import Foundation

/// Hold-key choices for the General tab. The hold key is configurable (R-ON-4).
/// A modifier key alone is the best hold key: it types nothing, and the input module reads it from flagsChanged events (E0).
public struct HoldKeyChoice: Hashable, Sendable, Identifiable {
    public var code: UInt32
    public var name: String
    public var modifierOnly: Bool
    public var id: UInt32 { code }

    public init(code: UInt32, name: String, modifierOnly: Bool) {
        self.code = code; self.name = name; self.modifierOnly = modifierOnly
    }
}

public enum HoldKeys {
    /// Modifier keys that the owner can hold alone. Virtual key codes from the macOS HIToolbox (kVK_*).
    public static let modifiers: [HoldKeyChoice] = [
        HoldKeyChoice(code: 61, name: "Right Option", modifierOnly: true),
        HoldKeyChoice(code: 58, name: "Left Option", modifierOnly: true),
        HoldKeyChoice(code: 54, name: "Right Command", modifierOnly: true),
        HoldKeyChoice(code: 62, name: "Right Control", modifierOnly: true),
        HoldKeyChoice(code: 59, name: "Left Control", modifierOnly: true),
        HoldKeyChoice(code: 60, name: "Right Shift", modifierOnly: true),
        HoldKeyChoice(code: 63, name: "Fn (Globe)", modifierOnly: true),
    ]

    /// Names of other keys that the owner can record. Keys that are not in this table show their code.
    static let otherNames: [UInt32: String] = [
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
        109: "F10", 111: "F12", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        118: "F4", 120: "F2", 122: "F1", 49: "Space", 36: "Return", 53: "Escape", 57: "Caps Lock",
    ]

    /// Modifier flag bits (NSEvent.ModifierFlags raw values) and their names, in the order that macOS shows them.
    static let modifierFlagNames: [(UInt32, String)] = [
        (1 << 18, "Control"), (1 << 19, "Option"), (1 << 17, "Shift"), (1 << 20, "Command"),
    ]

    public static func isModifierKey(_ code: UInt32) -> Bool { modifiers.contains { $0.code == code } || code == 55 || code == 56 }

    /// The name of the key in the settings, for example "Right Option" or "Control + F5".
    public static func name(code: UInt32, modifierOnly: Bool, modifiers flags: UInt32) -> String {
        if modifierOnly, let m = modifiers.first(where: { $0.code == code }) { return m.name }
        if code == 55 { return "Left Command" }
        if code == 56 { return "Left Shift" }
        let key = otherNames[code] ?? "Key \(code)"
        let mods = modifierFlagNames.filter { flags & $0.0 != 0 }.map(\.1)
        return (mods + [key]).joined(separator: " + ")
    }

    public static func name(of settings: EarshotSettings) -> String {
        name(code: settings.holdKeyCode, modifierOnly: settings.holdKeyIsModifierOnly, modifiers: settings.holdKeyModifiers)
    }

    /// Writes a recorded key into the settings. A modifier key alone becomes a modifier-only hold key.
    public static func apply(code: UInt32, modifiers flags: UInt32, to settings: inout EarshotSettings) {
        settings.holdKeyCode = code
        settings.holdKeyIsModifierOnly = isModifierKey(code)
        let mask = modifierFlagNames.reduce(UInt32(0)) { $0 | $1.0 }
        settings.holdKeyModifiers = settings.holdKeyIsModifierOnly ? 0 : flags & mask
    }

    /// A warning for a hold key that can cause problems, or nil.
    public static func warning(code: UInt32, modifierOnly: Bool, modifiers flags: UInt32) -> String? {
        if [36, 76].contains(code) { return "Return can send a message. Use a different key." }
        if code == 49 && flags == 0 { return "Space alone types a space in the front app. Use a modifier key." }
        if code == 53 { return "Escape closes dialogs in the front app. Use a different key." }
        if !modifierOnly && flags == 0 && otherNames[code] == nil { return "This key types a character in the front app. Use a modifier key." }
        return nil
    }
}
