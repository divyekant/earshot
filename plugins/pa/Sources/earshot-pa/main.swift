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
// [--get-assets] [--model <file.gguf>] [--gpu]. It reads only the made-up fixtures and prints one table.
if let i = args.firstIndex(of: "--embed-bench"), i + 1 < args.count {
    func value(_ flag: String) -> String? {
        args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }
    let name = value("--embedder") ?? "hash"
    // The bench runs in a function, so that the embedder is freed before exit. A GPU model that is still
    // loaded at exit stops the program in the Metal teardown of llama.cpp.
    func runBench() -> Int32 {
    do {
        let fx = try BenchFixtures.load(URL(fileURLWithPath: args[i + 1], isDirectory: true))
        let before = memoryFootprint()
        let t0 = Date()
        let embedder = try makeEmbedder(name, allowAssetRequest: args.contains("--get-assets"), modelFile: value("--model"),
                                        gpu: args.contains("--gpu"))
        _ = try embedder.embed(["A first text to load the model."], kind: .passage)
        let load = Date().timeIntervalSince(t0)
        let bench = EmbedBench(fixtures: fx, embedder: embedder, dims: value("--dims").flatMap(Int.init))
        bench.bakeoff = value("--bakeoff").map { URL(fileURLWithPath: $0, isDirectory: true) }
        bench.progress = { FileHandle.standardError.write(Data(("BENCH " + $0 + "\n").utf8)) }
        var result = try bench.run()
        result.rows.insert(("First load and first text", String(format: "%.0f ms", load * 1000)), at: 1)
        if let b = before, let a = memoryFootprint() {
            result.rows.append(("Memory footprint", String(format: "%.1f MB before the model, %.1f MB after the bench", Double(b) / 1e6, Double(a) / 1e6)))
        }
        print(EmbedBench.table(result))
        return 0
    } catch {
        print("Bench error: \(error)")
        return 1
    }
    }
    exit(runBench())
}

// The model worker (follow-up R3): earshot-pa --embed-worker <model> --data <data folder>. The PA starts it with
// this program file. It reads only the model file, never a file of the owner. It stops when stdin closes, or
// after 5 minutes with no request.
if let i = args.firstIndex(of: "--embed-worker"), i + 1 < args.count {
    signal(SIGPIPE, SIG_IGN)
    let data = args.firstIndex(of: "--data").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    func runWorker() -> Int32 {
        guard let embedder = makeWorkerEmbedder(args[i + 1], folder: URL(fileURLWithPath: data ?? ".", isDirectory: true)) else {
            return 2
        }
        // The embedder is freed when this function returns, before the exit: a GPU model that is still loaded at
        // exit stops the program in the Metal teardown of llama.cpp.
        return EmbedWorker.run(embedder) {}
    }
    exit(runWorker())
}

// The bench of the phase 2 follow-up (R1, R2): earshot-pa --followup-bench <fixtures folder> --embedder <name>
// [--model <file.gguf>] [--gpu] [--by-name] [--explain | --names | --final <variant> [--needs n,k]] [--bakeoff <folder>] [--verbose] [--weights a,d,r,s,f,t,tmax,w,n,b].
if let i = args.firstIndex(of: "--followup-bench"), i + 1 < args.count {
    func value(_ flag: String) -> String? {
        args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }
    func runFollowUp() -> Int32 {
        do {
            let embedder = try makeEmbedder(value("--embedder") ?? "hash", allowAssetRequest: false, modelFile: value("--model"),
                                            gpu: args.contains("--gpu"))
            let bench = try FollowUpBench(folder: URL(fileURLWithPath: args[i + 1], isDirectory: true), embedder: embedder)
            bench.verbose = args.contains("--verbose")
            bench.byName = args.contains("--by-name")
            if let n = value("--needs")?.split(separator: ",").compactMap({ Int($0) }), n.count == 2 { bench.needs = (n[0], n[1]) }
            bench.bakeoff = value("--bakeoff").map { URL(fileURLWithPath: $0, isDirectory: true) }
            if let w = value("--weights")?.split(separator: ",").compactMap({ Float($0) }), w.count == 10 {
                var x = MainPointsV2.Weights()
                (x.amount, x.date, x.request, x.result, x.opening) = (w[0], w[1], w[2], w[3], w[4])
                (x.titleWord, x.titleMax, x.centralWords, x.centralNumbers, x.boilerplate) = (w[5], w[6], w[7], w[8], w[9])
                bench.weights = x
            }
            if args.contains("--explain") {
                try bench.explain()
            } else if args.contains("--names") {
                try bench.names()
            } else if let v = value("--final") {
                guard let variant = ProjectRuleV2.Variant.allCases.first(where: { "\($0)" == v }) else {
                    print("Unknown variant \(v). Use one of: \(ProjectRuleV2.Variant.allCases.map { "\($0)" })")
                    return 1
                }
                try bench.final(variant: variant)
            } else {
                try bench.development()
            }
            return 0
        } catch {
            print("Bench error: \(error)")
            return 1
        }
    }
    exit(runFollowUp())
}

