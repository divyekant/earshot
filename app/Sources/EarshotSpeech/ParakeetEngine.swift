import AVFoundation
import CTranscribe
import EarshotCore
import Foundation

/// Parakeet speech to text through transcribe.cpp (MIT), on the Mac with Metal (R-MD-1, E2).
/// It reads the model file in place (for example the GGUF file of Hex) and keeps it loaded:
/// the load takes about 14 s and about 890 MB (E2, section 5.4).
/// The model weights are CC BY 4.0 (NVIDIA Parakeet). Credit them in the app's About text.
public final class ParakeetEngine: SpeechEngine, SpeechTimingReporting, @unchecked Sendable {
    public static let engineID = "parakeet"
    public let id = ParakeetEngine.engineID
    public let modelPath: String
    public var onPartial: (@Sendable (String) -> Void)?
    public var reason = ""
    var partials = PartialSchedule()

    /// At the key press, if the model was idle for this time or more, the engine starts a short warm-up run.
    /// The warm-up runs while the owner speaks, so that the final run does not pay for an idle GPU.
    /// Nil turns the warm-up off.
    public var warmAfterIdleSeconds: Double? = 2.0
    /// The length of the warm-up audio (silence).
    var warmSeconds = 0.5

    /// All model runs go through this queue, because one transcribe.cpp session is not thread safe.
    private let queue = DispatchQueue(label: "earshot.speech.parakeet", qos: .userInitiated)
    private var session: OpaquePointer?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var lastPartialFrames = 0
    private var listening = false
    private var timer: DispatchSourceTimer?
    private var lastRunEndNs: UInt64 = 0
    private var turn = SpeechTiming(engine: ParakeetEngine.engineID, why: "")
    private var timing: SpeechTiming?
    private let mic: MicrophoneFeed
    private let useMicrophone: Bool

    /// The time of the last load, in ms. For the log and the management window.
    public private(set) var loadMs: Double = 0

    public var lastTiming: SpeechTiming? { lock.withLock { timing } }

    /// - Parameter useMicrophone: false for tests that give audio with `transcribe(samples:)` or `feed`.
    public init(modelPath: String, useMicrophone: Bool = true) {
        self.modelPath = modelPath
        self.useMicrophone = useMicrophone
        mic = MicrophoneFeed(format: AudioUtil.parakeetFormat)
    }

    deinit {
        mic.stop()
        if let session { transcribe_session_free(session) }
    }

