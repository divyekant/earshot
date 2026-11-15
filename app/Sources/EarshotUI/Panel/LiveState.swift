import EarshotCore
import Foundation

// What earshot does now, in the words of the panel header, the window state chip and the menu bar icon.

/// The facts of the moment, from EarshotApp. A value, so the snapshots and the tests can make one.
public struct LiveState: Equatable, Sendable {
    public var listen: ListenState
    public var mode: InputMode
    public var wakePhrase: String
    /// The hold key on a keycap, for example "⌥ right".
    public var holdKey: String
    public var pausedUntil: Date?
    /// The end of the follow-up window, and its length.
    public var followUntil: Date?
    public var followSeconds: Double
    /// "Ask Jev" or "Jev sees the screen" is on.
    public var cloudOn: Bool
    /// A notice needs the owner: a missing permission, or a plugin that waits for approval.
    public var needsYou: Bool

    public init(listen: ListenState = .idle, mode: InputMode = .hold, wakePhrase: String = WakePhrase.defaultPhrase,
                holdKey: String = "⌥ right", pausedUntil: Date? = nil, followUntil: Date? = nil, followSeconds: Double = 5,
                cloudOn: Bool = false, needsYou: Bool = false) {
        self.listen = listen; self.mode = mode; self.wakePhrase = wakePhrase; self.holdKey = holdKey
        self.pausedUntil = pausedUntil; self.followUntil = followUntil; self.followSeconds = followSeconds
        self.cloudOn = cloudOn; self.needsYou = needsYou
    }

    /// The header of the panel: a title and a line. `key` is true if the line ends with the hold key on a keycap.
    public struct Header: Equatable, Sendable {
        public var title: String
        /// The words before the keycap, the keycap, and the words after it.
        public var before: String
        public var key: String?
        public var after: String
    }

    public var header: Header {
        switch listen {
        case .paused:
            let until = pausedUntil.map { "Until " + $0.formatted(date: .omitted, time: .shortened) + " · " } ?? ""
            return Header(title: "Paused", before: until + "no mic, no keys", key: nil, after: "")
        case .listening:
            return mode == .hold
                ? Header(title: "Hearing you", before: "Let go of", key: holdKey, after: "to run it")
                : Header(title: "Hearing you", before: "Stop to run it", key: nil, after: "")
        case .followUp:
            return Header(title: "Say the next one", before: "Your voice, no phrase needed", key: nil, after: "")
        case .textExpected:
            return Header(title: "Say the text", before: "earshot types your next words", key: nil, after: "")
        case .idle:
            return mode == .alwaysOn
                ? Header(title: "Listening for “\(wakePhrase)”", before: "or hold", key: holdKey, after: "")
                : Header(title: "Ready", before: "Hold", key: holdKey, after: "and speak")
        }
    }

    /// The look of the orb in the panel header.
    public var orb: Orb.Look {
        switch listen {
        case .paused: return .paused
        case .listening: return .hearing
        case .followUp: return followUntil.map { .next(until: $0, seconds: followSeconds) } ?? .still
        case .textExpected: return .text
        case .idle: return needsYou ? .needsYou : (mode == .alwaysOn ? .breathe : .still)
        }
    }

    /// The chip at the top right of the window: the dot, the state and the rest.
    public var chip: (dot: Dot.Tone, state: String, rest: String, key: String?) {
        switch listen {
        case .paused:
            return (.amber, "Paused", pausedUntil.map { "until " + $0.formatted(date: .omitted, time: .shortened) } ?? "", nil)
        case .listening: return (.live, "Hearing you", "", nil)
        case .followUp: return (.live, "Next one", "no phrase needed", nil)
        case .textExpected: return (.live, "Say the text", "", nil)
        case .idle:
            if needsYou { return (.amber, "Needs you", "see the panel", nil) }
            return mode == .alwaysOn ? (.live, "Listening", "for “\(wakePhrase)”", nil) : (.live, "Ready", "hold", Self.capOnly(holdKey))
        }
    }

    /// "⌥ right" gives "⌥": the chip has room for the mark only.
    static func capOnly(_ key: String) -> String { key.split(separator: " ").first.map(String.init) ?? key }

    /// The hold key in a sentence: "⌥ right" gives "the right ⌥ key", "fn" gives "the fn key", "F5" gives "F5".
    public static func holdWords(_ key: String) -> String {
        let parts = key.split(separator: " ").map(String.init)
        if parts.count == 2 { return "the \(parts[1]) \(parts[0]) key" }
        if ["⌥", "⌘", "⌃", "⇧", "fn"].contains(key) { return "the \(key) key" }
        return key
    }
}

extension HoldKeys {
    /// The hold key as the text of a keycap: "Right Option" gives "⌥ right".
    public static func capText(of settings: EarshotSettings) -> String {
        capText(name(of: settings))
    }

    public static func capText(_ name: String) -> String {
        let marks: [(String, String)] = [("Option", "⌥"), ("Command", "⌘"), ("Control", "⌃"), ("Shift", "⇧")]
        for (word, mark) in marks where name.hasSuffix(word) && !name.contains("+") {
            let side = name.dropLast(word.count).trimmingCharacters(in: .whitespaces).lowercased()
            return side.isEmpty ? mark : "\(mark) \(side)"
        }
        if name.hasPrefix("Fn") { return "fn" }
        return name
    }
}

/// One thing that needs the owner, or a long job that the owner may wait for. The panel shows it as a banner.
public struct Notice: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// earshot needs the owner: amber.
        case needsYou
        /// A long job, for example a download: no color.
        case working
    }

    public var id: String
    public var kind: Kind
    public var glyph: GlyphKind
    public var title: String
    public var detail: String
    /// The label of the one key, or nil for no key.
    public var action: String?
    /// The main action of the panel gets the ink key.
    public var main: Bool
    /// 0...1 for a job with a known end.
    public var progress: Double?

    public init(id: String, kind: Kind = .needsYou, glyph: GlyphKind = .failed, title: String, detail: String = "",
                action: String? = nil, main: Bool = false, progress: Double? = nil) {
        self.id = id; self.kind = kind; self.glyph = glyph; self.title = title; self.detail = detail
        self.action = action; self.main = main; self.progress = progress
    }
}
