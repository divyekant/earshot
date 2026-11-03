import AVFoundation
import CoreMedia
import EarshotCore
import Foundation
import Speech

#if compiler(>=6.2)   // Swift 6.2 comes with the macOS 26 SDK, which has SpeechTranscriber.

/// Apple SpeechTranscriber, on the Mac (R-MD-1, E0). It needs no model file from the owner:
/// macOS downloads the speech model for the locale one time.
/// It needs macOS 26. On older macOS, and if it does not load, `AppleSpeech.make` uses DictationEngine.
@available(macOS 26, *)
public final class AppleSpeechEngine: TurnSpeechEngine, PrerollControl, CaptureControl, PhraseHintControl, @unchecked Sendable {
    public static let engineID = AppleSpeech.engineID
    public let id = AppleSpeechEngine.engineID
    public let locale: Locale
    public var onPartial: (@Sendable (String) -> Void)?
    public var reason = ""
    public var lastTiming: SpeechTiming? { lock.withLock { timing } }

    private static let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
    private let lock = NSLock()
    private var mic: MicrophoneFeed?
    private var resolvedLocale: Locale?
    private var setup: Task<(SpeechAnalyzer, Task<TimedTranscript, Error>), Error>?
    private var finish: (() -> Void)?
    private var sink: ((AVAudioPCMBuffer) -> Void)?
    private var format: AVAudioFormat?
    private var frames: Int64 = 0
    private var timing: SpeechTiming?
    /// The preroll of the current turn, in seconds. The word times count from the start of the turn.
    private var turnPreroll: Double = 0
    /// Words to expect, such as the wake phrase (D-11). They go to the analyzer as context.
    private var hints: [String] = []
    let activity = TurnActivity()

    public init(locale: Locale = Locale(identifier: "en_US")) { self.locale = locale }

    deinit { mic?.stop() }