    public func prepare() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do { try loadIfNeeded(); c.resume() } catch { c.resume(throwing: error) }
            }
        }
        if useMicrophone { try mic.start() }
    }

    /// Runs on `queue`.
    private func loadIfNeeded() throws {
        if session != nil { return }
        guard FileManager.default.isReadableFile(atPath: modelPath) else {
            throw SpeechError("Parakeet model file not found: \(modelPath)")
        }
        transcribe_log_set(nil, nil)
        let t0 = SpeechClock.nowNs()
        var opened: OpaquePointer?
        let status = transcribe_open(modelPath, nil, nil, &opened)
        guard status == TRANSCRIBE_OK, let s = opened else {
            throw SpeechError("transcribe.cpp could not load \(modelPath): \(Self.statusText(status))")
        }
        session = s
        // The first run prepares the GPU code. Do it now, not on the first command.
        warmNow(seconds: 1.0)
        loadMs = SpeechClock.ms(since: t0)
    }

    public func begin() throws {
        guard useMicrophone else { throw SpeechError("this Parakeet engine has no microphone") }
        guard mic.isRunning else { throw SpeechError("Parakeet is not ready: call prepare() first") }
        startTurn()
        mic.begin { [weak self] buffer in self?.feed(AudioUtil.floats(buffer)) }
    }

    /// Starts a turn with no microphone. The caller gives the audio with `feed`. For measurements.
    func beginWithoutMicrophone() { startTurn() }

    /// Adds audio (16 kHz mono float) to the turn.
    func feed(_ floats: [Float]) {
        lock.withLock { if listening { samples.append(contentsOf: floats) } }
    }

    public func end() async throws -> Utterance {
        let t0 = SpeechClock.nowNs()
        if useMicrophone {
            mic.end()   // adds the tail silence through `feed`
        } else {
            feed([Float](repeating: 0, count: TailPad.frames(sampleRate: 16000)))
        }
        stopTimer()
        let (pcm, started) = lock.withLock { () -> ([Float], SpeechTiming) in
            let out = samples
            samples.removeAll()
            listening = false
            return (out, turn)
        }
        var t = started
        t.why = reason
        t.audioMs = Double(pcm.count) / 16.0
        t.tailMs = SpeechClock.ms(since: t0)
        let r = try await run(pcm)
        t.waitMs = r.waitMs
        t.decodeMs = r.decodeMs
        t.totalMs = SpeechClock.ms(since: t0)
        lock.withLock { timing = t }
        return Utterance(text: r.text, engine: id, ms: t.totalMs)
    }

    /// Transcribes samples (16 kHz mono float) with the loaded model. Adds the tail silence.
    /// For the Test tab and for measurements.
    public func transcribe(samples pcm: [Float]) async throws -> Utterance {
        let t0 = SpeechClock.nowNs()
        let r = try await run(pcm + [Float](repeating: 0, count: TailPad.frames(sampleRate: 16000)))
        return Utterance(text: r.text, engine: id, ms: SpeechClock.ms(since: t0))
    }

    /// Transcribes an audio file of any format that AVAudioFile reads.
    public func transcribe(file: URL) async throws -> Utterance {
        try await transcribe(samples: AudioUtil.readSamples16k(file))
    }

    /// Stops the microphone. The model stays loaded until the engine is released.
    public func shutdown() { stopTimer(); mic.stop() }

    // MARK: - Private

    private func startTurn() {
        let now = SpeechClock.nowNs()
        let warm: Bool = lock.withLock {
            samples.removeAll(keepingCapacity: true)
            lastPartialFrames = 0
            listening = true
            turn = SpeechTiming(engine: id, why: reason)
            turn.idleMs = lastRunEndNs == 0 ? 0 : Double(now &- lastRunEndNs) / 1_000_000
            if let limit = warmAfterIdleSeconds, turn.idleMs >= limit * 1000 { turn.warmed = true }
            return turn.warmed
        }
        if warm {
            let seconds = warmSeconds
            queue.async { [weak self] in self?.warmNow(seconds: seconds) }
        }
        if onPartial != nil { startTimer() }
    }

    /// Runs on `queue`. A run on silence, to wake the GPU and bring the model weights back into memory.
    private func warmNow(seconds: Double) {
        guard let session else { return }
        let pcm = [Float](repeating: 0, count: Int(16000 * seconds))
        _ = pcm.withUnsafeBufferPointer { transcribe_run(session, $0.baseAddress, Int32($0.count), nil) }
        lock.withLock { lastRunEndNs = SpeechClock.nowNs() }
    }

    private struct RunResult { let text: String; let waitMs: Double; let decodeMs: Double }

    private func run(_ pcm: [Float]) async throws -> RunResult {
        let queued = SpeechClock.nowNs()
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<RunResult, Error>) in
            queue.async { [self] in
                let wait = SpeechClock.ms(since: queued)
                let t0 = SpeechClock.nowNs()
                do {
                    let text = try runNow(pcm)
                    c.resume(returning: RunResult(text: text, waitMs: wait, decodeMs: SpeechClock.ms(since: t0)))
                } catch { c.resume(throwing: error) }
            }
        }
    }

    /// Runs on `queue`.
    private func runNow(_ pcm: [Float]) throws -> String {
        guard let session else { throw SpeechError("Parakeet is not loaded: call prepare() first") }
        if pcm.isEmpty { return "" }
        let status = pcm.withUnsafeBufferPointer { transcribe_run(session, $0.baseAddress, Int32($0.count), nil) }
        lock.withLock { lastRunEndNs = SpeechClock.nowNs() }
        guard status == TRANSCRIBE_OK else { throw SpeechError("Parakeet run failed: \(Self.statusText(status))") }
        guard let c = transcribe_full_text(session) else { return "" }
        return TextClean.clean(String(cString: c))
    }

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(200))
        t.setEventHandler { [weak self] in self?.partialTick() }
        lock.withLock { timer = t }
        t.resume()
    }

    private func stopTimer() {
        let t = lock.withLock { () -> DispatchSourceTimer? in defer { timer = nil }; return timer }
        t?.cancel()
    }

    /// Runs on `queue`. Makes a partial text when enough new audio came in.
    private func partialTick() {
        let due = lock.withLock { () -> ([Float], @Sendable (String) -> Void)? in
            guard listening, let callback = onPartial,
                  partials.due(totalFrames: samples.count, lastFrames: lastPartialFrames, sampleRate: 16000) else { return nil }
            lastPartialFrames = samples.count
            return (samples, callback)
        }
        guard let (pcm, callback) = due else { return }
        if let text = try? runNow(pcm), !text.isEmpty, lock.withLock({ listening }) {
            callback(text)
        }
    }

    static func statusText(_ s: transcribe_status) -> String {
        String(cString: transcribe_status_string(Int32(truncatingIfNeeded: s.rawValue)))
    }
}
