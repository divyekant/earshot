import Foundation
import PACore
#if canImport(llama)
import llama

/// Candidates 3 and 4 (phase 2 build spec, 6.2): a GGUF embedding model in llama.cpp. The model file comes from
/// the install script (a fixed revision and a SHA-256 check). This code only reads the file. It has no network code.
public final class LlamaEmbedder: Embedder {
    public struct Spec: Sendable {
        public var id: String
        public var queryPrefix: String
        public var passagePrefix: String
        /// Add the end token if the tokenizer does not (last-token pooling needs it).
        public var endToken: Bool
    }

    /// Qwen3-Embedding-0.6B: an instruction before a query, nothing before a passage, last-token pooling.
    public static let qwen3 = Spec(
        id: "qwen3-embedding-0.6b-q8_0",
        queryPrefix: "Instruct: Given a question or a note, find the passage, the document or the item that it is about\nQuery:",
        passagePrefix: "", endToken: true)

    /// EmbeddingGemma-300M: the prompts of its model card, mean pooling.
    public static let gemma = Spec(
        id: "embeddinggemma-300m-q8_0",
        queryPrefix: "task: search result | query: ", passagePrefix: "title: none | text: ", endToken: false)

    /// EmbeddingGemma 2 (Apache 2.0), text model only: the same prompts as EmbeddingGemma, mean pooling.
    public static let gemma2 = Spec(
        id: "embeddinggemma-2-q8_0",
        queryPrefix: "task: search result | query: ", passagePrefix: "title: none | text: ", endToken: false)

    public let id: String
    public let dimension: Int
    let spec: Spec
    let model: OpaquePointer
    let ctx: OpaquePointer
    let vocab: OpaquePointer
    let maxTokens: Int32 = 1024

    public init(path: String, spec: Spec, gpu: Bool) throws {
        llama_backend_init()
        llama_log_set({ _, _, _ in }, nil)
        var mp = llama_model_default_params()
        mp.n_gpu_layers = gpu ? 999 : 0
        guard let m = llama_model_load_from_file(path, mp) else {
            throw EmbedderError(description: "the model file does not load")
        }
        var cp = llama_context_default_params()
        cp.embeddings = true
        cp.n_ctx = UInt32(maxTokens)
        cp.n_batch = UInt32(maxTokens)
        cp.n_ubatch = UInt32(maxTokens)
        cp.n_threads = 4
        cp.n_threads_batch = 4
        guard let c = llama_init_from_model(m, cp) else {
            llama_model_free(m)
            throw EmbedderError(description: "the model context does not start")
        }
        model = m
        ctx = c
        vocab = llama_model_get_vocab(m)
        dimension = Int(llama_model_n_embd(m))
        self.spec = spec
        id = spec.id
    }

    deinit {
        llama_free(ctx)
        llama_model_free(model)
    }

    public func embed(_ texts: [String], kind: EmbedKind) throws -> [[Float]] {
        try texts.map { try one((kind == .query ? spec.queryPrefix : spec.passagePrefix) + $0) }
    }

    func tokens(_ text: String) -> [llama_token] {
        let n = Int32(text.utf8.count)
        var buf = [llama_token](repeating: 0, count: Int(n) + 8)
        var count = llama_tokenize(vocab, text, n, &buf, Int32(buf.count), true, false)
        if count < 0 {
            buf = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, text, n, &buf, Int32(buf.count), true, false)
        }
        var out = Array(buf.prefix(Int(max(0, count))))
        let eos = llama_vocab_eos(vocab)
        if out.count > Int(maxTokens) - 1 { out = Array(out.prefix(Int(maxTokens) - 1)) }
        if spec.endToken, out.last != eos { out.append(eos) }
        return out
    }

    func one(_ text: String) throws -> [Float] {
        let toks = tokens(text)
        guard !toks.isEmpty else { return [Float](repeating: 0, count: dimension) }
        llama_memory_clear(llama_get_memory(ctx), true)
        var batch = llama_batch_init(Int32(toks.count), 0, 1)
        defer { llama_batch_free(batch) }
        for (i, t) in toks.enumerated() {
            batch.token[i] = t
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = 1
        }
        batch.n_tokens = Int32(toks.count)
        guard llama_decode(ctx, batch) == 0 else { throw EmbedderError(description: "the model did not run") }
        guard let e = llama_get_embeddings_seq(ctx, 0) else { throw EmbedderError(description: "no numbers from the model") }
        return Vectors.normalized(Array(UnsafeBufferPointer(start: e, count: dimension)))
    }
}
#endif