// The bench of the page text (phase 4, section 8, E12): earshot-pa --page-bench <pages folder> [--corpus <phase 2
// fixtures folder>] [--embedder <name> [--model <file.gguf>] [--gpu]] [--final <a|b|c> [--heading] [--dev <folder>]].
// It prints counts and shares only, never a text of a page.
if let i = args.firstIndex(of: "--page-bench"), i + 1 < args.count {
    func value(_ flag: String) -> String? {
        args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }
    func runPages() -> Int32 {
        do {
            let embedder = try makeEmbedder(value("--embedder") ?? "hash", allowAssetRequest: false, modelFile: value("--model"),
                                            gpu: args.contains("--gpu"))
            let corpus = try value("--corpus").map { try BenchFixtures.load(URL(fileURLWithPath: $0, isDirectory: true)) }
            let bench = PageBench(folder: URL(fileURLWithPath: args[i + 1], isDirectory: true), corpus: corpus, embedder: embedder)
            if let v = value("--final") {
                guard let variant = MainText.Variant(rawValue: v) else { print("Unknown variant \(v). Use a, b or c."); return 1 }
                let dev = value("--dev").map { PageBench(folder: URL(fileURLWithPath: $0, isDirectory: true), corpus: nil, embedder: embedder) }
                try bench.final(variant: variant, headingFront: args.contains("--heading"), devPages: dev)
            } else {
                try bench.development()
            }
            return 0
        } catch {
            print("Bench error: \(error)")
            return 1
        }
    }
    exit(runPages())
}

// The bench of the request flags (phase 3, 8.5, E11): earshot-pa --flags-bench <mail fixtures folder>
// [--embedder <name> [--model <file.gguf>] [--gpu]] [--final <variant>:<threshold>]
// [--write-weights <file> --variant <A|B> --threshold <t>] [--analyze <set> --threshold <t>]
// [--items <set> --owner-names a,b --owner-addresses x@y] (dk's items: counts only).
if let i = args.firstIndex(of: "--flags-bench"), i + 1 < args.count {
    func value(_ flag: String) -> String? {
        args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }
    func runFlags() -> Int32 {
        do {
            let embedder = try value("--embedder").map {
                try makeEmbedder($0, allowAssetRequest: false, modelFile: value("--model"), gpu: args.contains("--gpu"))
            }
            let bench = FlagBench(folder: URL(fileURLWithPath: args[i + 1], isDirectory: true), embedder: embedder)
            if let names = value("--owner-names") { bench.owner = Set(names.lowercased().split(separator: ",").map(String.init)) }
            if let addrs = value("--owner-addresses") { bench.ownerAddresses = Set(addrs.lowercased().split(separator: ",").map(String.init)) }
            if let it = value("--items") {
                try bench.items(it)
            } else if let a = value("--analyze") {
                try bench.analyze(a, threshold: Double(value("--threshold") ?? "4") ?? 4)
            } else if let w = value("--write-weights") {
                try bench.writeWeights(URL(fileURLWithPath: w), variant: value("--variant") ?? "B",
                                       threshold: Double(value("--threshold") ?? "0.5") ?? 0.5)
            } else if let f = value("--final") {
                let parts = f.split(separator: ":")
                guard parts.count == 2, let t = Double(parts[1]) else { print("Use --final B:0.60."); return 1 }
                try bench.final(variant: String(parts[0]), threshold: t)
            } else {
                try bench.development()
            }
            return 0
        } catch {
            print("Bench error: \(error)")
            return 1
        }
    }
    exit(runFlags())
}

