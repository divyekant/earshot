import EarshotCore
import Foundation

/// The tuning of the wake trigger.
public struct WakeConfig: Sendable, Equatable {
    /// The audio gate for the end of the turn and for follow-up turns.
    public var detector = DetectorConfig()
    /// After the wake phrase, the time that the turn waits for the command if the owner pauses.
    public var graceMs: Double = 2000
    /// After a command, the time in which the owner's voice can give the next command with no wake phrase.
    public var followUpSeconds: Double = 5
    /// A follow-up turn with less audio than this has no voice check: the score is not sure on short audio.
    /// It is dropped instead.
    public var minimumFollowUpSeconds: Double = 0.5

    public init() {}
}

/// The always-on trigger (R-ON-1, R-ON-3, D-11). It opens a turn only on the wake phrase in the owner's voice.
///
/// 1. It listens for the wake phrase (`WakeListener`). Speech without the phrase never reaches the speech engine,
///    so earshot keeps no text of talk that is not for it.
/// 2. If a voice is enrolled, the voice of the phrase must match it. Else `onRejected` reports the wake, and
///    nothing starts.
/// 3. The turn ends after the command and a short quiet time.
/// 4. For `followUpSeconds` after a command (`openFollowUp()`), speech in the owner's voice starts a turn
///    with no phrase. Its voice is checked at the end of the turn.
///
/// Run every command from this trigger with mode `.alwaysOn`, so that SafetyPolicy blocks risky presses and
/// Send (R-ON-5). Callbacks run on the main thread.
/// It is `@unchecked Sendable` because its state is used only on `queue`, and the callbacks are set and called only
/// on the main thread.
public final class WakeTrigger: CancellableTrigger, PausableTrigger, @unchecked Sendable {
    public var onStart: (() -> Void)?
    public var onStop: (() -> Void)?
    /// The turn was not a command. Drop the text. If nil, `onStop` is called instead.
    public var onCancel: ((String) -> Void)?
    /// The wake phrase opened a turn. It comes right before `onStart`. The speech engine must start
    /// `hit.prerollSeconds` back, so that it hears the phrase and the words after it.
    public var onWake: ((WakeHit) -> Void)?
    /// The wake phrase was heard, but the voice did not match. Nothing started. For the log: it has no text.
    public var onRejected: ((WakeHit) -> Void)?

    public let config: WakeConfig
    private let listener: WakeListener
    private let source: SampleSource
    private let queue = DispatchQueue(label: "earshot.wake", qos: .userInitiated)

    private enum State: Equatable {
        /// Waits for the wake phrase.
        case idle
        /// Waits for the phrase, or for speech in the follow-up window, until the sample time.
        case followUp(until: Int)
        /// A turn that the wake phrase opened.
        case wakeTurn
        /// A turn that speech opened in the follow-up window. The voice is checked at the end.
        case followTurn
    }

    // Used only on `queue`.
    private var state = State.idle
    private var detector: SpeechDetector
    private var running = false
    private var paused = false
    /// The samples seen since the start, at 16 kHz.
    private var clock = 0
    /// Samples that do not fill a level frame yet.
    private var pending: [Float] = []
    /// The levels of the last frames, oldest first, to see if the owner spoke after the phrase.
    private var recentLevels: [Double] = []
    /// The last samples, for the start of a follow-up turn.
    private var recentSamples: [Float] = []
    /// The samples of a follow-up turn, for the voice check.
    private var turnSamples: [Float] = []

    static let rate = 16000
    private var frameSamples: Int { Int(Double(Self.rate) * config.detector.frameMs / 1000) }
    private static let keepLevelFrames = 150
    private static let keepSamples = 16000 / 2

    public init(listener: WakeListener, config: WakeConfig = WakeConfig(), source: SampleSource = MicrophoneSamples()) {
        self.listener = listener
        self.config = config
        self.source = source
        detector = SpeechDetector(config: config.detector)
    }

    public func start() throws {
        let start = queue.sync { () -> Bool in
            if running { return false }
            running = true
            return true
        }
        guard start else { return }
        do {
            try source.start { [weak self] samples in self?.queue.async { self?.feed(samples) } }
        } catch {
            queue.sync { running = false }
            throw error
        }
    }

    public func stop() {
        source.stop()
        let event = queue.sync { () -> SpeechEvent? in
            running = false
            return endTurn()
        }
        if let event { deliver(event) }
    }

    /// Pauses the trigger, for example while the hold key is down or while earshot types.
    /// A pause drops an open turn and closes the follow-up window.
    public func setPaused(_ value: Bool) {
        queue.async { [self] in
            paused = value
            if value, let event = endTurn() { deliver(event) }
        }
    }

