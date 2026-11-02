import EarshotCore
import Foundation

/// Makes the trigger from the owner's settings. EarshotApp calls this at start and after a settings change.
public enum InputTriggers {
    /// Mode `.hold`: the hold key only. Mode `.alwaysOn`: always-on, and the hold key as the fallback (R-ON-4).
    public static func make(_ settings: EarshotSettings) -> InputSwitch {
        let hold = HoldKeyTrigger(settings: settings)
        return InputSwitch(hold: hold, alwaysOn: settings.mode == .alwaysOn ? AlwaysOnTrigger() : nil)
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
        (alwaysOn as? AlwaysOnTrigger)?.setPaused(value)
    }

    private func setCancel(_ trigger: InputTrigger, _ handler: @escaping (String) -> Void) {
        if let t = trigger as? CancellableTrigger { t.onCancel = handler }
    }
}

/// A trigger that can report a cancel. The tests use it for fake triggers.
public protocol CancellableTrigger: InputTrigger {
    var onCancel: ((String) -> Void)? { get set }
}

extension HoldKeyTrigger: CancellableTrigger {}
extension AlwaysOnTrigger: CancellableTrigger {}
