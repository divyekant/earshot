import Foundation
import PACore
import PAMac

// The PA plugin of earshot (docs/PLUGINS.md, docs/PA.md). earshot starts this program and talks JSON lines on
// stdin and stdout. The program stops when stdin closes. It has no network code.

setvbuf(stdout, nil, _IOLBF, 0)

/// Writes each message as one line on stdout.
final class StdoutOutput: Output {
    private let lock = NSLock()
    func send(_ message: Outgoing) {
        var data = message.line()
        data.append(0x0A)
        lock.lock()
        FileHandle.standardOutput.write(data)
        lock.unlock()
    }
}

func reminderStore() -> ReminderStore? {
    #if canImport(EventKit)
    return EventKitStore()
    #else
    return nil
    #endif
}

let args = CommandLine.arguments

// Probe 1 by hand: ask for access to Reminders and print the result. As a plugin, the PA asks at the first hello.
if args.contains("--probe-reminders") {
    guard let r = reminderStore() else { print("Reminders: not on this system"); exit(1) }
    print("Reminders access before: \(r.access)")
    let sem = DispatchSemaphore(value: 0)
    r.requestAccess { result in
        print("Reminders access: \(result)")
        sem.signal()
    }
    while sem.wait(timeout: .now() + 0.1) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    exit(0)
}

// The bench of phase 2 (build spec 6.5): earshot-pa --embed-bench <fixtures folder> --embedder <name> [--dims N]
// [--get-assets]. It reads only the made-up fixtures and prints one table.
if let i = args.firstIndex(of: "--embed-bench"), i + 1 < args.count {
    func value(_ flag: String) -> String? {
        args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }
    let name = value("--embedder") ?? "hash"
    do {
        let fx = try BenchFixtures.load(URL(fileURLWithPath: args[i + 1], isDirectory: true))
        let before = memoryFootprint()
        let t0 = Date()
        let embedder = try makeEmbedder(name, allowAssetRequest: args.contains("--get-assets"))
        _ = try embedder.embed(["A first text to load the model."], kind: .passage)
        let load = Date().timeIntervalSince(t0)
        let bench = EmbedBench(fixtures: fx, embedder: embedder, dims: value("--dims").flatMap(Int.init))
        bench.progress = { FileHandle.standardError.write(Data(("BENCH " + $0 + "\n").utf8)) }
        var result = try bench.run()
        result.rows.insert(("First load and first text", String(format: "%.0f ms", load * 1000)), at: 1)
        if let b = before, let a = memoryFootprint() {
            result.rows.append(("Memory footprint", String(format: "%.1f MB before the model, %.1f MB after the bench", Double(b) / 1e6, Double(a) / 1e6)))
        }
        print(EmbedBench.table(result))
        exit(0)
    } catch {
        print("Bench error: \(error)")
        exit(1)
    }
}

let env = ProcessInfo.processInfo.environment
let folder: URL
if let path = env["EARSHOT_PLUGIN_DATA"], !path.isEmpty {
    folder = URL(fileURLWithPath: path, isDirectory: true)
} else {
    folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/earshot/plugin-data/pa", isDirectory: true)
}

/// One serial queue owns the engine and the store.
let queue = DispatchQueue(label: "earshot.pa.engine")
let output = StdoutOutput()
let engine = Engine(folder: folder, clock: SystemClock(), output: output, reminders: reminderStore(),
                    detector: SystemDateDetector(), textReader: makeTextReader())
// The reads of kept files run at background priority, one at a time, so that they do not slow a command
// (phase 2 build rule 6).
let backgroundQueue = DispatchQueue(label: "earshot.pa.background", qos: .utility)
queue.sync {
    engine.runLater = { delay, block in queue.asyncAfter(deadline: .now() + delay, execute: block) }
    engine.background = { block in backgroundQueue.async(execute: block) }
    engine.start()
}

// The clock: one timer for the next check, and a check at least each 60 s (build spec 10.1). The timer uses the
// wall clock, so it fires at the right time after a sleep of the Mac.
let timer = DispatchSource.makeTimerSource(queue: queue)
func scheduleCheck() {
    let now = Date()
    var delay: TimeInterval = 60
    if let next = engine.nextCheck() { delay = min(60, max(0.05, next.timeIntervalSince(now) + 0.05)) }
    timer.schedule(wallDeadline: .now() + delay, leeway: .milliseconds(100))
}
timer.setEventHandler {
    engine.tick()
    scheduleCheck()
}
queue.sync { scheduleCheck() }
timer.resume()
let systemEvents = SystemEvents { _ in
    queue.async {
        engine.tick()
        scheduleCheck()
    }
}

// A watch on the data folder: a new settings.json (an editor saves it as a new file) takes effect in about 1 s,
// not at the next 60 s check (build spec 10.4).
#if os(macOS)
let folderFD = open(folder.path, O_EVTONLY)
let folderWatch = folderFD >= 0
    ? DispatchSource.makeFileSystemObjectSource(fileDescriptor: folderFD, eventMask: [.write, .rename], queue: queue) : nil
let settingsFD = open(folder.appendingPathComponent("settings.json").path, O_EVTONLY)
let settingsWatch = settingsFD >= 0
    ? DispatchSource.makeFileSystemObjectSource(fileDescriptor: settingsFD, eventMask: [.write, .extend], queue: queue) : nil
var settingsCheckPending = false
func settingsMayHaveChanged() {
    guard !settingsCheckPending else { return }
    settingsCheckPending = true
    // Wait a short time, so that the editor has finished the write.
    queue.asyncAfter(deadline: .now() + 0.5) {
        settingsCheckPending = false
        if engine.reloadSettingsIfChanged() { engine.flushPages() }
        scheduleCheck()
    }
}
folderWatch?.setEventHandler(handler: settingsMayHaveChanged)
settingsWatch?.setEventHandler(handler: settingsMayHaveChanged)
folderWatch?.resume()
settingsWatch?.resume()
#endif

// Read stdin on its own thread. Each line goes to the engine queue. At the end of stdin, stop.
let reader = Thread {
    let input = FileHandle.standardInput
    var buffer = Data()
    let maxLine = 1_048_576
    while true {
        let chunk = input.availableData
        if chunk.isEmpty { break }
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if line.isEmpty { continue }
            queue.async {
                engine.receive(line)
                scheduleCheck()
            }
        }
        // A line with no end that is too long: drop it.
        if buffer.count > maxLine { buffer.removeAll() }
    }
    if !buffer.isEmpty { let line = buffer; queue.async { engine.receive(line) } }
    queue.sync { engine.stop() }
    exit(0)
}
reader.start()

// The main run loop delivers the notifications of EventKit and of the system (wake, clock change).
RunLoop.main.run()
