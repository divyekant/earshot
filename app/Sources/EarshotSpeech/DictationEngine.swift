import AVFoundation
import EarshotCore
import Foundation
import Speech

/// Apple on-device dictation (SFSpeechRecognizer), on the Mac (R-MD-1).
/// It runs on macOS 14 and later, on Intel Macs too. SpeechTranscriber needs macOS 26 and is reported to need
/// Apple silicon, so this engine is the Apple engine on other Macs.
/// It always sets `requiresOnDeviceRecognition`. If this Mac cannot recognize the locale on the device,
/// `prepare` throws. The engine never sends audio to a server.
public final class DictationEngine: TurnSpeechEngine, PrerollControl, CaptureControl, PhraseHintControl, MicIdleControl,
                                    @unchecked Sendable {
    public static let engineID = "apple-dictation"
    public let id = DictationEngine.engineID
    public let locale: Locale
    public var onPartial: (@Sendable (String) -> Void)?
    public var reason = ""
    public var lastTiming: SpeechTiming? { lock.withLock { timing } }

    /// The longest wait for the final text after the audio ends. After it, the last partial text wins.
    var finalWaitSeconds = 3.0

    private let lock = NSLock()
    private var recognizer: SFSpeechRecognizer?
    private var mic: MicrophoneFeed?
    private var turn: DictationTurn?
    private var frames: Int64 = 0
    private var timing: SpeechTiming?
    /// Words to expect, such as the wake phrase (D-11). They go to each request as contextual strings.
    private var hints: [String] = []
    /// The idle time of the microphone (`MicIdleControl`). The feed gets it when `prepare` makes the feed.
    private var idleClose: Double?
    private let format = AudioUtil.parakeetFormat
    let activity = TurnActivity()

    public init(locale: Locale = Locale(identifier: "en_US")) { self.locale = locale }

    deinit { mic?.stop() }

    /// Checks the permission and the on-device support of the locale, then opens the microphone.
    public func prepare() async throws {
        try await prepareRecognizer()
        let feed = MicrophoneFeed(format: format)
        feed.setIdleClose(seconds: lock.withLock { idleClose })
        try feed.start()
        lock.withLock { mic = feed }
    }

    /// Everything except the microphone.
    func prepareRecognizer() async throws {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
            }
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw SpeechError("the Speech Recognition permission is off")
        }
        guard let r = SFSpeechRecognizer(locale: locale) else {
            throw SpeechError("Apple dictation does not support the locale \(locale.identifier)")
        }
        guard r.supportsOnDeviceRecognition else {
            throw SpeechError("this Mac cannot recognize \(locale.identifier) on the device; earshot sends no audio to a server")
        }
        lock.withLock { recognizer = r }
    }

    public func setNextPreroll(seconds: Double) { lock.withLock { mic }?.setNextPreroll(seconds: seconds) }
    public func setNextCapture(seconds: Double) { lock.withLock { mic }?.setNextCapture(seconds: seconds) }
    public func setMicIdleClose(seconds: Double?) {
        lock.withLock { () -> MicrophoneFeed? in idleClose = seconds; return mic }?.setIdleClose(seconds: seconds)
    }

    public func setPhraseHints(_ phrases: [String]) { lock.withLock { hints = phrases.filter { !$0.isEmpty } } }

    public func begin() throws {
        guard let mic = lock.withLock({ self.mic }) else {
            throw SpeechError("Apple dictation is not ready: call prepare() first")
        }
        try mic.begin(try startTurn())
    }

    /// Starts a turn with no microphone, for measurements. Give 16 kHz mono float audio to the returned function.
    func beginWithoutMicrophone() throws -> (AVAudioPCMBuffer) -> Void { try startTurn() }

    private func startTurn() throws -> (AVAudioPCMBuffer) -> Void {
        guard let recognizer = lock.withLock({ self.recognizer }) else {
            throw SpeechError("Apple dictation is not ready: call prepare() first")
        }
        activity.begin("earshot speech command")
        let request = Self.request(SFSpeechAudioBufferRecognitionRequest())
        request.shouldReportPartialResults = onPartial != nil
        request.contextualStrings = lock.withLock { hints }
        let t = DictationTurn(request: request)
        let partial = onPartial
        t.task = recognizer.recognitionTask(with: request) { result, error in
            t.update(result: result, error: error, onPartial: partial)
        }
        lock.withLock { turn = t; frames = 0 }
        return { [weak self] buffer in
            self?.lock.withLock { self?.frames += Int64(buffer.frameLength) }
            request.append(buffer)
        }
    }

    /// Key up: closes the audio (with the tail silence), waits for the final text, and returns it.
    public func end() async throws -> Utterance {
        let t0 = SpeechClock.nowNs()
        let (mic, current) = lock.withLock { () -> (MicrophoneFeed?, DictationTurn?) in
            defer { turn = nil }
            return (self.mic, turn)
        }
        defer { activity.end() }
        guard let current else { return Utterance(text: "", engine: id, ms: 0) }
        if let mic {
            await mic.end(captureSeconds: TailPad.captureSeconds)   // then adds the tail silence through the sink
        } else if let pad = AudioUtil.silence(format: format, frames: TailPad.frames(sampleRate: format.sampleRate)) {
            current.request.append(pad)
        }
        var t = SpeechTiming(engine: id, why: reason)
        t.tailMs = SpeechClock.ms(since: t0)
        let tDecode = SpeechClock.nowNs()
        current.request.endAudio()
        let text = try await current.wait(seconds: finalWaitSeconds)
        t.decodeMs = SpeechClock.ms(since: tDecode)
        t.totalMs = SpeechClock.ms(since: t0)
        lock.withLock {
            t.audioMs = Double(frames) / format.sampleRate * 1000
            timing = t
        }
        return Utterance(text: TextClean.clean(text), engine: id, ms: t.totalMs)
    }

    /// Drops the turn with no final text.
    public func cancelTurn() {
        let (mic, current) = lock.withLock { () -> (MicrophoneFeed?, DictationTurn?) in
            defer { turn = nil }
            return (self.mic, turn)
        }
        mic?.end()
        current?.task?.cancel()
        activity.end()
    }

    /// Transcribes an audio file. For the Test tab and for measurements. `ms` is the full run time.
    public func transcribe(file: URL) async throws -> Utterance {
        if lock.withLock({ recognizer }) == nil { try await prepareRecognizer() }
        guard let recognizer = lock.withLock({ self.recognizer }) else { throw SpeechError("Apple dictation is not ready") }
        let request = Self.request(SFSpeechURLRecognitionRequest(url: file))
        request.shouldReportPartialResults = false
        let t = DictationTurn(request: nil)
        let t0 = SpeechClock.nowNs()
        t.task = recognizer.recognitionTask(with: request) { result, error in t.update(result: result, error: error, onPartial: nil) }
        let text = try await t.wait(seconds: 30)
        return Utterance(text: TextClean.clean(text), engine: id, ms: SpeechClock.ms(since: t0))
    }

    public func shutdown() { lock.withLock { mic }?.stop() }

    /// The settings of every request: on the device only, with punctuation, as a short command.
    private static func request<R: SFSpeechRecognitionRequest>(_ r: R) -> R {
        r.requiresOnDeviceRecognition = true
        r.taskHint = .dictation
        r.addsPunctuation = true
        return r
    }
}

