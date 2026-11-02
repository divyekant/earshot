import Foundation

/// One key event, in a form that the tests can make without AppKit.
/// `flags` is the raw value of NSEvent.ModifierFlags. It holds the device bits for left and right keys.
public struct KeyEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case flagsChanged, keyDown, keyUp }
    public var kind: Kind
    public var code: UInt16
    public var flags: UInt
    public var isRepeat: Bool
    /// Seconds, from any fixed start. NSEvent.timestamp is good.
    public var time: TimeInterval

    public init(_ kind: Kind, code: UInt16, flags: UInt = 0, isRepeat: Bool = false, time: TimeInterval = 0) {
        self.kind = kind; self.code = code; self.flags = flags; self.isRepeat = isRepeat; self.time = time
    }
}

/// What the hold key does to the utterance.
public enum HoldAction: Sendable, Equatable {
    /// The key went down: start to listen.
    case start
    /// The key came up: stop, and use the text.
    case stop
    /// Not a command: the owner typed a character with the key, or tapped it. Stop, and drop the text.
    case cancel(String)
}

/// Modifier bits. The device bits (NX_DEVICE*KEYMASK in IOKit) tell the left key from the right key.
public enum ModifierBits {
    public static let capsLock: UInt = 1 << 16
    public static let shift: UInt = 1 << 17
    public static let control: UInt = 1 << 18
    public static let option: UInt = 1 << 19
    public static let command: UInt = 1 << 20
    public static let function: UInt = 1 << 23
    /// The four modifiers that change a key: Shift, Control, Option, Command.
    public static let main: UInt = shift | control | option | command

    /// Device bit for each modifier key code (kVK_*). Fn has no device bit; it uses `function`.
    public static let deviceBit: [UInt16: UInt] = [
        59: 0x0001, // left Control
        56: 0x0002, // left Shift
        60: 0x0004, // right Shift
        55: 0x0008, // left Command
        54: 0x0010, // right Command
        58: 0x0020, // left Option
        61: 0x0040, // right Option
        62: 0x2000, // right Control
        63: function, // Fn (Globe)
    ]
    /// All device bits together, plus Fn.
    public static let allDevice: UInt = deviceBit.values.reduce(0, |)

    public static func isModifierKey(_ code: UInt16) -> Bool { deviceBit[code] != nil }
}

/// The state machine of the hold key (R-ON-4). It has no AppKit code, so that the tests can run it.
///
/// A modifier key alone (default: right Option, code 61) works like this:
/// - It starts only if no other modifier is down. Option+Shift is for typing, not for earshot.
/// - Another key or modifier during the hold cancels: the owner types a character, for example Option+E.
/// - A tap shorter than `minimumHold` cancels. A brush of the key does not send a command.
///
/// A normal key (for example F13 or Control+F5) starts on key down with the exact modifiers, and stops on key up.
/// Key repeats do nothing.
public struct KeyHold: Sendable {
    public let code: UInt16
    public let modifierOnly: Bool
    /// The modifiers for a normal key (NSEvent.ModifierFlags raw bits). Not used for a modifier key alone.
    public let modifiers: UInt
    public let minimumHold: TimeInterval

    public private(set) var active = false
    /// True after a cancel, until the key comes up. So the same press cannot start again.
    private var waitForRelease = false
    private var startTime: TimeInterval = 0

    public init(code: UInt16, modifierOnly: Bool, modifiers: UInt = 0, minimumHold: TimeInterval = 0.15) {
        self.code = code; self.modifierOnly = modifierOnly
        self.modifiers = modifiers & ModifierBits.main; self.minimumHold = minimumHold
    }

    /// Feeds one event. Returns what to do, or nil.
    public mutating func handle(_ e: KeyEvent) -> HoldAction? {
        modifierOnly ? handleModifier(e) : handleKey(e)
    }

    /// Ends a hold from the outside, for example when earshot stops. Returns `.cancel` if a hold was active.
    public mutating func reset() -> HoldAction? {
        defer { active = false; waitForRelease = false }
        return active ? .cancel("input stopped") : nil
    }

    private var ownBit: UInt { ModifierBits.deviceBit[code] ?? 0 }

    private mutating func handleModifier(_ e: KeyEvent) -> HoldAction? {
        switch e.kind {
        case .flagsChanged where e.code == code:
            let down = e.flags & ownBit != 0
            if down {
                guard !active, !waitForRelease else { return nil }
                let others = e.flags & ModifierBits.allDevice & ~ownBit
                if others != 0 { waitForRelease = true; return nil }
                active = true
                startTime = e.time
                return .start
            }
            waitForRelease = false
            guard active else { return nil }
            active = false
            if e.time - startTime < minimumHold { return .cancel("tap shorter than \(Int(minimumHold * 1000)) ms") }
            return .stop
        case .flagsChanged:
            // Another modifier changed during the hold.
            guard active else { return nil }
            if e.flags & ModifierBits.allDevice & ~ownBit != 0 {
                active = false
                waitForRelease = true
                return .cancel("another modifier key was pressed")
            }
            return nil
        case .keyDown:
            guard active else { return nil }
            active = false
            waitForRelease = true
            return .cancel("a key was typed with the hold key")
        case .keyUp:
            return nil
        }
    }

    private mutating func handleKey(_ e: KeyEvent) -> HoldAction? {
        switch e.kind {
        case .keyDown where e.code == code:
            if e.isRepeat || active { return nil }
            guard e.flags & ModifierBits.main == modifiers else { return nil }
            active = true
            startTime = e.time
            return .start
        case .keyUp where e.code == code:
            guard active else { return nil }
            active = false
            if e.time - startTime < minimumHold { return .cancel("tap shorter than \(Int(minimumHold * 1000)) ms") }
            return .stop
        case .keyDown:
            guard active else { return nil }
            active = false
            return .cancel("another key was typed during the hold")
        default:
            return nil
        }
    }
}