// The bench of the links by a rule (phase 3, 9.2): earshot-pa --events-bench <phase 2 fixtures folder>
// --events <events tsv> --embedder <name> [--model <file.gguf>] [--gpu] [--detail] [--final L1+L2].
if let i = args.firstIndex(of: "--events-bench"), i + 1 < args.count {
    func value(_ flag: String) -> String? {
        args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }
    func runEvents() -> Int32 {
        do {
            guard let events = value("--events") else { print("Say the events file with --events."); return 1 }
            let embedder = try makeEmbedder(value("--embedder") ?? "hash", allowAssetRequest: false, modelFile: value("--model"),
                                            gpu: args.contains("--gpu"))
            let bench = try EventBench(corpus: URL(fileURLWithPath: args[i + 1], isDirectory: true), embedder: embedder)
            let file = URL(fileURLWithPath: events)
            if args.contains("--mail-arrivals") {
                try bench.mailArrivals(file)
                return 0
            }
            if let f = value("--final") {
                guard let lines = EventLinker.Lines(label: f) else { print("Unknown lines \(f). Use for example L1+L2."); return 1 }
                try bench.final(file, lines: lines)
            } else {
                let show = (value("--show") ?? "").split(separator: " ").compactMap { EventLinker.Lines(label: String($0)) }
                try bench.development(file, detail: args.contains("--detail"), show: show)
            }
            return 0
        } catch {
            print("Bench error: \(error)")
            return 1
        }
    }
    exit(runEvents())
}

let env = ProcessInfo.processInfo.environment
let folder: URL
if let path = env["EARSHOT_PLUGIN_DATA"], !path.isEmpty {
    folder = URL(fileURLWithPath: path, isDirectory: true)
} else {
    folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/earshot/plugin-data/pa", isDirectory: true)
}

// A write to a worker that stopped must give an error, not stop the PA (follow-up R3).
signal(SIGPIPE, SIG_IGN)

/// One serial queue owns the engine and the store.
let queue = DispatchQueue(label: "earshot.pa.engine")
let output = StdoutOutput()
let engine = Engine(folder: folder, clock: SystemClock(), output: output, reminders: reminderStore(),
                    detector: SystemDateDetector(), textReader: makeTextReader())
// The reads of kept files run at background priority, one at a time, so that they do not slow a command
// (phase 2 build rule 6).
let backgroundQueue = DispatchQueue(label: "earshot.pa.background", qos: .utility)
// The watch on kept folders (phase 2, Q6).
#if canImport(CoreServices)
engine.folderWatcher = FSEventsWatcher()
#endif
// The model of the search by sense (phase 2, Q3). With no model file, the search uses keywords only.
engine.models = makeSearchModel(PASettings.load(folder.appendingPathComponent("settings.json")).settings.searchModel,
                                folder: folder)
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
// The calendar (phase 3, 9.1). The PA asks for access only if the source is on.
#if os(macOS)
if PASettings.load(folder.appendingPathComponent("settings.json")).settings.sources.calendar {
    let calendar = EventKitCalendar(ask: true) {
        queue.async {
            engine.readCalendar()
            scheduleCheck()
        }
    }
    queue.async {
        engine.calendarSource = calendar
        engine.readCalendar()
        scheduleCheck()
    }
}
// The mail (phase 3, 6.1). The PA reads only while Mail runs. It never starts Mail.
if PASettings.load(folder.appendingPathComponent("settings.json")).settings.sources.mail {
    let mail = AppleMail()
    queue.async { engine.mailSource = mail }
}
// The notes (phase 3, S6). The PA reads only while Notes runs. It never starts Notes.
if PASettings.load(folder.appendingPathComponent("settings.json")).settings.sources.notes {
    let notes = AppleNotes()
    queue.async { engine.notesSource = notes }
}
#endif
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

// Phase 3, S1: the probes, if the owner's test put the file probe-request in the data folder. They run off the
// command path. Apple events run on the main thread.
#if os(macOS)
DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { SourceProbe.runIfRequested(folder: folder) }
#endif

// The main run loop delivers the notifications of EventKit and of the system (wake, clock change).
RunLoop.main.run()
