// The speaker embedding: WeSpeaker ResNet34-LM (Core ML conversion aufklarer/WeSpeaker-ResNet34-LM-CoreML).
// Based on soniqo/speech-swift (Apache-2.0), Sources/SpeechVAD/CoreMLWeSpeakerInference.swift and WeSpeaker.swift
// at a57702e. earshot changes: 16-bit floats through Half (no Float16 on Intel Macs); local model folder; no MLX path.
// License: LICENSES/Apache-2.0.txt. The model weights: see THIRD_PARTY_NOTICES.md.
import CoreML
import Foundation

/// Makes a 256-value voice embedding from 16 kHz mono audio (R-ON-3).
/// It is not thread-safe. Use it from one queue.
final class VoiceModel {
    /// The frame counts that the Core ML model accepts (enumerated shapes, 10 ms frames).
    static let melLengths = [20, 50, 100, 200, 300, 500, 750, 1000, 1500, 2000]
    static let dimension = 256

    private let model: MLModel
    private let mel = MelFeatureExtractor()

    init(folder: URL, computeUnits: MLComputeUnits = .cpuAndNeuralEngine) throws {
        let url = folder.appendingPathComponent("wespeaker.mlmodelc", isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioModelError.modelLoadFailed(modelId: "wespeaker", reason: "Core ML model not found at \(url.path)")
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        model = try MLModel(contentsOf: url, configuration: configuration)
    }

    /// The L2-normalized embedding of the audio. Audio longer than 20 s uses the first 20 s.
    func embed(_ samples: [Float]) throws -> [Float] {
        let (features, frames) = mel.extractRaw(samples)
        guard frames > 0 else { throw AudioModelError.inferenceFailed(operation: "voice", reason: "no audio") }
        // The nearest accepted length that holds all frames. Shorter audio is padded with zeros.
        let length = Self.melLengths.first { $0 >= frames } ?? Self.melLengths.last!
        let input = try MLMultiArray(shape: [1, NSNumber(value: length), 80], dataType: .float16)
        var padded = [Float](repeating: 0, count: length * 80)
        let copy = min(frames, length) * 80
        for i in 0..<copy { padded[i] = features[i] }
        Half.store(padded, count: padded.count, to: input.dataPointer)

        let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["mel": MLFeatureValue(multiArray: input)]))
        guard let out = result.featureValue(for: "embedding")?.multiArrayValue else {
            throw AudioModelError.inferenceFailed(operation: "voice", reason: "no embedding output")
        }
        var embedding: [Float]
        switch out.dataType {
        case .float16: embedding = Half.load(out.dataPointer, count: Self.dimension)
        case .float32:
            let p = out.dataPointer.assumingMemoryBound(to: Float.self)
            embedding = Array(UnsafeBufferPointer(start: p, count: Self.dimension))
        default:
            throw AudioModelError.inferenceFailed(operation: "voice", reason: "unexpected output type")
        }
        return Self.normalized(embedding)
    }

    static func normalized(_ v: [Float]) -> [Float] {
        let norm = v.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        return norm > 1e-10 ? v.map { $0 / norm } : v
    }

    /// The cosine similarity of two embeddings.
    static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let d = na.squareRoot() * nb.squareRoot()
        return d > 0 ? Double(dot / d) : 0
    }
}
