import Foundation
import PACore
#if canImport(NaturalLanguage)
import NaturalLanguage

/// Candidate 1 (phase 2 build spec, 6.2): the sentence embedding that macOS includes. No download.
public final class NLSentenceEmbedder: Embedder {
    public let id: String
    public let dimension: Int
    let model: NLEmbedding

    public init?(language: NLLanguage = .english) {
        guard let m = NLEmbedding.sentenceEmbedding(for: language) else { return nil }
        model = m
        dimension = m.dimension
        id = "nl-sentence-\(language.rawValue)-r\(m.revision)"
    }

    public func embed(_ texts: [String], kind: EmbedKind) throws -> [[Float]] {
        texts.map { t in
            model.vector(for: t)?.map(Float.init) ?? [Float](repeating: 0, count: dimension)
        }
    }
}


/// Candidate 2 (6.2): the contextual embedding of macOS. macOS can download its data one time. The list of a text
/// is the mean of the lists of its tokens.
@available(macOS 14.0, *)
public final class NLContextualEmbedder: Embedder {
    public let id: String
    public let dimension: Int
    let model: NLContextualEmbedding
    let language: NLLanguage

    /// - Parameter allowAssetRequest: if true and the data is not on the Mac, ask macOS to get it, and wait.
    public init(language: NLLanguage = .english, allowAssetRequest: Bool) throws {
        guard let m = NLContextualEmbedding(language: language) else {
            throw EmbedderError(description: "no contextual embedding for \(language.rawValue)")
        }
        if !m.hasAvailableAssets {
            guard allowAssetRequest else { throw EmbedderError(description: "the data of the contextual embedding is not on this Mac") }
            let sem = DispatchSemaphore(value: 0)
            var outcome = "unknown"
            m.requestAssets { result, error in
                switch result {
                case .available: outcome = "available"
                case .notAvailable: outcome = "not available"
                case .error: outcome = "error \(error.map { "\($0)" } ?? "")"
                @unknown default: outcome = "unknown"
                }
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 600)
            // The answer can come before the data is ready. The state of the data decides.
            if !m.hasAvailableAssets {
                throw EmbedderError(description: "the data of the contextual embedding: \(outcome)")
            }
        }
        try m.load()
        model = m
        self.language = language
        dimension = m.dimension
        id = "nl-contextual-\(m.modelIdentifier)-r\(m.revision)"
    }

    public func embed(_ texts: [String], kind: EmbedKind) throws -> [[Float]] {
        try texts.map { t in
            var sum = [Double](repeating: 0, count: dimension)
            var n = 0
            guard !t.isEmpty else { return [Float](repeating: 0, count: dimension) }
            let r = try model.embeddingResult(for: t, language: language)
            r.enumerateTokenVectors(in: t.startIndex..<t.endIndex) { v, _ in
                for i in 0..<min(v.count, sum.count) { sum[i] += v[i] }
                n += 1
                return true
            }
            return n == 0 ? sum.map(Float.init) : sum.map { Float($0 / Double(n)) }
        }
    }
}
#endif

public struct EmbedderError: Error, CustomStringConvertible {
    public var description: String
    public init(description: String) { self.description = description }
}

/// The memory footprint of this program in bytes (the number that Activity Monitor shows), or nil.
public func memoryFootprint() -> Int? {
    #if os(macOS)
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let rc = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return rc == KERN_SUCCESS ? Int(info.phys_footprint) : nil
    #else
    return nil
    #endif
}

/// The embedder for a name of the bench: "hash", "nl-sentence", "nl-contextual", "qwen3", "gemma".
/// "qwen3" and "gemma" need `modelFile`, a GGUF file.
public func makeEmbedder(_ name: String, allowAssetRequest: Bool = false, modelFile: String? = nil,
                         gpu: Bool = false) throws -> Embedder {
    switch name {
    case "hash": return HashEmbedder()
    #if canImport(llama)
    case "qwen3", "gemma":
        guard let modelFile else { throw EmbedderError(description: "\(name) needs --model <file.gguf>") }
        return try LlamaEmbedder(path: modelFile, spec: name == "qwen3" ? LlamaEmbedder.qwen3 : LlamaEmbedder.gemma, gpu: gpu)
    #endif
    #if canImport(NaturalLanguage)
    case "nl-sentence":
        guard let e = NLSentenceEmbedder() else { throw EmbedderError(description: "no sentence embedding on this Mac") }
        return e
    case "nl-contextual":
        if #available(macOS 14.0, *) { return try NLContextualEmbedder(allowAssetRequest: allowAssetRequest) }
        throw EmbedderError(description: "needs macOS 14")
    #endif
    default:
        throw BenchNameError(name: name)
    }
}

public struct BenchNameError: Error, CustomStringConvertible {
    public var name: String
    public var description: String { "unknown embedder \(name)" }
}
