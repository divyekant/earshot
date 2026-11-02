import EarshotCore
import Foundation

/// The always-on trigger (R-ON-1). It starts an utterance when speech starts, and stops it at the end of the turn.
/// No key and no wake word. It is off by default (EarshotSettings.mode is `.hold`).
///
/// This trigger only finds speech. It does not decide if the speech is for earshot.
/// After the speech engine gives the text, use `ForMeGate` (R-ON-2). Run every command from this trigger
/// with mode `.alwaysOn`, so that SafetyPolicy blocks risky presses (R-ON-5).
///
/// Callbacks run on the main thread.
public final class AlwaysOnTrigger: InputTrigger {
    public var onStart: (() -> Void)?
    public var onStop: (() -> Void)?
    /// The sound was not a command (too short or too long). Drop the text.
    /// If this is nil, the trigger calls `onStop` instead, so that start and stop always come in pairs.
    public var onCancel: ((String) -> Void)?

    private let source: LevelSource
    private let queue = DispatchQueue(label: "earshot.alwayson")
    // Used only on `queue`.
    private var detector: SpeechDetector
    private var paused = false
    private var running = false

    public init(config: DetectorConfig = DetectorConfig(), source: LevelSource = MicrophoneLevels()) {
        detector = SpeechDetector(config: config)
        self.source = source
    }

    public func start() throws {
        let frameMs = queue.sync { () -> Double? in
            if running { return nil }
            running = true
            return detector.config.frameMs
        }
        guard let frameMs else { return }
        do {
            try source.start(frameMs: frameMs) { [weak self] db in self?.queue.async { self?.feed(db) } }
        } catch {
            queue.sync { running = false }
            throw error
        }
    }

    public func stop() {
        source.stop()
        let event = queue.sync { () -> SpeechEvent? in
            running = false
            return detector.reset()
        }
        if let event { deliver(event) }
    }

    /// Pauses the detector, for example while the hold key is down or while earshot types.
    /// A pause drops an open turn.
    public func setPaused(_ value: Bool) {
        queue.async { [self] in
            paused = value
            if value, let event = detector.reset() { deliver(event) }
        }
    }

    /// Feeds one level. It runs on `queue`.
    private func feed(_ db: Double) {
        guard running, !paused, let event = detector.feed(db: db) else { return }
        deliver(event)
    }

    private func deliver(_ event: SpeechEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch event {
            case .start: self.onStart?()
            case .end: self.onStop?()
            case .drop(let why): if let c = self.onCancel { c(why) } else { self.onStop?() }
            }
        }
    }
}