    /// A command finished. For `followUpSeconds`, the owner's voice can give the next command with no phrase.
    public func openFollowUp() {
        queue.async { [self] in
            guard running, !paused, state == .idle else { return }
            state = .followUp(until: clock + Int(config.followUpSeconds * Double(Self.rate)))
        }
    }

    /// Feeds samples. It runs on `queue`.
    func feed(_ samples: [Float]) {
        guard running, !paused, !samples.isEmpty else { return }
        clock += samples.count
        remember(samples)
        if state == .followTurn { turnSamples.append(contentsOf: samples) }

        // The spotter listens only between turns. In a turn, the speech engine has the audio.
        var hit: WakeHit?
        if !inTurn { hit = listener.feed(samples) }

        pending.append(contentsOf: samples)
        let frame = frameSamples
        var events: [SpeechEvent] = []
        var offset = 0
        while pending.count - offset >= frame {
            let db = SpeechDetector.db(pending[offset..<(offset + frame)])
            offset += frame
            recentLevels.append(db)
            if let event = level(db) { events.append(event) }
        }
        pending.removeFirst(offset)
        if recentLevels.count > Self.keepLevelFrames * 2 { recentLevels.removeFirst(recentLevels.count - Self.keepLevelFrames) }

        for event in events { handle(event) }
        if let hit { wake(hit) }
        if case .followUp(let until) = state, clock >= until { state = .idle }
    }

    private var inTurn: Bool { state == .wakeTurn || state == .followTurn }

    /// Feeds one level to the detector. Between turns, only the follow-up window can open a turn.
    private func level(_ db: Double) -> SpeechEvent? {
        switch state {
        case .idle:
            detector.track(db: db)
            return nil
        case .followUp, .wakeTurn, .followTurn:
            return detector.feed(db: db)
        }
    }

    private func handle(_ event: SpeechEvent) {
        switch (state, event) {
        case (.followUp, .start):
            state = .followTurn
            // The turn starts a little before the detector saw it, as the speech engine's preroll does.
            turnSamples = Array(recentSamples.suffix(Self.rate / 4))
            deliver(.start)
        case (.wakeTurn, .end), (.wakeTurn, .drop):
            finishTurn()
            deliver(event)
        case (.followTurn, .end):
            let samples = turnSamples
            finishTurn()
            deliver(followUpVerdict(samples))
        case (.followTurn, .drop):
            finishTurn()
            deliver(event)
        default:
            break
        }
    }

    /// The voice check at the end of a follow-up turn.
    private func followUpVerdict(_ samples: [Float]) -> SpeechEvent {
        guard Double(samples.count) >= config.minimumFollowUpSeconds * Double(Self.rate) else {
            return .drop("follow-up too short for a voice check")
        }
        guard let score = listener.voiceScore(samples) else { return .end }
        if score >= listener.voiceThreshold { return .end }
        return .drop(String(format: "not the owner's voice (%.2f)", score))
    }

    private func wake(_ hit: WakeHit) {
        guard !inTurn else { return }
        guard hit.isOwner else {
            listener.reset()
            DispatchQueue.main.async { [weak self] in self?.onRejected?(hit) }
            return
        }
        // Did the owner speak after the phrase already? The spotter fires about 0.3 to 0.5 s after the phrase.
        let frameMs = config.detector.frameMs
        let after = max(0, Int(hit.phraseEndSeconds * 1000 / frameMs) - 5)  // 100 ms after the phrase, as frames
        let threshold = detector.thresholdDb
        let tail = recentLevels.suffix(after)
        let loud = tail.filter { $0 >= threshold }.count
        let heard = loud >= config.detector.startFrames
        let quietFrames = tail.reversed().prefix(while: { $0 < threshold }).count
        detector.open(heardSpeech: heard, quietMs: heard ? Double(quietFrames) * frameMs : 0, graceMs: config.graceMs)
        state = .wakeTurn
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onWake?(hit)
            self.onStart?()
        }
    }

    private func finishTurn() {
        state = .idle
        turnSamples.removeAll()
        listener.reset()
    }

    /// Ends an open turn from the outside. Returns `.drop` if a turn was open.
    private func endTurn() -> SpeechEvent? {
        let open = inTurn
        _ = detector.reset()
        state = .idle
        turnSamples.removeAll()
        pending.removeAll()
        listener.reset()
        return open ? .drop("input stopped") : nil
    }

    private func remember(_ samples: [Float]) {
        recentSamples.append(contentsOf: samples)
        if recentSamples.count > Self.keepSamples * 2 { recentSamples.removeFirst(recentSamples.count - Self.keepSamples) }
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
