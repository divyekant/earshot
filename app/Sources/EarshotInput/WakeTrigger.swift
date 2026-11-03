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
    /// The end silence of a turn that is expected to hold dictated text (after "type", or after earshot typed).
    /// Commands keep `detector.endSilenceMs`.
    public var dictationEndSilenceMs: Double = 1200
    /// A follow-up turn with less audio than this has no voice check: the score is not sure on short audio.
    /// It is dropped instead.
    public var minimumFollowUpSeconds: Double = 0.5
    /// In a follow-up turn, the spotter keeps on for this long from the start of the turn. If the owner says the
    /// phrase again in this time, the turn becomes a wake turn (D-11). Live test 2026-11-02: 3 follow-up turns started
    /// with the phrase again, heard as "Yeah, let's".
    public var followTurnWakeSeconds: Double = 2.5
    /// The trigger reports the near misses of the spotter after this much audio, at a wake and at stop (D-11).
    public var nearMissReportSeconds: Double = 60

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
/// 5. In the first `followTurnWakeSeconds` of a follow-up turn, the spotter still listens. If the owner says the
///    phrase again, the turn becomes a wake turn: `onWake` comes with `inTurnAfterSeconds`, and no second `onStart`.
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
    /// Partial matches of the phrase that did not fire, since the last report. For the log: a count and the best
    /// part of the phrase only. No audio and no text (D-11).
    public var onNearMisses: ((NearMisses) -> Void)?

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
    /// The value of `clock` at the start of the turn.
    private var turnStartClock = 0
    /// The value of `clock` at the last near-miss report.
    private var nearMissClock = 0

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
            reportNearMisses()
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
    /// With `longPause`, the next turn in the window (a follow-up or a wake) ends after `dictationEndSilenceMs`.
    /// `afterSeconds`: the length of a result sound that plays now. The detector ignores the sound, and the window
    /// starts when the sound ends (live test: a result sound became a follow-up turn, dropped as another voice).
    public func openFollowUp(longPause: Bool = false, afterSeconds: Double = 0) {
        queue.async { [self] in
            guard running, !paused, state == .idle else { return }
            muteLocked(afterSeconds)
            let after = Int(max(0, afterSeconds) * Double(Self.rate))
            state = .followUp(until: clock + after + Int(config.followUpSeconds * Double(Self.rate)))
            nextTurnLongPause = longPause
        }
    }

    /// The detector ignores the audio for `seconds` from now: earshot plays a sound, and the microphone hears it.
    /// The detector does not change in that time, so the sound opens no turn, ends no turn, and moves no noise floor.
    /// The spotter and the speech engine still get the audio.
    public func mute(seconds: Double) {
        queue.async { [self] in muteLocked(seconds) }
    }

    private func muteLocked(_ seconds: Double) {
        guard seconds > 0 else { return }
        muteUntilClock = max(muteUntilClock, clock + Int(seconds * Double(Self.rate)))
    }

    /// The sample clock until which the detector ignores the audio (`mute`).
    private var muteUntilClock = 0

    /// True if the next turn in the follow-up window uses the long end silence.
    private var nextTurnLongPause = false

    /// Sets the end silence of a turn that starts now: long only in the follow-up window after a dictation cue.
    private func setTurnEndSilence() {
        var open = false
        if case .followUp = state { open = true }
        let dictation = open && nextTurnLongPause
        detector.endSilenceOverrideMs = dictation ? config.dictationEndSilenceMs : nil
        // A dictation turn can be long. Its length limit ends it with its text (DetectorConfig.dictationMaximumTurnMs).
        detector.dictationTurn = dictation
        nextTurnLongPause = false
    }

    /// The audio length of the last follow-up turn at its voice check, in seconds. For the log of a dropped turn.
    public private(set) var lastFollowUpSeconds: Double?

    /// Feeds samples. It runs on `queue`.
    func feed(_ samples: [Float]) {
        guard running, !paused, !samples.isEmpty else { return }
        clock += samples.count
        remember(samples)
        if state == .followTurn { turnSamples.append(contentsOf: samples) }

        // The spotter listens between turns, and at the start of a follow-up turn. Else the speech engine has the audio.
        var hit: WakeHit?
        if !inTurn || spotsInFollowTurn { hit = listener.feed(samples) }

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
        if case .followUp(let until) = state, clock >= until { state = .idle; nextTurnLongPause = false }
        if Double(clock - nearMissClock) >= config.nearMissReportSeconds * Double(Self.rate) { reportNearMisses() }
    }

    private var inTurn: Bool { state == .wakeTurn || state == .followTurn }

    /// True in the first `followTurnWakeSeconds` of a follow-up turn.
    private var spotsInFollowTurn: Bool {
        state == .followTurn && Double(clock - turnStartClock) <= config.followTurnWakeSeconds * Double(Self.rate)
    }

    /// Feeds one level to the detector. Between turns, only the follow-up window can open a turn.
    private func level(_ db: Double) -> SpeechEvent? {
        if clock < muteUntilClock { return nil }
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
            setTurnEndSilence()
            state = .followTurn
            turnStartClock = clock
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

    /// The voice score of the last follow-up turn that passed to the pipeline. Nil if no voice is enrolled, so no
    /// check ran. An always-on "send" needs a checked voice (R-ON-5).
    public private(set) var lastFollowUpVoiceScore: Double?

    /// The voice check at the end of a follow-up turn.
    private func followUpVerdict(_ samples: [Float]) -> SpeechEvent {
        lastFollowUpVoiceScore = nil
        let seconds = Double(samples.count) / Double(Self.rate)
        lastFollowUpSeconds = seconds
        guard seconds >= config.minimumFollowUpSeconds else {
            return .drop(String(format: "\(Self.tooShort) (%.2f s)", seconds))
        }
        guard let score = listener.voiceScore(samples) else { return .end }
        lastFollowUpVoiceScore = score
        if score >= listener.voiceThreshold { return .end }
        return .drop(String(format: "\(Self.otherVoice) (%.2f)", score))
    }

    /// The start of the cancel reason when the voice of a follow-up turn is not the owner's voice.
    public static let otherVoice = "not the owner's voice"
    /// The start of the cancel reason when a follow-up turn is too short for a voice check.
    public static let tooShort = "follow-up too short for a voice check"

    private func wake(_ hit: WakeHit) {
        reportNearMisses()
        if state == .followTurn { return wakeInFollowTurn(hit) }
        guard !inTurn else { return }
        guard hit.isOwner else {
            listener.reset()
            DispatchQueue.main.async { [weak self] in self?.onRejected?(hit) }
            return
        }
        setTurnEndSilence()
        openAfterPhrase(hit)
        state = .wakeTurn
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onWake?(hit)
            self.onStart?()
        }
    }

    /// The owner said the phrase again at the start of a follow-up turn (D-11). The turn becomes a wake turn, so the
    /// pipeline removes the phrase by its time, and the voice of the phrase counts as the voice check.
    /// If the voice does not match, the turn stays a follow-up turn, and its voice is checked at the end.
    private func wakeInFollowTurn(_ hit: WakeHit) {
        guard hit.isOwner else { return }
        var hit = hit
        hit.inTurnAfterSeconds = Double(clock - turnStartClock) / Double(Self.rate)
        openAfterPhrase(hit)
        state = .wakeTurn
        turnSamples.removeAll()
        // The speech engine runs already: no new preroll and no second start.
        DispatchQueue.main.async { [weak self] in self?.onWake?(hit) }
    }

    /// Opens the turn after the phrase, with a grace time for the command if the owner did not speak after it yet.
    private func openAfterPhrase(_ hit: WakeHit) {
        // Did the owner speak after the phrase already? The spotter fires about 0.3 to 0.5 s after the phrase.
        let frameMs = config.detector.frameMs
        let after = max(0, Int(hit.phraseEndSeconds * 1000 / frameMs) - 5)  // 100 ms after the phrase, as frames
        let threshold = detector.thresholdDb
        let quiet = detector.quietDb
        let tail = recentLevels.suffix(after)
        let loud = tail.filter { $0 >= threshold }.count
        let heard = loud >= config.detector.startFrames
        // Only quiet frames count toward the end silence, as in the turn (SpeechDetector.quietDb).
        let quietFrames = tail.reversed().prefix(while: { $0 <= quiet }).count
        detector.open(heardSpeech: heard, quietMs: heard ? Double(quietFrames) * frameMs : 0, graceMs: config.graceMs)
    }

    /// Sends the near misses of the spotter since the last report, if there are some.
    private func reportNearMisses() {
        nearMissClock = clock
        guard let misses = listener.takeNearMisses() else { return }
        DispatchQueue.main.async { [weak self] in self?.onNearMisses?(misses) }
    }

    private func finishTurn() {
        detector.endSilenceOverrideMs = nil
        detector.dictationTurn = false
        state = .idle
        turnSamples.removeAll()
        listener.reset()
    }

    /// Ends an open turn from the outside. Returns `.drop` if a turn was open.
    private func endTurn() -> SpeechEvent? {
        let open = inTurn
        _ = detector.reset()
        detector.endSilenceOverrideMs = nil
        detector.dictationTurn = false
        nextTurnLongPause = false
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
