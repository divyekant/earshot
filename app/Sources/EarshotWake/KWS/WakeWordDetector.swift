// Copied from soniqo/speech-swift (Apache-2.0), Sources/SpeechWakeWord/SpeechWakeWord.swift at a57702e.
// earshot changes: `load(from:)` reads the model files from a local folder (ModelFiles downloads and checks them)
// in place of the Hugging Face download; no resampling (the input is 16 kHz); no parity-test decoder; the decoder and
// joiner are visible in the module for the enrolment (TokenReader); plain MLModel load. License: LICENSES/Apache-2.0.txt.
import CoreML
import Foundation

/// On-device wake-word / keyword spotter built on icefall's KWS Zipformer
/// (gigaspeech, 3.49M params) exported to CoreML.
///
/// Ships as three ``.mlmodelc`` bundles (encoder / decoder / joiner), a
/// SentencePiece BPE vocabulary (500 pieces), and a tuned threshold/boost pair.
///
/// - Warning: Not thread-safe. Create one detector per streaming audio source.
public final class WakeWordDetector {
    public let config: KWSZipformerConfig
    public let vocabulary: KWSVocabulary
    public let keywords: [KeywordSpec]
    public let contextGraph: ContextGraph

    let bpeTokenizer: BPETokenizer
    let fbank: KaldiFbank
    let encoder: MLModel
    let decoder: MLModel
    let joiner: MLModel

    private init(
        config: KWSZipformerConfig,
        vocabulary: KWSVocabulary,
        bpeTokenizer: BPETokenizer,
        keywords: [KeywordSpec],
        contextGraph: ContextGraph,
        fbank: KaldiFbank,
        encoder: MLModel,
        decoder: MLModel,
        joiner: MLModel
    ) {
        self.config = config
        self.vocabulary = vocabulary
        self.bpeTokenizer = bpeTokenizer
        self.keywords = keywords
        self.contextGraph = contextGraph
        self.fbank = fbank
        self.encoder = encoder
        self.decoder = decoder
        self.joiner = joiner
    }

    // MARK: - Streaming API

    /// Create a new streaming detection session sharing this detector's models
    /// and context graph. Call ``WakeWordSession/reset()`` between unrelated
    /// audio streams.
    public func createSession(
        options: WakeWordDecodingOptions = WakeWordDecodingOptions()
    ) throws -> WakeWordSession {
        try WakeWordSession(
            config: config,
            encoder: encoder,
            decoder: decoder,
            joiner: joiner,
            fbank: fbank,
            contextGraph: contextGraph,
            options: options
        )
    }

    /// Batch-detect keyword occurrences in a full 16 kHz audio buffer.
    public func detect(
        audio: [Float],
        options: WakeWordDecodingOptions = WakeWordDecodingOptions()
    ) throws -> [KeywordDetection] {
        let session = try createSession(options: options)
        var detections = try session.pushAudio(audio)
        detections.append(contentsOf: try session.finalize())
        return detections
    }

    /// Runs the models once, so that the first real chunk does not pay the first-run cost.
    public func warmUp() throws {
        let dummy = [Float](repeating: 0, count: config.feature.sampleRate) // 1s silence
        _ = try detect(audio: dummy)
    }

    // MARK: - Loading

    /// Loads the models from `directory` and builds a context graph from the keywords.
    /// The folder holds encoder.mlmodelc, decoder.mlmodelc, joiner.mlmodelc, tokens.txt, bpe.model and config.json.
    public static func load(
        from directory: URL,
        keywords: [KeywordSpec],
        computeUnits: MLComputeUnits = .cpuAndNeuralEngine
    ) throws -> WakeWordDetector {
        let config: KWSZipformerConfig
        let configURL = directory.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: configURL.path) {
            let data = try Data(contentsOf: configURL)
            config = try JSONDecoder().decode(KWSZipformerConfig.self, from: data)
        } else {
            config = .default
        }

