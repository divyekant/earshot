import AVFoundation
import Foundation
import Speech

/// Which on-device engine to use. Both run on the Mac (R-MD-1).
enum EngineKind: String {
    case transcriber   // SpeechTranscriber: the general model, with fast results
    case dictation     // DictationTranscriber: the dictation model, short-dictation preset
}

/// A transcriber module of either kind, plus the task that collects its final text.
struct SpeechModuleBox {
    let module: any SpeechModule
    let collect: () -> Task<String, Error>

    static func make(_ kind: EngineKind, locale: Locale, onVolatile: (@Sendable (String) -> Void)? = nil) -> SpeechModuleBox {
        switch kind {
        case .transcriber:
            let t = SpeechTranscriber(locale: locale,
                                      transcriptionOptions: [],
                                      reportingOptions: [.volatileResults, .fastResults],
                                      attributeOptions: [])
            return SpeechModuleBox(module: t) {
                Task {
                    var text = ""
                    for try await r in t.results {
                        let s = String(r.text.characters)
                        if r.isFinal { text += s } else { onVolatile?(text + s) }
                    }
                    return text
                }
            }
        case .dictation:
            let d = DictationTranscriber(locale: locale, preset: .shortDictation)
            return SpeechModuleBox(module: d) {
                Task {
                    var text = ""
                    for try await r in d.results where r.isFinal { text += String(r.text.characters) }
                    return text
                }
            }
        }
    }
}

enum SpeechSetup {
    static func locale(for kind: EngineKind, wanted: Locale) async -> Locale? {
        switch kind {
        case .transcriber: return await SpeechTranscriber.supportedLocale(equivalentTo: wanted)
        case .dictation: return await DictationTranscriber.supportedLocale(equivalentTo: wanted)
        }
    }

    static func status(_ kind: EngineKind, locale: Locale) async -> String {
        let box = SpeechModuleBox.make(kind, locale: locale)
        switch await AssetInventory.status(forModules: [box.module]) {
        case .installed: return "installed"
        case .supported: return "supported, not downloaded"
        case .downloading: return "downloading"
        case .unsupported: return "unsupported"
        @unknown default: return "unknown"
        }
    }

    /// Asks macOS to download the speech model for this locale, if it is missing.
    static func ensureAssets(_ kind: EngineKind, locale: Locale) async throws {
        let box = SpeechModuleBox.make(kind, locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [box.module]) {
            print("macOS is downloading the \(locale.identifier) speech model (one time)...")
            try await request.downloadAndInstall()
            print("Speech model installed.")
        }
    }

    /// Transcribes an audio file and returns the text and the time it took.
    static func transcribe(file path: String, kind: EngineKind, locale: Locale, hints: [String]) async throws -> (String, Double) {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let box = SpeechModuleBox.make(kind, locale: locale)
        let analyzer = SpeechAnalyzer(modules: [box.module])
        if !hints.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings = [.general: hints]
            try await analyzer.setContext(context)
        }
        let collector = box.collect()
        let t0 = Clock.nowNs()
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let text = try await collector.value
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), Clock.ms(since: t0))
    }
}

/// Receives microphone buffers on the audio thread, converts them to the
/// analyzer format, and passes them on while the talk key is down.
/// It keeps the last 250 ms before the key press, so the first word is not lost.
final class AudioFeed: @unchecked Sendable {
    private let lock = NSLock()
    private let outFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var preroll: [AVAudioPCMBuffer] = []
    private var prerollFrames: Int64 = 0
    private let prerollLimit: Int64

    init(outFormat: AVAudioFormat, prerollSeconds: Double = 0.25) {
        self.outFormat = outFormat
        prerollLimit = Int64(outFormat.sampleRate * prerollSeconds)
    }

    func attach(to engine: AVAudioEngine) {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [self] buffer, _ in
            self.push(buffer)
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == outFormat { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outFormat)
        }
        guard let converter else { return nil }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : out
    }

    private func push(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convert(buffer), converted.frameLength > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        if let continuation {
            continuation.yield(AnalyzerInput(buffer: converted))
        } else {
            preroll.append(converted)
            prerollFrames += Int64(converted.frameLength)
            while prerollFrames > prerollLimit, let first = preroll.first {
                prerollFrames -= Int64(first.frameLength)
                preroll.removeFirst()
            }
        }
    }

    func begin(_ c: AsyncStream<AnalyzerInput>.Continuation) {
        lock.lock()
        defer { lock.unlock() }
        for b in preroll { c.yield(AnalyzerInput(buffer: b)) }
        preroll.removeAll()
        prerollFrames = 0
        continuation = c
    }

    func end() {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.finish()
    }
}

/// Push-to-talk listener. The microphone runs while the probe runs.
/// Audio goes to the analyzer only while the talk key is down. No audio is saved.
@MainActor
final class Listener {
    let kind: EngineKind
    let locale: Locale
    var hints: [String] = []
    var onVolatile: (@Sendable (String) -> Void)?

    private let engine = AVAudioEngine()
    private var feed: AudioFeed?
    private var setup: Task<(SpeechAnalyzer, Task<String, Error>), Error>?

    init(kind: EngineKind, locale: Locale) {
        self.kind = kind
        self.locale = locale
    }

    func start() async throws {
        let probe = SpeechModuleBox.make(kind, locale: locale)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [probe.module]) else {
            throw ProbeError("no audio format for the speech model")
        }
        // Load the model now, so the first command does not wait for it.
        let warm = SpeechAnalyzer(modules: [probe.module], options: Self.options)
        try await warm.prepareToAnalyze(in: format)
        await warm.cancelAndFinishNow()

        let feed = AudioFeed(outFormat: format)
        feed.attach(to: engine)
        engine.prepare()
        try engine.start()
        self.feed = feed
    }

    static let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)

    /// Key down: start to pass audio at once; the analyzer starts in parallel.
    func begin() {
        guard let feed else { return }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        feed.begin(continuation)
        let kind = self.kind, locale = self.locale, hints = self.hints, onVolatile = self.onVolatile
        setup = Task {
            let box = SpeechModuleBox.make(kind, locale: locale, onVolatile: onVolatile)
            let analyzer = SpeechAnalyzer(modules: [box.module], options: Self.options)
            if !hints.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings = [.general: hints]
                try await analyzer.setContext(context)
            }
            let collector = box.collect()
            try await analyzer.start(inputSequence: stream)
            return (analyzer, collector)
        }
    }

    /// Key up: close the audio, finalize, and return the text.
    func end() async throws -> String {
        feed?.end()
        guard let setup else { return "" }
        self.setup = nil
        let (analyzer, collector) = try await setup.value
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = try await collector.value
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }
}
