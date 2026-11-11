import EarshotCore
import Foundation

// Item 10 of the gap list (2026-11-11): the owner always knows if earshot listens. The menu bar icon shows the state.

/// What earshot does with the microphone now. The menu bar icon and the first menu line show it.
public enum ListenState: String, CaseIterable, Sendable {
    /// The owner paused earshot ("Pause for 1 hour"). No input runs: no wake phrase and no hold key.
    case paused
    /// earshot waits for the hold key, or for the wake phrase in always-on mode.
    case idle
    /// A turn is open: earshot hears a command now.
    case listening
    /// Always-on: for a short time after a command, the owner's voice can give the next one with no wake phrase.
    case followUp
    /// The next turn is text to type: after a bare "type", or right after earshot typed in always-on mode.
    case textExpected

    /// The SF Symbol of the menu bar icon. The app shows "ear" if a symbol is not on this Mac.
    public var symbol: String {
        switch self {
        case .paused: return "pause.circle"
        case .idle: return "ear"
        case .listening: return "ear.fill"
        case .followUp: return "ear.badge.waveform"
        case .textExpected: return "text.cursor"
        }
    }

    /// The first line of the menu.
    public func label(mode: InputMode, wakePhrase: String, pausedUntil: Date? = nil) -> String {
        switch self {
        case .paused:
            let time = pausedUntil.map { " until " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
            return "Paused\(time): earshot does not listen"
        case .idle:
            return mode == .alwaysOn ? "Waits for \"\(wakePhrase)\" or the hold key" : "Waits for the hold key"
        case .listening: return "Listens to a command"
        case .followUp: return "Listens for a next command in your voice"
        case .textExpected: return "Waits for the text to type"
        }
    }
}

/// The facts that give the listen state. A pure value, so the tests can set the clock.
public struct ListenClock: Equatable, Sendable {
    /// The end of a pause, or nil if earshot is not paused.
    public var pausedUntil: Date?
    /// True while a turn is open (from the start of the turn to its end or its drop).
    public var turnOpen = false
    /// The end of the follow-up window (always-on), or nil.
    public var followUpUntil: Date?
    /// The end of the time in which the next turn is text to type, or nil.
    public var textUntil: Date?

    public init() {}

    /// The state at `now`. A pause wins, then an open turn, then text, then the follow-up window.
    public func state(at now: Date) -> ListenState {
        if let p = pausedUntil, now < p { return .paused }
        if turnOpen { return .listening }
        if let t = textUntil, now < t { return .textExpected }
        if let f = followUpUntil, now < f { return .followUp }
        return .idle
    }

    /// The next time at which the state changes by the clock alone, or nil. The app reads the state again then.
    public func nextChange(after now: Date) -> Date? {
        [pausedUntil, textUntil, followUpUntil].compactMap { $0 }.filter { $0 > now }.min()
    }

    /// A turn started: the windows of the last turn end.
    public mutating func turnStarted() {
        turnOpen = true
        followUpUntil = nil
        textUntil = nil
    }

    /// A turn was dropped (another voice, too short, or the hold key took over). No window opens.
    public mutating func turnDropped() {
        turnOpen = false
        followUpUntil = nil
        textUntil = nil
    }

    /// A turn finished.
    /// - `followUpSeconds`: the follow-up window after the result sound, or nil if no window opens (hold mode, or
    ///   a turn that opens no window).
    /// - `soundSeconds`: the length of the result sound. The window starts when the sound ends.
    /// - `armedUntil`: the end of the window after a bare "type", if the pipeline armed one.
    /// - `expectsText`: the next turn in the follow-up window holds text (always-on, right after a typing).
    public mutating func turnFinished(at now: Date, followUpSeconds: Double?, soundSeconds: Double = 0,
                                      armedUntil: Date? = nil, expectsText: Bool = false) {
        turnOpen = false
        followUpUntil = followUpSeconds.map { now.addingTimeInterval(soundSeconds + $0) }
        textUntil = armedUntil ?? (expectsText ? followUpUntil : nil)
    }
}