        let vocab = try KWSVocabulary.load(
            from: directory.appendingPathComponent("tokens.txt"),
            blankId: config.decoder.blankId
        )
        let sp = try SentencePieceModel(contentsOf: directory.appendingPathComponent("bpe.model"))
        let tokenizer = BPETokenizer(model: sp)

        let encoder = try loadMLModel(name: "encoder", from: directory, units: computeUnits)
        let decoder = try loadMLModel(name: "decoder", from: directory, units: computeUnits)
        let joiner = try loadMLModel(name: "joiner", from: directory, units: computeUnits)

        let fbank = KaldiFbank(.init(
            sampleRate: config.feature.sampleRate,
            frameLengthMs: config.feature.frameLengthMs,
            frameShiftMs: config.feature.frameShiftMs,
            numMelBins: config.feature.numMelBins,
            highFreq: config.feature.highFreq,
            snipEdges: config.feature.snipEdges
        ))

        let graph = try buildContextGraph(
            keywords: keywords, tokenizer: tokenizer,
            vocabulary: vocab, defaults: config.kws
        )

        return WakeWordDetector(
            config: config,
            vocabulary: vocab,
            bpeTokenizer: tokenizer,
            keywords: keywords,
            contextGraph: graph,
            fbank: fbank,
            encoder: encoder,
            decoder: decoder,
            joiner: joiner
        )
    }

    /// Build a context graph using this detector's tokenizer. Useful when
    /// you want to swap keyword lists without reloading the model.
    public func rebuildContextGraph(keywords: [KeywordSpec]) throws -> WakeWordDetector {
        let graph = try Self.buildContextGraph(
            keywords: keywords, tokenizer: bpeTokenizer,
            vocabulary: vocabulary, defaults: config.kws
        )
        return WakeWordDetector(
            config: config,
            vocabulary: vocabulary,
            bpeTokenizer: bpeTokenizer,
            keywords: keywords,
            contextGraph: graph,
            fbank: fbank,
            encoder: encoder,
            decoder: decoder,
            joiner: joiner
        )
    }

    // MARK: - Helpers

    private static func buildContextGraph(
        keywords: [KeywordSpec],
        tokenizer: BPETokenizer,
        vocabulary: KWSVocabulary,
        defaults: KWSZipformerConfig.KWSDefaults
    ) throws -> ContextGraph {
        guard !keywords.isEmpty else {
            throw AudioModelError.invalidConfiguration(
                model: "KWS-Zipformer",
                reason: "At least one KeywordSpec is required"
            )
        }
        let graph = ContextGraph(
            contextScore: defaults.defaultContextScore,
            acThreshold: defaults.defaultThreshold
        )
        var tokenIds: [[Int]] = []
        var phrases: [String] = []
        var boosts: [Double] = []
        var thresholds: [Double] = []
        for kw in keywords {
            let ids: [Int]
            if let pieces = kw.tokens {
                ids = try pieces.map { piece -> Int in
                    guard let id = vocabulary.tokenToId[piece] else {
                        throw AudioModelError.invalidConfiguration(
                            model: "KWS-Zipformer",
                            reason: "Unknown BPE piece '\(piece)' in keyword '\(kw.phrase)'"
                        )
                    }
                    return id
                }
            } else {
                ids = tokenizer.encode(kw.phrase)
            }
            tokenIds.append(ids)
            phrases.append(kw.phrase)
            boosts.append(kw.boost)
            thresholds.append(kw.acThreshold)
        }
        graph.build(
            tokenIds: tokenIds,
            phrases: phrases,
            boosts: boosts,
            thresholds: thresholds
        )
        return graph
    }

    private static func loadMLModel(
        name: String, from directory: URL, units: MLComputeUnits
    ) throws -> MLModel {
        let url = directory.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioModelError.modelLoadFailed(
                modelId: name, reason: "CoreML model not found at \(url.path)"
            )
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = units
        return try MLModel(contentsOf: url, configuration: configuration)
    }
}
