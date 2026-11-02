import AVFoundation
import CTranscribe
import EarshotCore
import Foundation

/// Parakeet speech to text through transcribe.cpp (MIT), on the Mac with Metal (R-MD-1, E2).
/// It reads the model file in place (for example the GGUF file of Hex) and keeps it loaded:
/// the load takes about 14 s and about 890 MB (E2, section 5.4).
/// The model weights are CC BY 4.0 (NVIDIA Parakeet). Credit them in the app's About text.
public final class ParakeetEngine: SpeechEngine, @unchecked Sendable {
    public static let engineID = "parakeet"
    public let id = ParakeetEngine.engineID
    public let modelPath: String
    public var onPartial: (@Sendable (String) -> Void)?
    var partials = PartialSchedule()

    /// All model runs go through this queue, because one transcribe.cpp session is not thread safe.
    private let queue = DispatchQueue(label: "earshot.speech.parakeet", qos: .userInitiated)
    private var session: OpaquePointer?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var lastPartialFrames = 0
    private var listening = false
    private var timer: DispatchSourceTimer?
    private let mic: MicrophoneFeed
    private let useMicrophone: Bool

    /// The time of the last load, in ms. For the log and the management window.
    public private(set) var loadMs: Double = 0

    /// - Parameter useMicrophone: false for tests that give audio with `transcribe(samples:)`.
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
        let warm = [Float](repeating: 0, count: 16000)
        _ = warm.withUnsafeBufferPointer { transcribe_run(s, $0.baseAddress, Int32($0.count), nil) }
        loadMs = SpeechClock.ms(since: t0)
    }

    public func begin() throws {
        guard useMicrophone else { throw SpeechError("this Parakeet engine has no microphone") }
        guard mic.isRunning else { throw SpeechError("Parakeet is not ready: call prepare() first") }
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lastPartialFrames = 0
        listening = true
        lock.unlock()
        mic.begin { [weak self] buffer in self?.append(AudioUtil.floats(buffer)) }
        startTimer()
    }

    public func end() async throws -> Utterance {
        let t0 = SpeechClock.nowNs()
        mic.end()                      // adds the tail silence
        stopTimer()
        lock.lock()
        let pcm = samples
        samples.removeAll()
        listening = false
        lock.unlock()
        let text = try await run(pcm)
        return Utterance(text: text, engine: id, ms: SpeechClock.ms(since: t0))
    }

    /// Transcribes samples (16 kHz mono float) with the loaded model. Adds the tail silence.
    /// For the Test tab and for measurements.
    public func transcribe(samples pcm: [Float]) async throws -> Utterance {
        let t0 = SpeechClock.nowNs()
        let text = try await run(pcm + [Float](repeating: 0, count: TailPad.frames(sampleRate: 16000)))
        return Utterance(text: text, engine: id, ms: SpeechClock.ms(since: t0))
    }

    /// Transcribes an audio file of any format that AVAudioFile reads.
    public func transcribe(file: URL) async throws -> Utterance {
        try await transcribe(samples: AudioUtil.readSamples16k(file))
    }

    /// Stops the microphone. The model stays loaded until the engine is released.
    public func shutdown() { stopTimer(); mic.stop() }

    // MARK: - Private

    private func append(_ floats: [Float]) {
        lock.lock(); defer { lock.unlock() }
        if listening { samples.append(contentsOf: floats) }
    }

    private func run(_ pcm: [Float]) async throws -> String {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
            queue.async { [self] in
                do { c.resume(returning: try runNow(pcm)) } catch { c.resume(throwing: error) }
            }
        }
    }

    /// Runs on `queue`.
    private func runNow(_ pcm: [Float]) throws -> String {
        guard let session else { throw SpeechError("Parakeet is not loaded: call prepare() first") }
        if pcm.isEmpty { return "" }
        let status = pcm.withUnsafeBufferPointer { transcribe_run(session, $0.baseAddress, Int32($0.count), nil) }
        guard status == TRANSCRIBE_OK else { throw SpeechError("Parakeet run failed: \(Self.statusText(status))") }
        guard let c = transcribe_full_text(session) else { return "" }
        return TextClean.clean(String(cString: c))
    }

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(200))
        t.setEventHandler { [weak self] in self?.partialTick() }
        lock.lock(); timer = t; lock.unlock()
        t.resume()
    }

    private func stopTimer() {
        lock.lock(); let t = timer; timer = nil; lock.unlock()
        t?.cancel()
    }

    /// Runs on `queue`. Makes a partial text when enough new audio came in.
    private func partialTick() {
        lock.lock()
        guard listening, onPartial != nil,
              partials.due(totalFrames: samples.count, lastFrames: lastPartialFrames, sampleRate: 16000) else {
            lock.unlock(); return
        }
        let pcm = samples
        lastPartialFrames = pcm.count
        let callback = onPartial
        lock.unlock()
        if let text = try? runNow(pcm), !text.isEmpty {
            lock.lock(); let still = listening; lock.unlock()
            if still { callback?(text) }
        }
    }

    static func statusText(_ s: transcribe_status) -> String {
        String(cString: transcribe_status_string(Int32(truncatingIfNeeded: s.rawValue)))
    }
}
