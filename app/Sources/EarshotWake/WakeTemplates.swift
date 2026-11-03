import EarshotCore
import Foundation

/// Makes the audio templates of the wake phrase from the teach takes, and packs them for `voice.json` (D-11, E5).
/// A template is the encoder frames of the spoken part of one take. It is not audio.
enum WakeTemplates {
    /// Digital quiet before a take, as in the E5 bench (0.3 s).
    static let leadSamples = 4800
    /// Digital quiet after a take, so that the encoder gives the last frames (0.5 s).
    static let tailSamples = 8000
    /// The encoder frame of a sound comes about 2 frames (80 ms) after the sound (E5).
    static let delayFrames = 2
    /// One more frame at each end of the speech.
    static let padFrames = 1
    static let secondsPerFrame = 0.04

    /// The frames of the template, from the encoder frames of one take.
    /// - Parameters:
    ///   - frames: the encoder frames of `leadSamples` of quiet, the take, and `tailSamples` of quiet.
    ///   - speech: the loud part of the take, in samples from the start of the take.
    static func cut(_ frames: [[Float]], speech: Range<Int>, rate: Int = 16000) -> [[Float]] {
        let start = Double(leadSamples + speech.lowerBound) / Double(rate)
        let end = Double(leadSamples + speech.upperBound) / Double(rate)
        let first = max(0, Int((start / secondsPerFrame).rounded()) + delayFrames - padFrames)
        let last = min(frames.count, Int((end / secondsPerFrame).rounded()) + delayFrames + padFrames)
        guard last > first else { return [] }
        return Array(frames[first..<last])
    }

    /// Packs the frames as 16-bit floats.
    static func pack(_ frames: [[Float]]) -> WakeTemplate {
        let width = frames.first?.count ?? 0
        let flat = frames.flatMap { $0.count == width ? $0 : [Float](repeating: 0, count: width) }
        var data = Data(count: flat.count * 2)
        data.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress, !flat.isEmpty { Half.store(flat, count: flat.count, to: base) }
        }
        return WakeTemplate(frames: frames.count, width: width, half: data)
    }

    /// Unpacks the frames. Empty if the data does not have the size of the frames.
    static func unpack(_ template: WakeTemplate) -> [[Float]] {
        guard template.isValid else { return [] }
        let count = template.frames * template.width
        let flat = template.half.withUnsafeBytes { raw -> [Float] in
            guard let base = raw.baseAddress else { return [] }
            return Half.load(base, count: count)
        }
        guard flat.count == count else { return [] }
        return (0..<template.frames).map { Array(flat[($0 * template.width)..<(($0 + 1) * template.width)]) }
    }
}
