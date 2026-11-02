import AVFoundation
import EarshotCore
import Foundation
import Speech

/// Apple SpeechTranscriber, on the Mac (R-MD-1, E0). It needs no model file from the owner:
/// macOS downloads the speech model for the locale one time.
public final class AppleSpeechEngine: SpeechEngine, @unchecked Sendable {
    public static let engineID = "apple"
    public let id = AppleSpeechEngine.engineID
    public let locale: Locale
    public var onPartial: (@Sendable (String) -> Void)?

    private static let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
    private let lock = NSLock()
    private var mic: MicrophoneFeed?
    private var resolvedLocale: Locale?
    private var setup: Task<(SpeechAnalyzer, Task<String, Error>), Error>?
    private var finish: (() -> Void)?

    public init(locale: Locale = Locale(identifier: "en_US")) { self.locale = locale }

    deinit { mic?.stop() }

    private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [],
                          reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
    }

    /// Checks the locale, downloads the speech model if it is missing, loads it, and opens the microphone.
    public func prepare() async throws {
        let format = try await prepareModel()
        let feed = MicrophoneFeed(format: format)
        try feed.start()
        lock.lock(); mic = feed; lock.unlock()
    }

    /// Everything except the microphone. Returns the audio format of the model.
    @discardableResult
    func prepareModel() async throws -> AVAudioFormat {
        guard let loc = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechError("Apple speech does not support the locale \(locale.identifier)")
        }
        let module = Self.makeTranscriber(loc)
        // assetInstallationRequest returns a request even when the model is installed, so check first.
        if await AssetInventory.status(forModules: [module]) != .installed,
           let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw SpeechError("no audio format for the Apple speech model")
        }
        // Load the model now, so that the first command does not wait for it.
        let warm = SpeechAnalyzer(modules: [module], options: Self.options)
        try await warm.prepareToAnalyze(in: format)
        await warm.cancelAndFinishNow()
        lock.lock(); resolvedLocale = loc; lock.unlock()
        return format
    }

    /// Key down: audio goes to the analyzer at once. The analyzer starts in parallel.
    public func begin() throws {
        lock.lock()
        guard let mic, let loc = resolvedLocale else {
            lock.unlock()
            throw SpeechError("Apple speech is not ready: call prepare() first")
        }
        lock.unlock()
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        mic.begin { buffer in continuation.yield(AnalyzerInput(buffer: buffer)) }
        let task = Self.startAnalyzer(locale: loc, input: stream, onPartial: onPartial)
        lock.lock()
        setup = task
        finish = { continuation.finish() }   // `end` closes the stream.
        lock.unlock()
    }

    /// Key up: closes the audio (with the tail silence), finalizes, and returns the text.
    public func end() async throws -> Utterance {
        let t0 = SpeechClock.nowNs()
        lock.lock()
        let mic = self.mic, task = setup, close = finish
        setup = nil; finish = nil
        lock.unlock()
        mic?.end()
        close?()
        guard let task else { return Utterance(text: "", engine: id, ms: 0) }
        let (analyzer, collector) = try await task.value
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = TextClean.clean(try await collector.value)
        return Utterance(text: text, engine: id, ms: SpeechClock.ms(since: t0))
    }

    /// Transcribes an audio file. For the Test tab and for measurements. `ms` is the full run time.
    public func transcribe(file: URL) async throws -> Utterance {
        lock.lock(); let known = resolvedLocale; lock.unlock()
        let loc: Locale
        if let known { loc = known } else {
            guard let l = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
                throw SpeechError("Apple speech does not support the locale \(locale.identifier)")
            }
            loc = l
        }
        let audio = try AVAudioFile(forReading: file)
        let module = Self.makeTranscriber(loc)
        let analyzer = SpeechAnalyzer(modules: [module], options: Self.options)
        let collector = Self.collect(module, onPartial: nil)
        let t0 = SpeechClock.nowNs()
        if let last = try await analyzer.analyzeSequence(from: audio) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let text = TextClean.clean(try await collector.value)
        return Utterance(text: text, engine: id, ms: SpeechClock.ms(since: t0))
    }

    public func shutdown() { lock.lock(); let m = mic; lock.unlock(); m?.stop() }

    private static func startAnalyzer(locale: Locale, input: AsyncStream<AnalyzerInput>,
                                      onPartial: (@Sendable (String) -> Void)?) -> Task<(SpeechAnalyzer, Task<String, Error>), Error> {
        Task {
            let module = makeTranscriber(locale)
            let analyzer = SpeechAnalyzer(modules: [module], options: options)
            let collector = collect(module, onPartial: onPartial)
            try await analyzer.start(inputSequence: input)
            return (analyzer, collector)
        }
    }

    private static func collect(_ module: SpeechTranscriber, onPartial: (@Sendable (String) -> Void)?) -> Task<String, Error> {
        Task {
            var join = TranscriptJoin()
            for try await r in module.results {
                let so = join.add(String(r.text.characters), isFinal: r.isFinal)
                if !r.isFinal { onPartial?(TextClean.clean(so)) }
            }
            return join.text
        }
    }
}
