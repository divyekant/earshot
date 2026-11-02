// earshot: small stand-ins for the parts of speech-swift's AudioCommon module that the copied wake word code uses.
// earshot does not depend on the speech-swift package (it needs macOS 15 and MLX). See THIRD_PARTY_NOTICES.md.
import Accelerate
import Foundation

/// The errors of the copied wake word code. Same cases as speech-swift's `AudioModelError`, without the ones it does not use.
enum AudioModelError: Error, LocalizedError, CustomStringConvertible {
    case modelLoadFailed(modelId: String, reason: String)
    case inferenceFailed(operation: String, reason: String)
    case invalidConfiguration(model: String, reason: String)

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .modelLoadFailed(let modelId, let reason): return "the model \(modelId) did not load: \(reason)"
        case .inferenceFailed(let operation, let reason): return "the model step \(operation) failed: \(reason)"
        case .invalidConfiguration(let model, let reason): return "bad settings for \(model): \(reason)"
        }
    }
}

/// The log of the copied code. Errors go to the system log. earshot logs no audio and no text here.
enum AudioLog {
    struct Channel {
        let name: String
        func error(_ message: @autoclosure () -> String) { NSLog("earshot wake %@: %@", name, message()) }
        func warning(_ message: @autoclosure () -> String) { NSLog("earshot wake %@: %@", name, message()) }
        func info(_ message: @autoclosure () -> String) {}
    }

    static let inference = Channel(name: "inference")
    static let modelLoading = Channel(name: "load")
}

/// 16-bit floats in Core ML arrays. Swift's `Float16` type is not available on Intel Macs, so this uses vImage,
/// which converts on every Mac.
enum Half {
    /// Writes the first `count` values of `values` to `destination` as 16-bit floats.
    static func store(_ values: [Float], count: Int, to destination: UnsafeMutableRawPointer) {
        let n = min(count, values.count)
        guard n > 0 else { return }
        values.withUnsafeBufferPointer { source in
            var from = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: source.baseAddress!),
                                     height: 1, width: vImagePixelCount(n), rowBytes: n * MemoryLayout<Float>.size)
            var to = vImage_Buffer(data: destination, height: 1, width: vImagePixelCount(n), rowBytes: n * 2)
            _ = vImageConvert_PlanarFtoPlanar16F(&from, &to, vImage_Flags(kvImageNoFlags))
        }
    }

    /// Reads `count` 16-bit floats from `source`.
    static func load(_ source: UnsafeRawPointer, count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: max(0, count))
        guard count > 0 else { return out }
        out.withUnsafeMutableBufferPointer { destination in
            var from = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: source),
                                     height: 1, width: vImagePixelCount(count), rowBytes: count * 2)
            var to = vImage_Buffer(data: destination.baseAddress!, height: 1, width: vImagePixelCount(count),
                                   rowBytes: count * MemoryLayout<Float>.size)
            _ = vImageConvert_Planar16FtoPlanarF(&from, &to, vImage_Flags(kvImageNoFlags))
        }
        return out
    }
}