/// The state of one dictation turn. The recognizer calls `update` on its own queue.
final class DictationTurn: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest!
    var task: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var text = ""
    private var done = false
    private var failure: Error?
    private var waiter: CheckedContinuation<String, Error>?

    init(request: SFSpeechAudioBufferRecognitionRequest?) { self.request = request }

    func update(result: SFSpeechRecognitionResult?, error: Error?, onPartial: (@Sendable (String) -> Void)?) {
        if let result {
            let s = result.bestTranscription.formattedString
            lock.withLock { text = s }
            if result.isFinal { finish(nil) } else { onPartial?(TextClean.clean(s)) }
        }
        if let error { finish(error) }
    }

    /// Returns the final text, or the last partial text after `seconds`.
    func wait(seconds: Double) async throws -> String {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
            self?.finish(nil)
        }
        return try await withCheckedThrowingContinuation { c in
            let ready: Result<String, Error>? = lock.withLock {
                if done { return Self.outcome(text, failure) }
                waiter = c
                return nil
            }
            if let ready { c.resume(with: ready) }
        }
    }

    private func finish(_ error: Error?) {
        let (c, out) = lock.withLock { () -> (CheckedContinuation<String, Error>?, Result<String, Error>) in
            if !done { done = true; failure = error }
            defer { waiter = nil }
            return (waiter, Self.outcome(text, failure))
        }
        c?.resume(with: out)
    }

    /// Text wins over an error. "No speech detected" with no text is an empty command, not an error.
    static func outcome(_ text: String, _ error: Error?) -> Result<String, Error> {
        if !text.isEmpty || error == nil { return .success(text) }
        let ns = error! as NSError
        if ns.domain == "kAFAssistantErrorDomain", [203, 1110].contains(ns.code) { return .success("") }
        // macOS gives "Siri and Dictation are disabled" when Dictation is off. On-device dictation needs it on.
        let hint = ns.localizedDescription.localizedCaseInsensitiveContains("dictation")
            ? ". Turn on Dictation in System Settings > Keyboard, then restart earshot" : ""
        return .failure(SpeechError("Apple dictation failed: \(ns.localizedDescription)\(hint)"))
    }
}
