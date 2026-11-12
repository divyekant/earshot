import Foundation

/// The embedding model of the PA (phase 2 build spec, 7.6). It loads the model at the first use and unloads it
/// after a quiet time. All calls to the model go through one lock, because a model context does one job at a time.
/// The engine queue and the background queue can both call it.
public final class ModelHost: @unchecked Sendable {
    /// The id of the model, known before the load. The store keeps it with each list of numbers.
    public let modelID: String
    let make: () throws -> Embedder
    /// Held during a load and during each embed call.
    let work = NSLock()
    /// Guards `model`, `lastUse` and `failed` for short reads.
    let state = NSLock()
    var model: Embedder?
    var lastUse: Date?
    /// The load failed `maxLoadFailures` times in a row. The PA does not try again until the next start, and uses
    /// keywords only.
    var failed = false
    var loadFailures = 0
    public static let maxLoadFailures = 3
    /// Called after each load, with the new model (for the log: the process id of a worker).
    public var onLoad: ((Embedder) -> Void)?
    /// Called when a call to a loaded model fails, before the model is dropped.
    public var onFault: (() -> Void)?
    /// The values of the proposal and duplicate rules for this model (E10). Nil: no proposals and no notice.
    public var rules: ModelRules?
    /// The time of the last load, for the log.
    public private(set) var lastLoadTime: TimeInterval?

    public init(modelID: String, make: @escaping () throws -> Embedder) {
        self.modelID = modelID
        self.make = make
    }

    public var isLoaded: Bool {
        state.lock()
        defer { state.unlock() }
        return model != nil
    }

    public var isFailed: Bool {
        state.lock()
        defer { state.unlock() }
        return failed
    }

    /// Embeds the texts. Loads the model if it is not loaded. `wait` is the longest time to wait for the lock:
    /// nil waits as long as necessary. Gives nil if the lock is busy for longer, or if the model does not load.
    public func embed(_ texts: [String], kind: EmbedKind, load: Bool = true, wait: TimeInterval? = nil) -> [[Float]]? {
        if let wait {
            guard work.lock(before: Date().addingTimeInterval(wait)) else { return nil }
        } else {
            work.lock()
        }
        defer { work.unlock() }
        guard let m = loadLocked(load) else { return nil }
        touch()
        do {
            return try m.embed(texts, kind: kind)
        } catch {
            // A model in a worker process can stop. Drop it: the next call loads a new one.
            state.lock()
            model = nil
            state.unlock()
            onFault?()
            return nil
        }
    }

    /// Loads the model, if it is not loaded. For a load in the background before the next search.
    public func preload() {
        work.lock()
        defer { work.unlock() }
        _ = loadLocked(true)
        touch()
    }

    /// Unloads the model if it had no use for `after` seconds. Gives true if it unloaded the model.
    @discardableResult
    public func unloadIfIdle(now: Date, after: TimeInterval) -> Bool {
        state.lock()
        let idle = model != nil && (lastUse.map { now.timeIntervalSince($0) >= after } ?? true)
        state.unlock()
        guard idle else { return false }
        // A job that has the lock now uses the model: try again at the next check.
        guard work.try() else { return false }
        defer { work.unlock() }
        state.lock()
        model = nil
        state.unlock()
        return true
    }

    /// Unloads the model now. The program calls it before it stops: a GPU model that is still loaded at exit
    /// stops the program in the Metal teardown of llama.cpp.
    public func unload() {
        work.lock()
        defer { work.unlock() }
        state.lock()
        model = nil
        state.unlock()
    }

    func loadLocked(_ load: Bool) -> Embedder? {
        state.lock()
        let m = model
        let f = failed
        state.unlock()
        if let m { return m }
        guard load, !f else { return nil }
        let t = Date()
        do {
            let e = try make()
            // The first text loads the data of the model into memory.
            _ = try e.embed(["A first text to load the model."], kind: .passage)
            lastLoadTime = Date().timeIntervalSince(t)
            state.lock()
            model = e
            loadFailures = 0
            state.unlock()
            onLoad?(e)
            return e
        } catch {
            state.lock()
            loadFailures += 1
            if loadFailures >= Self.maxLoadFailures { failed = true }
            state.unlock()
            return nil
        }
    }

    func touch() {
        state.lock()
        lastUse = Date()
        state.unlock()
    }
}
