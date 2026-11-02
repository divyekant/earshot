import CoreML
import Foundation

/// Reads which word pieces the spotter model hears in a short clip, with greedy transducer decoding.
/// The enrolment uses it: the model hears a made-up name such as "earshot" as other words ("YOUR SHOT"),
/// so earshot listens for the pieces that the model heard when the owner said the phrase.
struct TokenReader {
    let detector: WakeWordDetector

    /// The word pieces of the clip, for example ["▁HE", "Y", "▁YOUR", "▁SHOT"].
    func pieces(_ audio: [Float]) throws -> [String] {
        try ids(audio).compactMap { detector.vocabulary.idToToken[$0] }
    }

    /// The token ids of the clip. Blank frames give no token. One token at most for each encoder frame
    /// (40 ms), the same as the streaming greedy search of sherpa-onnx.
    func ids(_ audio: [Float]) throws -> [Int] {
        let session = try detector.createSession()
        var frames: [[Float]] = []
        session.frameSink = { frames.append($0) }
        let rate = detector.config.feature.sampleRate
        // Silence before and after the clip, so that the first and the last word are not cut.
        let padded = [Float](repeating: 0, count: rate / 4) + audio + [Float](repeating: 0, count: rate / 2)
        _ = try session.pushAudio(padded)
        _ = try session.finalize()

        let blank = detector.config.decoder.blankId
        let contextSize = detector.config.decoder.contextSize
        var context = [Int](repeating: blank, count: contextSize)
        var decoderOut = WakeWordSession.runDecoder(model: detector.decoder, contextTokens: context,
                                                    contextSize: contextSize)
        guard !decoderOut.isEmpty else { throw WakeError("The spotter decoder gave no output.") }
        var out: [Int] = []
        for frame in frames {
            let logits = WakeWordSession.runJoiner(model: detector.joiner, encoderFrame: frame, decoderOut: decoderOut)
            guard let best = Self.argmax(logits), best != blank else { continue }
            if let unk = detector.vocabulary.unkId, best == unk { continue }
            out.append(best)
            context = Array((context + [best]).suffix(contextSize))
            decoderOut = WakeWordSession.runDecoder(model: detector.decoder, contextTokens: context,
                                                    contextSize: contextSize)
        }
        return out
    }

    static func argmax(_ values: [Float]) -> Int? {
        guard var bestValue = values.first else { return nil }
        var best = 0
        for i in 1..<values.count where values[i] > bestValue { bestValue = values[i]; best = i }
        return best
    }
}
