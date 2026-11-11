import AppKit
import EarshotCore
import EarshotInput
import EarshotSpeech
import EarshotUI

// Item 10 of the gap list (2026-11-11): the menu bar shows if earshot listens, and the menu can pause earshot and
// change the mode.

extension AppController {
    /// "Pause for 1 hour".
    static let pauseSeconds: TimeInterval = 3600

    var isPaused: Bool { listenClock.pausedUntil.map { Date() < $0 } ?? false }

    /// The first line of the menu.
    var listenLabel: String {
        listen.label(mode: settings.mode, wakePhrase: settings.wakePhrase, pausedUntil: listenClock.pausedUntil)
    }

    /// Changes the facts of the listen state, sets `listen`, and sets the timer for the next change by the clock.
    func updateListen(_ change: (inout ListenClock) -> Void = { _ in }) {
        change(&listenClock)
        refreshListen()
    }

    /// Reads the state again at the current time. At the end of a pause, earshot listens again.
    func refreshListen() {
        let now = Date()
        if let until = listenClock.pausedUntil, now >= until {
            listenClock.pausedUntil = nil
            startInput()
        }
        let state = listenClock.state(at: now)
        if state != listen { listen = state }
        // The "Listening" note stays for the whole open turn (dk, 2026-11-11). `showsListening` decides which turns
        // show it. It goes when the turn ends.
        if state != .listening { feedback.endListening() }
        listenTimer?.cancel()
        guard let next = listenClock.nextChange(after: now) else { return }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.refreshListen() } }
        listenTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + next.timeIntervalSince(now) + 0.05, execute: work)
    }

    /// True if a turn that starts now shows the "Listening" note. A wake shows it in `onWake`. In always-on mode, a
    /// follow-up turn with no phrase shows it only when text is expected (after "type"): other sounds in the
    /// follow-up window open turns that the voice check drops, and a note for each looked random (live test
    /// 2026-11-11, E7).
    static func showsListening(mode: InputMode, before: ListenState) -> Bool {
        mode == .hold || before == .textExpected
    }

    /// Stops all input for `seconds`: no wake phrase and no hold key. An open turn is dropped, with no action.
    /// The pause is not saved: earshot listens again after a restart.
    func pause(seconds: TimeInterval) {
        // The always-on trigger drops its own open turn when it stops (onCancel). A hold-key turn needs the cancel here.
        let open = input?.isOpen == true && input?.current == .hold
        updateListen {
            $0.turnDropped()
            $0.pausedUntil = Date().addingTimeInterval(seconds)
        }
        startInput()
        if open {
            pipeline.pendingWake = nil
            pipeline.turnVoice = nil
            Task { await pipeline.cancel() }
        }
    }

    /// Ends the pause now.
    func resume() {
        updateListen { $0.pausedUntil = nil }
        startInput()
    }

    /// The mode switch of the menu. It saves the setting, the same as the Manage window.
    func setMode(_ mode: InputMode) {
        guard settings.mode != mode else { return }
        var new = settings
        new.mode = mode
        do { try store.save(new, "settings.json") } catch {
            feedback.show("Mode: \(error.localizedDescription)", ok: false)
            return
        }
        apply(new)
        refreshListen()
    }
}

/// The SF Symbol for the menu bar. A symbol that this macOS does not have shows the ear, so the icon never goes blank.
enum ListenIcon {
    static func symbol(_ state: ListenState) -> String {
        NSImage(systemSymbolName: state.symbol, accessibilityDescription: nil) == nil ? ListenState.idle.symbol : state.symbol
    }
}
