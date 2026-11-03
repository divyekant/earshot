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
    /// The turn model (Smart Turn v3.2) checks the turn at the first pause (`DetectorConfig.pauseCheckMs`). A
    /// probability at or above this value ends the turn at once. 0.5 is the default of the model card; the log of
    /// each check (`onTurnCheck`) gives the value for the owner's own turns.
    public var turnThreshold: Double = 0.5
    /// If the model hears a pause inside the turn, the turn ends only after this much quiet (a command turn).
    /// Smart Turn's own pipeline and Hex used 2 s.
    public var turnWaitMs: Double = 2000
    /// The same for a dictation turn. Hex's "patient" preset used 3 s.
    public var dictationTurnWaitMs: Double = 3000
    /// The limits of the owner voice check (E6). The phrase alone must pass `voice.gate` to start a turn. At the end
    /// of the turn, the voice of the whole turn decides.
    public var voice = VoiceRule()
    /// The voice check uses the first this many seconds of a turn. A long dictation does not need more.
    public var voiceCheckMaxSeconds: Double = 8

    public init() {}
}

/// The always-on trigger (R-ON-1, R-ON-3, D-11). It opens a turn only on the wake phrase in the owner's voice.
///
/// 1. It listens for the wake phrase (`WakeListener`). Speech without the phrase never reaches the speech engine,
///    so earshot keeps no text of talk that is not for it.
/// 2. If a voice is enrolled, the voice of the phrase must reach `config.voice.gate` (E6). Else `onRejected`
///    reports the wake, and nothing starts.
/// 3. The turn ends after the command and a short quiet time. Then the voice of the whole turn, from the phrase to
///    the end, must reach the limit of `config.voice` for its length. Else the turn is dropped (`onCancel` with
///    `otherVoice`). A whole turn gives a surer score than the phrase alone.
/// 4. For `followUpSeconds` after a command (`openFollowUp()`), speech in the owner's voice starts a turn
///    with no phrase. Its voice is checked at the end of the turn, with the same rule.
/// 5. In the first `followTurnWakeSeconds` of a follow-up turn, the spotter still listens. If the owner says the
///    phrase again, the turn becomes a wake turn: `onWake` comes with `inTurnAfterSeconds`, and no second `onStart`.
/// 6. `onTurnVoice` gives the result of each voice check, right before `onStop` or `onCancel`.
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
    /// The wake phrase was heard, but the voice of the phrase did not reach the gate. Nothing started. For the log:
    /// it has no text.
    public var onRejected: ((WakeHit) -> Void)?
    /// The voice check at the end of a turn. It comes right before `onStop` or `onCancel` of that turn.
    public var onTurnVoice: ((TurnVoice) -> Void)?
    /// Partial matches of the phrase that did not fire, since the last report. For the log: a count and the best
    /// part of the phrase only. No audio and no text (D-11).
    public var onNearMisses: ((NearMisses) -> Void)?
    /// One check of the turn model at a pause. For the log: numbers only (R-ON-1, I-2).
    public var onTurnCheck: ((TurnCheck) -> Void)?

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
    /// The samples of the open turn, for the voice check: at most `voiceCheckMaxSeconds`. A wake turn starts at
    /// the phrase.
    private var turnSamples: [Float] = []
    /// All the samples of the open turn, also after `voiceCheckMaxSeconds`.
    private var turnSampleCount = 0
    /// The wake of the open turn, or nil for a follow-up turn.
    private var turnWake: WakeHit?
    /// The value of `clock` at the start of the turn.
    private var turnStartClock = 0
    /// The last 8.5 s of the open turn (wake or follow-up), for the turn model. It is dropped at the end of the turn.
    private var turnAudio: [Float] = []
    private static let keepTurnSamples = 16000 * 17 / 2
    /// The value of `clock` at the last near-miss report.
    private var nearMissClock = 0

    static let rate = 16000
    private var frameSamples: Int { Int(Double(Self.rate) * config.detector.frameMs / 1000) }
    private static let keepLevelFrames = 150
    /// The audio kept from before a turn: the phrase of a wake turn starts up to about 2.5 s back.
    private static let keepSamples = 16000 * 3

    public init(listener: WakeListener, config: WakeConfig = WakeConfig(), source: SampleSource = MicrophoneSamples()) {
        self.listener = listener
        self.config = config
        self.source = source
        detector = SpeechDetector(config: config.detector)
        // Each pause asks the listener. A listener with no turn model answers nil, and the end silence counts.
        detector.pauseChecks = true
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

    /// The result of the last voice check, or nil if no check ran (no voice is enrolled, or the follow-up turn was
    /// too short). Use it on `queue` or after the turn ended.
    public private(set) var lastTurnVoice: TurnVoice?

    /// Feeds samples. It runs on `queue`.
    func feed(_ samples: [Float]) {
        guard running, !paused, !samples.isEmpty else { return }
        clock += samples.count
        remember(samples)
        if inTurn {
            addTurnSamples(samples)
            keepTurnAudio(samples)
        }

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
            if let event = pauseCheck() { events.append(event) }
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
            startTurnSamples(Array(recentSamples.suffix(Self.rate / 4)), wake: nil)
            turnAudio = turnSamples
            deliver(.start)
        case (.wakeTurn, .end):
            let (samples, count, wake) = (turnSamples, turnSampleCount, turnWake)
            finishTurn()
            deliver(verdict(.wake, samples, audioSamples: count, phrase: wake), voice: lastTurnVoice)
        case (.wakeTurn, .drop):
            finishTurn()
            deliver(event)
        case (.followTurn, .end):
            let (samples, count) = (turnSamples, turnSampleCount)
            finishTurn()
            deliver(followUpVerdict(samples, audioSamples: count), voice: lastTurnVoice)
        case (.followTurn, .drop):
            finishTurn()
            deliver(event)
        default:
            break
        }
    }

    /// The voice check at the end of a follow-up turn. A turn that is too short has no check: it is dropped.
    private func followUpVerdict(_ samples: [Float], audioSamples: Int) -> SpeechEvent {
        let seconds = Double(audioSamples) / Double(Self.rate)
        guard seconds >= config.minimumFollowUpSeconds else {
            lastTurnVoice = nil
            return .drop(String(format: "\(Self.tooShort) (%.2f s)", seconds))
        }
        return verdict(.followUp, samples, audioSamples: audioSamples, phrase: nil)
    }

    /// The voice check at the end of a turn (E6): the voice of the whole turn, with the limit for its speech length.
    /// It sets `lastTurnVoice`. If the check does not run (no voice is enrolled, or the model failed), a wake turn
    /// keeps the score of its phrase, with the short limit. With no score at all, the turn goes on unchecked: an
    /// always-on "send" then stays blocked (D-12).
    private func verdict(_ kind: TurnVoice.Kind, _ samples: [Float], audioSamples: Int, phrase: WakeHit?) -> SpeechEvent {
        let rule = config.voice
        let audio = Double(audioSamples) / Double(Self.rate)
        let start = DispatchTime.now().uptimeNanoseconds
        let check = samples.isEmpty ? nil : listener.voiceCheck(samples)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        if let check {
            let limit = rule.limit(seconds: check.seconds)
            lastTurnVoice = TurnVoice(kind: kind, score: check.score, seconds: check.seconds, audioSeconds: audio,
                                      limit: limit, passed: check.score >= limit, ms: ms)
        } else if let score = phrase?.voiceScore {
            lastTurnVoice = TurnVoice(kind: kind, score: score, seconds: 0, audioSeconds: audio, limit: rule.short,
                                      passed: score >= rule.short, byTurn: false, ms: ms)
        } else {
            lastTurnVoice = nil
            return .end
        }
        guard let voice = lastTurnVoice, !voice.passed else { return .end }
        return .drop(String(format: "\(Self.otherVoice) (%.2f)", voice.score))
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
        // The voice check and the turn model hear the turn from the start of the phrase. The spotter fires after
        // the phrase ended. The audio before the phrase is not part of the turn.
        let back = min(recentSamples.count, Int(hit.prerollSeconds * Double(Self.rate)))
        startTurnSamples(Array(recentSamples.suffix(back)), wake: hit)
        turnAudio = turnSamples
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onWake?(hit)
            self.onStart?()
        }
    }

    /// The owner said the phrase again at the start of a follow-up turn (D-11). The turn becomes a wake turn, so the
    /// pipeline removes the phrase by its time. The voice of the whole turn is checked at the end, as for a wake turn.
    /// If the voice of the phrase does not reach the gate, the turn stays a follow-up turn.
    private func wakeInFollowTurn(_ hit: WakeHit) {
        guard hit.isOwner else { return }
        var hit = hit
        hit.inTurnAfterSeconds = Double(clock - turnStartClock) / Double(Self.rate)
        openAfterPhrase(hit)
        state = .wakeTurn
        // The samples of the turn stay: they hold the phrase.
        turnWake = hit
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
        clearTurnSamples()
        turnAudio.removeAll()
        listener.reset()
    }

    private func startTurnSamples(_ samples: [Float], wake: WakeHit?) {
        lastTurnVoice = nil
        turnSamples = samples
        turnSampleCount = samples.count
        turnWake = wake
    }

    private func addTurnSamples(_ samples: [Float]) {
        turnSampleCount += samples.count
        let room = Int(config.voiceCheckMaxSeconds * Double(Self.rate)) - turnSamples.count
        if room > 0 { turnSamples.append(contentsOf: samples.prefix(room)) }
    }

    private func clearTurnSamples() {
        turnSamples.removeAll()
        turnSampleCount = 0
        turnWake = nil
    }

    /// Ends an open turn from the outside. Returns `.drop` if a turn was open.
    private func endTurn() -> SpeechEvent? {
        let open = inTurn
        _ = detector.reset()
        detector.endSilenceOverrideMs = nil
        detector.dictationTurn = false
        nextTurnLongPause = false
        state = .idle
        clearTurnSamples()
        turnAudio.removeAll()
        pending.removeAll()
        listener.reset()
        return open ? .drop("input stopped") : nil
    }

    /// Asks the turn model at the first pause of the turn (R-ON-1, I-2). A high probability ends the turn now. A low
    /// one keeps the turn open up to the wait time, so a pause in a sentence does not cut it. With no model, nothing
    /// changes. The idea comes from Hex's Smart Turn experiment (anomalyco/hex f748282, MIT).
    private func pauseCheck() -> SpeechEvent? {
        guard inTurn, detector.takePauseCheck() else { return nil }
        let start = DispatchTime.now().uptimeNanoseconds
        let probability = listener.turnScore(turnAudio)
        let runMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        guard let probability else { return nil }
        let dictation = detector.dictationTurn
        let silenceMs = detector.pauseMs
        let done = probability >= config.turnThreshold
        var event: SpeechEvent?
        if done {
            event = detector.endTurnNow()
        } else {
            detector.answerPauseCheck(waitMs: dictation ? config.dictationTurnWaitMs : config.turnWaitMs)
        }
        let check = TurnCheck(probability: probability, silenceMs: silenceMs, decision: done ? .end : .wait,
                              runMs: runMs, dictation: dictation)
        DispatchQueue.main.async { [weak self] in self?.onTurnCheck?(check) }
        return event
    }

    private func keepTurnAudio(_ samples: [Float]) {
        turnAudio.append(contentsOf: samples)
        if turnAudio.count > Self.keepTurnSamples + Self.rate {
            turnAudio.removeFirst(turnAudio.count - Self.keepTurnSamples)
        }
    }

    private func remember(_ samples: [Float]) {
        recentSamples.append(contentsOf: samples)
        if recentSamples.count > Self.keepSamples * 2 { recentSamples.removeFirst(recentSamples.count - Self.keepSamples) }
    }

    /// Calls the callback of the event on the main thread. `voice` comes first, in the same block, so that the app
    /// has the voice check of the turn when the turn ends.
    private func deliver(_ event: SpeechEvent, voice: TurnVoice? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let voice { self.onTurnVoice?(voice) }
            switch event {
            case .start: self.onStart?()
            case .end: self.onStop?()
            case .drop(let why): if let c = self.onCancel { c(why) } else { self.onStop?() }
            }
        }
    }
}
