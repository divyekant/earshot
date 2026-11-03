// The end-of-turn model: Pipecat Smart Turn v3.2 (BSD-2-Clause, Daily), Core ML conversion
// aufklarer/Smart-Turn-v3.2-CoreML. Based on soniqo/speech-swift (Apache-2.0), Sources/SpeechVAD/SmartTurn.swift at
// a57702e. earshot changes: local model folder, no download code, no resampling (the wake trigger gives 16 kHz).
// License: LICENSES/Apache-2.0.txt. The model weights: see THIRD_PARTY_NOTICES.md.
import CoreML
import Foundation

/// Gives the probability that the speaker finished the turn, from the sound of the last 8 s (R-ON-1, I-2).
/// It hears the voice (pitch, pace), not the words. The model has the log-mel front end inside, so it takes raw
/// 16 kHz samples. It is not thread-safe. Use it from one queue.
final class TurnModel {
    static let sampleRate = 16000
    static let windowSamples = 128_000
    static let folderName = "smart_turn.mlmodelc"

    private let model: MLModel

    init(folder: URL, computeUnits: MLComputeUnits = .cpuAndNeuralEngine) throws {
        let url = folder.appendingPathComponent(Self.folderName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioModelError.modelLoadFailed(modelId: "smart-turn", reason: "Core ML model not found at \(url.path)")
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        model = try MLModel(contentsOf: url, configuration: configuration)
    }

    /// The probability, 0 to 1, that the turn is done. `samples` is the turn so far at 16 kHz; the model uses the
    /// last 8 s, and a shorter turn gets zeros at the front.
    func probability(_ samples: [Float]) throws -> Double {
        let window = Self.window(samples)
        let input = try MLMultiArray(shape: [1, NSNumber(value: Self.windowSamples)], dataType: .float32)
        let pointer = input.dataPointer.assumingMemoryBound(to: Float.self)
        window.withUnsafeBufferPointer { pointer.update(from: $0.baseAddress!, count: Self.windowSamples) }
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "audio": MLFeatureValue(multiArray: input),
        ]))
        guard let values = output.featureValue(for: "probability")?.multiArrayValue, values.count >= 1 else {
            throw AudioModelError.inferenceFailed(operation: "turn", reason: "no probability output")
        }
        let p = values[0].doubleValue
        guard p.isFinite else { throw AudioModelError.inferenceFailed(operation: "turn", reason: "not a number") }
        return min(1, max(0, p))
    }

    /// Runs the model one time, so that the first pause does not pay the first-run cost.
    func warmUp() throws {
        var samples = [Float](repeating: 0, count: Self.sampleRate)
        for i in samples.indices { samples[i] = 0.05 * sin(2 * Float.pi * 173 * Float(i) / Float(Self.sampleRate)) }
        _ = try probability(samples)
    }

    /// The last `windowSamples` samples, with zeros at the front if the turn is shorter. A sample that is not a
    /// number becomes 0.
    static func window(_ samples: [Float]) -> [Float] {
        let tail = samples.count > windowSamples ? Array(samples.suffix(windowSamples)) : samples
        var window = [Float](repeating: 0, count: windowSamples)
        let offset = windowSamples - tail.count
        for (i, s) in tail.enumerated() { window[offset + i] = s.isFinite ? s : 0 }
        return window
    }
}