    private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        // The audio time of each word lets the pipeline remove the wake phrase by time (D-11).
        SpeechTranscriber(locale: locale, transcriptionOptions: [],
                          reportingOptions: [.volatileResults, .fastResults], attributeOptions: [.audioTimeRange])
    }

    /// Checks the locale, downloads the speech model if it is missing, loads it, and opens the microphone.
    public func prepare() async throws {
        let format = try await prepareModel()
        let feed = MicrophoneFeed(format: format)
        try feed.start()
        lock.withLock { mic = feed }
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
        lock.withLock { resolvedLocale = loc; self.format = format }
        return format
    }

    public func setNextPreroll(seconds: Double) { lock.withLock { mic }?.setNextPreroll(seconds: seconds) }
    public func setNextCapture(seconds: Double) { lock.withLock { mic }?.setNextCapture(seconds: seconds) }

    public func setPhraseHints(_ phrases: [String]) { lock.withLock { hints = phrases.filter { !$0.isEmpty } } }

    /// Key down: audio goes to the analyzer at once. The analyzer starts in parallel.
    public func begin() throws {
        guard let mic = lock.withLock({ self.mic }) else {
            throw SpeechError("Apple speech is not ready: call prepare() first")
        }
        let preroll = mic.begin(try startTurn())
        lock.withLock { turnPreroll = preroll }
    }

    /// Starts a turn with no microphone, for measurements. Give the audio (in the model format) to the returned function.
    func beginWithoutMicrophone() throws -> (AVAudioPCMBuffer) -> Void { try startTurn() }

    /// The audio format of the model, after `prepareModel`.
    var modelFormat: AVAudioFormat? { lock.withLock { format } }

    private func startTurn() throws -> (AVAudioPCMBuffer) -> Void {
        guard let loc = lock.withLock({ resolvedLocale }) else {
            throw SpeechError("Apple speech is not ready: call prepare() first")
        }
        activity.begin("earshot speech command")
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let task = Self.startAnalyzer(locale: loc, input: stream, hints: lock.withLock { hints }, onPartial: onPartial)
        let feed: (AVAudioPCMBuffer) -> Void = { [weak self] buffer in
            self?.lock.withLock { self?.frames += Int64(buffer.frameLength) }
            continuation.yield(AnalyzerInput(buffer: buffer))
        }
        lock.withLock {
            setup = task
            sink = feed
            frames = 0
            turnPreroll = 0
            finish = { continuation.finish() }   // `end` closes the stream.
        }
        return feed
    }

    /// Key up: closes the audio (with the tail silence), finalizes, and returns the text.
    public func end() async throws -> Utterance {
        let t0 = SpeechClock.nowNs()
        let (mic, task, close, feed, format) = lock.withLock {
            let out = (self.mic, setup, finish, sink, self.format)
            setup = nil; finish = nil; sink = nil
            return out
        }
        if let mic {
            await mic.end(captureSeconds: TailPad.captureSeconds)   // then adds the tail silence through the sink
        } else if let feed, let format, let pad = AudioUtil.silence(format: format, frames: TailPad.frames(sampleRate: format.sampleRate)) {
            feed(pad)
        }
        close?()
        defer { activity.end() }
        guard let task else { return Utterance(text: "", engine: id, ms: 0) }
        var t = SpeechTiming(engine: id, why: reason)
        t.tailMs = SpeechClock.ms(since: t0)
        let tWait = SpeechClock.nowNs()
        let (analyzer, collector) = try await task.value
        t.waitMs = SpeechClock.ms(since: tWait)
        let tDecode = SpeechClock.nowNs()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let joined = try await collector.value
        let text = TextClean.clean(joined.text)
        t.decodeMs = SpeechClock.ms(since: tDecode)
        t.totalMs = SpeechClock.ms(since: t0)
        let preroll = lock.withLock {
            if let format { t.audioMs = Double(frames) / format.sampleRate * 1000 }
            timing = t
            return turnPreroll
        }
        // The analyzer counts time from the first audio, which is the preroll. The pipeline counts from the start.
        var words: [TimedWord] = []
        if TimedTranscript.plausible(joined.words, audioSeconds: t.audioMs / 1000) {
            words = joined.words.map { TimedWord(text: $0.text, start: $0.start - preroll, end: $0.end - preroll) }
        }
        return Utterance(text: text, engine: id, ms: t.totalMs, words: words)
    }

    /// Drops the turn with no final text.
    public func cancelTurn() {
        let (mic, task, close) = lock.withLock {
            let out = (self.mic, setup, finish)
            setup = nil; finish = nil; sink = nil
            return out
        }
        mic?.end()
        close?()
        activity.end()
        guard let task else { return }
        Task {
            guard let (analyzer, collector) = try? await task.value else { return }
            await analyzer.cancelAndFinishNow()
            collector.cancel()
        }
    }

    /// Transcribes an audio file. For the Test tab and for measurements. `ms` is the full run time.
    public func transcribe(file: URL) async throws -> Utterance {
        let known = lock.withLock { resolvedLocale }
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
        let joined = try await collector.value
        return Utterance(text: TextClean.clean(joined.text), engine: id, ms: SpeechClock.ms(since: t0), words: joined.words)
    }

    public func shutdown() { lock.withLock { mic }?.stop() }

    private static func startAnalyzer(locale: Locale, input: AsyncStream<AnalyzerInput>, hints: [String],
                                      onPartial: (@Sendable (String) -> Void)?) -> Task<(SpeechAnalyzer, Task<TimedTranscript, Error>), Error> {
        Task {
            let module = makeTranscriber(locale)
            let analyzer = SpeechAnalyzer(modules: [module], options: options)
            let collector = collect(module, onPartial: onPartial)
            if !hints.isEmpty {
                // The wake phrase as context, so that the model spells it right more often (D-11). The probe used
                // the same call for names (E2). If the context does not apply, the turn goes on without it.
                let context = AnalysisContext()
                context.contextualStrings = [.general: hints]
                try? await analyzer.setContext(context)
            }
            try await analyzer.start(inputSequence: input)
            return (analyzer, collector)
        }
    }

    private static func collect(_ module: SpeechTranscriber,
                                onPartial: (@Sendable (String) -> Void)?) -> Task<TimedTranscript, Error> {
        Task {
            var join = TimedTranscript()
            for try await r in module.results {
                let so = join.add(String(r.text.characters), words: pieces(r.text), isFinal: r.isFinal)
                if !r.isFinal { onPartial?(TextClean.clean(so)) }
            }
            return join
        }
    }

    /// The runs of a result with their audio times, in seconds from the first audio of the turn.
    /// A run with no time (for example a space) joins the piece before it, so the pieces joined give the text.
    static func pieces(_ text: AttributedString) -> [TimedWord] {
        var out: [TimedWord] = []
        var lead = ""
        for run in text.runs {
            let piece = String(text[run.range].characters)
            if let range = run.audioTimeRange, range.start.isNumeric, range.duration.isNumeric {
                out.append(TimedWord(text: lead + piece, start: range.start.seconds, end: range.end.seconds))
                lead = ""
            } else if out.isEmpty {
                lead += piece
            } else {
                out[out.count - 1].text += piece
            }
        }
        if !lead.isEmpty, !out.isEmpty { out[out.count - 1].text += lead }
        return out
    }
}

#endif
