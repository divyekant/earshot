import Foundation

/// The model in a worker process (phase 2 follow-up spec, R3). The PA starts `earshot-pa --embed-worker <model>`
/// with the same program file. The worker loads the model, reads requests on stdin and writes the numbers on stdout.
/// It reads no file of the owner and has no access to the store: the PA sends the texts.
///
/// If the worker stops, or gives no answer in `timeout` seconds, `embed` throws. The PA then treats the model as
/// not loaded, and the next use starts a new worker. When the PA unloads the model, it frees this object, which
/// closes the stdin of the worker: the worker frees the model and stops.
public final class WorkerEmbedder: Embedder {
    public let id: String
    public private(set) var dimension: Int
    let process: Process
    let input: FileHandle
    let timeout: TimeInterval
    /// Guards `lines` and `ended`.
    let lock = NSLock()
    let ready = DispatchSemaphore(value: 0)
    var buffer = Data()
    var lines: [Data] = []
    var ended = false
    var nextID = 0

    public struct WorkerError: Error, CustomStringConvertible {
        public var description: String
    }

    struct Request: Codable { var id: Int; var kind: String; var texts: [String] }
    struct Response: Codable { var id: Int; var vectors: [[Float]]?; var error: String? }

    /// The process id of the worker, for the log.
    public var pid: Int32 { process.processIdentifier }

    public init(executable: URL, arguments: [String], id: String, dimension: Int, timeout: TimeInterval = 10) throws {
        self.id = id
        self.dimension = dimension
        self.timeout = timeout
        process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let inPipe = Pipe(), outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        input = inPipe.fileHandleForWriting
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard let self else { return }
            self.lock.lock()
            if d.isEmpty {
                self.ended = true
                h.readabilityHandler = nil
            } else {
                self.buffer.append(d)
                while let nl = self.buffer.firstIndex(of: 0x0A) {
                    self.lines.append(self.buffer.subdata(in: self.buffer.startIndex..<nl))
                    self.buffer.removeSubrange(self.buffer.startIndex...nl)
                }
            }
            self.lock.unlock()
            self.ready.signal()
        }
        try process.run()
    }

    public func embed(_ texts: [String], kind: EmbedKind) throws -> [[Float]] {
        nextID += 1
        let rid = nextID
        var line = try JSONEncoder().encode(Request(id: rid, kind: kind.rawValue, texts: texts))
        line.append(0x0A)
        do { try input.write(contentsOf: line) } catch {
            stop()
            throw WorkerError(description: "the worker does not read")
        }
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            lock.lock()
            let next = lines.isEmpty ? nil : lines.removeFirst()
            let gone = ended
            lock.unlock()
            if let next {
                guard let r = try? JSONDecoder().decode(Response.self, from: next), r.id == rid else { continue }
                guard let v = r.vectors, v.count == texts.count else {
                    throw WorkerError(description: "the worker gave no numbers")
                }
                if let first = v.first, !first.isEmpty { dimension = first.count }
                return v
            }
            if gone || !process.isRunning {
                throw WorkerError(description: "the worker stopped")
            }
            if ready.wait(timeout: .now() + max(0, deadline.timeIntervalSinceNow)) == .timedOut, Date() >= deadline {
                stop()
                throw WorkerError(description: "the worker gave no answer in time")
            }
        }
    }

    /// Closes the stdin of the worker. If the worker still runs after 2 s, the PA stops it.
    public func stop() {
        try? input.close()
        let p = process
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            if p.isRunning { p.terminate() }
        }
    }

    deinit { stop() }
}

/// The loop of the worker process: `earshot-pa --embed-worker <model>`. It reads one request on each line of
/// stdin and writes one answer on each line of stdout. It stops when stdin closes, or after `idle` seconds with
/// no request. `release` runs before the stop, so that a GPU model is freed before the exit.
public enum EmbedWorker {
    final class Inbox: @unchecked Sendable {
        let lock = NSLock()
        var pending: [String] = []
        var closed = false
        let ready = DispatchSemaphore(value: 0)
    }

    public static func run(_ embedder: Embedder, idle: TimeInterval = 300, release: () -> Void) -> Int32 {
        let inbox = Inbox()
        Thread.detachNewThread {
            while let l = readLine(strippingNewline: true) {
                inbox.lock.lock(); inbox.pending.append(l); inbox.lock.unlock()
                inbox.ready.signal()
            }
            inbox.lock.lock(); inbox.closed = true; inbox.lock.unlock()
            inbox.ready.signal()
        }
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        while true {
            inbox.lock.lock()
            let line = inbox.pending.isEmpty ? nil : inbox.pending.removeFirst()
            let end = inbox.closed
            inbox.lock.unlock()
            if let line {
                guard let req = try? decoder.decode(WorkerEmbedder.Request.self, from: Data(line.utf8)) else { continue }
                var res = WorkerEmbedder.Response(id: req.id)
                do {
                    res.vectors = try embedder.embed(req.texts, kind: EmbedKind(rawValue: req.kind) ?? .passage)
                } catch {
                    res.error = "embed failed"
                }
                if var data = try? encoder.encode(res) {
                    data.append(0x0A)
                    do { try FileHandle.standardOutput.write(contentsOf: data) } catch { break }
                }
                continue
            }
            if end { break }
            if inbox.ready.wait(timeout: .now() + idle) == .timedOut { break }
        }
        release()
        return 0
    }
}
