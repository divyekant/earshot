import AppKit
import EarshotCore
import Foundation

/// The push-to-talk trigger (R-ON-4). Hold the key to listen, release it to run the command.
///
/// It reads key events with NSEvent monitors. The global monitor sees keys in other apps;
/// macOS gives these events only if earshot has the Accessibility permission.
/// The monitors only watch: they do not stop the key from reaching the front app.
/// So the best hold key is a modifier key alone, because it types nothing (E0).
///
/// Callbacks run on the main thread.
public final class HoldKeyTrigger: InputTrigger {
    public var onStart: (() -> Void)?
    public var onStop: (() -> Void)?
    /// The hold was not a command (a tap, or a typed character). Drop the text.
    /// If this is nil, the trigger calls `onStop` instead, so that start and stop always come in pairs.
    public var onCancel: ((String) -> Void)?

    /// A hold longer than this stops by itself. It protects against a lost key-up event.
    public var maximumHold: TimeInterval = 60

    private var state: KeyHold
    private var monitors: [Any] = []
    private var watchdog: DispatchWorkItem?

    public init(code: UInt32, modifierOnly: Bool, modifiers: UInt32 = 0, minimumHold: TimeInterval = 0.15) {
        state = KeyHold(code: UInt16(truncatingIfNeeded: code), modifierOnly: modifierOnly,
                        modifiers: UInt(modifiers), minimumHold: minimumHold)
    }

    public convenience init(settings: EarshotSettings) {
        self.init(code: settings.holdKeyCode, modifierOnly: settings.holdKeyIsModifierOnly, modifiers: settings.holdKeyModifiers)
    }

    /// True while the key is down and the hold is a command.
    public var isHolding: Bool { state.active }

    /// True if macOS lets earshot read keys in other apps (the Accessibility permission).
    public static var canReadOtherApps: Bool { AXIsProcessTrusted() }

    /// Adds the monitors. Call on the main thread.
    public func start() throws {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.receive($0) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] in self?.receive($0); return $0 }) {
            monitors.append(local)
        }
        if monitors.isEmpty { throw InputError("macOS did not add the key monitors") }
    }

    public func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        if let action = state.reset() { perform(action) }
    }

    /// Feeds one event. The monitors call this; the tests can call it too.
    public func receive(_ event: NSEvent) {
        let kind: KeyEvent.Kind
        switch event.type {
        case .flagsChanged: kind = .flagsChanged
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        default: return
        }
        let repeatFlag = kind == .flagsChanged ? false : event.isARepeat
        receive(KeyEvent(kind, code: event.keyCode, flags: event.modifierFlags.rawValue, isRepeat: repeatFlag,
                         time: event.timestamp))
    }

    public func receive(_ event: KeyEvent) {
        if let action = state.handle(event) { perform(action) }
    }

    private func perform(_ action: HoldAction) {
        watchdog?.cancel()
        watchdog = nil
        switch action {
        case .start:
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.state.reset() != nil else { return }
                self.perform(.cancel("held longer than \(Int(self.maximumHold)) s"))
            }
            watchdog = item
            DispatchQueue.main.asyncAfter(deadline: .now() + maximumHold, execute: item)
            onStart?()
        case .stop:
            onStop?()
        case .cancel(let why):
            if let onCancel { onCancel(why) } else { onStop?() }
        }
    }
}

public struct InputError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}
