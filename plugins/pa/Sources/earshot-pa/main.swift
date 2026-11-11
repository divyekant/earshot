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
                    detector: SystemDateDetector())
queue.sync {
    engine.runLater = { delay, block in queue.asyncAfter(deadline: .now() + delay, execute: block) }
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
