import EarshotCore
import Foundation

/// Makes the trigger from the owner's settings. EarshotApp calls this at start and after a settings change.
public enum InputTriggers {
    /// Mode `.hold`: the hold key only. Mode `.alwaysOn`: the wake phrase, and the hold key as the fallback (R-ON-4).
    /// - Parameter wake: the wake phrase listener (EarshotWake). If it is nil, for example while the models load,
    ///   always-on mode has the hold key only.
    public static func make(_ settings: EarshotSettings, wake: WakeListener? = nil) -> InputSwitch {
        let hold = HoldKeyTrigger(settings: settings)
        var alwaysOn: InputTrigger?
        if settings.mode == .alwaysOn, let wake { alwaysOn = WakeTrigger(listener: wake) }
        return InputSwitch(hold: hold, alwaysOn: alwaysOn)
    }
}

/// Joins the hold key and the always-on trigger into one trigger.
/// The hold key wins: while it is down, always-on pauses, and an open always-on turn is dropped.
/// `current` tells which input started the utterance. Pass it to SafetyPolicy as `mode` (R-ON-5).
///
/// Callbacks run on the main thread. Use this type on the main thread.
public final class InputSwitch: InputTrigger {
    public var onStart: (() -> Void)?
    public var onStop: (() -> Void)?
    /// The utterance was not a command. Drop the text. If nil, `onStop` is called instead.
    public var onCancel: ((String) -> Void)?

    public let hold: InputTrigger
    public let alwaysOn: InputTrigger?
    /// The input of the open utterance, or of the last one after it stopped.
    public private(set) var current: InputMode?
    public private(set) var isOpen = false

    public init(hold: InputTrigger, alwaysOn: InputTrigger?) {
        self.hold = hold
        self.alwaysOn = alwaysOn
        wire()
    }

    public var mode: InputMode { alwaysOn == nil ? .hold : .alwaysOn }

    /// Pauses always-on, for example while earshot types, so that earshot does not hear its own typing.
    public func setAlwaysOnPaused(_ value: Bool) { pauseAlwaysOn(value) }

    /// A command finished: open the follow-up window of always-on. `expectsText`: the next turn holds dictated text,
    /// so it gets the long end silence.
    /// `soundSeconds`: the length of the result sound that plays now. The follow-up window starts after it.
    public func commandFinished(expectsText: Bool = false, soundSeconds: Double = 0) {
        (alwaysOn as? WakeTrigger)?.openFollowUp(longPause: expectsText, afterSeconds: soundSeconds)
    }

    public func start() throws {
        try hold.start()
        do { try alwaysOn?.start() } catch {
            hold.stop()
            throw error
        }
    }

    public func stop() {
        alwaysOn?.stop()
        hold.stop()
    }

    private func wire() {
        hold.onStart = { [weak self] in
            guard let self else { return }
            // Drop an open always-on turn first. The hold key is the stronger signal.
            if self.isOpen, self.current == .alwaysOn { self.close(cancel: "the hold key took over") }
            self.pauseAlwaysOn(true)
            self.open(.hold)
        }
        hold.onStop = { [weak self] in self?.endHold(cancel: nil) }
        setCancel(hold) { [weak self] why in self?.endHold(cancel: why) }

        guard let alwaysOn else { return }
        alwaysOn.onStart = { [weak self] in
            guard let self, !self.isOpen else { return }
            self.open(.alwaysOn)
        }
        alwaysOn.onStop = { [weak self] in
            guard let self, self.isOpen, self.current == .alwaysOn else { return }
            self.close(cancel: nil)
        }
        setCancel(alwaysOn) { [weak self] why in
            guard let self, self.isOpen, self.current == .alwaysOn else { return }
            self.close(cancel: why)
        }
    }

    private func endHold(cancel: String?) {
        if isOpen, current == .hold { close(cancel: cancel) }
        pauseAlwaysOn(false)
    }

    private func open(_ input: InputMode) {
        current = input
        isOpen = true
        onStart?()
    }

    private func close(cancel: String?) {
        isOpen = false
        if let cancel, let onCancel { onCancel(cancel) } else { onStop?() }
    }

    private func pauseAlwaysOn(_ value: Bool) {
        (alwaysOn as? PausableTrigger)?.setPaused(value)
    }

    private func setCancel(_ trigger: InputTrigger, _ handler: @escaping (String) -> Void) {
        if let t = trigger as? CancellableTrigger { t.onCancel = handler }
    }
}

/// A trigger that can report a cancel. The tests use it for fake triggers.
public protocol CancellableTrigger: InputTrigger {
    var onCancel: ((String) -> Void)? { get set }
}

/// A trigger that can pause, for example while the hold key is down.
public protocol PausableTrigger: InputTrigger {
    func setPaused(_ value: Bool)
}

extension HoldKeyTrigger: CancellableTrigger {}
