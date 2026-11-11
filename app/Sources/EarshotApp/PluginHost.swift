import Darwin
import EarshotCore
import Foundation

// The plugin host (R-PL-1 to R-PL-5, docs/PLUGINS.md). earshot starts each approved plugin as a separate program
// and talks JSON lines with it over stdin and stdout. No network port is open. No plugin code runs inside earshot.

/// The hand-off as the command pipeline uses it. PluginHost is the real one. The tests give a fake.
protocol PluginHandOff: AnyObject {
    /// The leads of the approved plugins with no problems. The router uses them.
    var leads: [PluginLead] { get }
    /// The display name of a plugin.
    func name(of pluginID: String) -> String
    /// Sends the words to the plugin, and returns at once (R-PL-5). Nil if the words went out, else a short reason.
    /// `available` is the context that earshot can give. The host sends only the keys that the manifest names.
    func handOff(pluginID: String, lead: String, text: String, available: [String: String]) -> String?
    /// The targets with an `open` value of the approved plugins that run. The router uses them for "open <target>".
    var targetNames: [PluginTargetName] { get }
}

final class PluginHost: PluginHandOff, @unchecked Sendable {
    let catalog: PluginCatalog
    /// The folder for the data of each plugin: <store>/plugin-data/<id>/. An update of the plugin does not touch it.
    let dataFolder: URL
    /// An answer or an alert from a plugin. It comes on a background queue. It is text to show, never a command (R-PL-3).
    var onAnswer: ((PluginMessage, PluginManifest) -> Void)?
    /// The most starts of one plugin in `startWindow` seconds. After that, the plugin stays off until a reload.
    static let maxStarts = 3
    static let startWindow: TimeInterval = 60
    /// The wait before earshot starts a plugin again after it stopped.
    static let restartDelay: TimeInterval = 2

    private let lock = NSLock()
    private var entries: [PluginEntry] = []
    private var processes: [String: PluginProcess] = [:]
    private var starts: [String: [Date]] = [:]
    private var targetCache: [String: [PluginTarget]] = [:]

    init(store: Store) {
        catalog = PluginCatalog(store: store)
        dataFolder = store.folder.appendingPathComponent("plugin-data", isDirectory: true)
        // A write to a plugin that stopped must give an error, not stop earshot.
        signal(SIGPIPE, SIG_IGN)
    }

    /// Reads the plugins folder and the approvals again. Stops each plugin that is gone, changed or not approved,
    /// and starts each approved plugin that does not run. A plugin runs while earshot runs: it keeps its own clock
    /// for alerts.
    func reload() {
        let found = catalog.scan()
        lock.lock()
        let wanted = found.filter { $0.approved && $0.problems.isEmpty }
        let keep = Set(wanted.map(\.hash))
        // A plugin also stops if its program files changed since it started, so that "Read again" starts a new build.
        // The approval stays on the plugin.json hash.
        let stop = processes.filter { !keep.contains($0.value.hash) || $0.value.stamp != PluginProcess.stamp(of: $0.value.entry) }
        for id in stop.keys { processes[id] = nil; targetCache[id] = nil }
        entries = found
        starts = [:]
        lock.unlock()
        for p in stop.values { p.stop() }
        for entry in wanted { _ = running(entry) }
    }

    var all: [PluginEntry] { lock.lock(); defer { lock.unlock() }; return entries }

    var leads: [PluginLead] {
        all.filter { $0.approved && $0.problems.isEmpty }
            .flatMap { e in e.manifest.leads.map { PluginLead(pluginID: e.id, lead: $0) } }
    }

    func name(of pluginID: String) -> String { all.first { $0.id == pluginID }?.manifest.name ?? pluginID }

    /// The targets that the plugin gave last (contract part 3).
    func targets(of pluginID: String) -> [PluginTarget] { lock.lock(); defer { lock.unlock() }; return targetCache[pluginID] ?? [] }

    var targetNames: [PluginTargetName] {
        let approved = Set(all.filter { $0.approved && $0.problems.isEmpty }.map(\.id))
        lock.lock(); defer { lock.unlock() }
        return targetCache.filter { approved.contains($0.key) }.flatMap { id, targets in
            targets.compactMap { t in t.open.map { PluginTargetName(pluginID: id, name: t.name, open: $0) } }
        }
    }

    func handOff(pluginID: String, lead: String, text: String, available: [String: String]) -> String? {
        guard let entry = all.first(where: { $0.id == pluginID }), entry.approved, entry.problems.isEmpty else {
            return "the plugin \(pluginID) is not approved"
        }
        let process: PluginProcess
        switch running(entry) {
        case .success(let p): process = p
        case .failure(let why): return why.text
        }
        let context = available.filter { entry.manifest.context.contains($0.key) }
        process.send(.command(id: UUID().uuidString, lead: lead, text: text, context: context))
        return nil
    }

    /// Stops one plugin and starts it again, with a new start count (R-CT-2). It reads the plugins folder and the
    /// approvals first, so a plugin that is not approved now does not start. Nil if it runs again, else a reason.
    func restart(_ pluginID: String) -> String? {
        reload()
        guard let entry = all.first(where: { $0.id == pluginID }) else { return "there is no plugin \(pluginID)" }
        guard entry.approved else { return "the plugin \(pluginID) is not approved" }
        guard entry.problems.isEmpty else { return "the plugin \(pluginID) has problems: " + entry.problems.joined(separator: "; ") }
        lock.lock()
        let old = processes[pluginID]
        processes[pluginID] = nil
        targetCache[pluginID] = nil
        starts[pluginID] = nil
        lock.unlock()
        old?.stop()
        switch running(entry) {
        case .success: return nil
        case .failure(let why): return why.text
        }
    }

    /// The ids of the plugins that run now.
    var runningIDs: [String] {
        lock.lock(); defer { lock.unlock() }
        return processes.filter { $0.value.isRunning }.keys.sorted()
    }

    func stopAll() {
        lock.lock()
        let all = processes.values
        processes = [:]
        entries = []
        lock.unlock()
        for p in all { p.stop() }
    }

    struct StartError: Error { let text: String }

    /// The running process of the plugin. Starts it if it does not run, within the start limit.
    private func running(_ entry: PluginEntry) -> Result<PluginProcess, StartError> {
        lock.lock()
        defer { lock.unlock() }
        if let p = processes[entry.id], p.isRunning { return .success(p) }
        let now = Date()
        let recent = (starts[entry.id] ?? []).filter { now.timeIntervalSince($0) < Self.startWindow }
        guard recent.count < Self.maxStarts else {
            return .failure(StartError(text: "the plugin \(entry.manifest.name) stopped \(recent.count) times: it is off"))
        }
        starts[entry.id] = recent + [now]
        let data = dataFolder.appendingPathComponent(entry.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let manifest = entry.manifest
        let p = PluginProcess(entry: entry, dataFolder: data, onMessage: { [weak self] message in
            self?.received(message, from: manifest)
        }, onExit: { [weak self] process in
            self?.exited(process)
        })
        do { try p.start() } catch {
            return .failure(StartError(text: "the plugin \(manifest.name) did not start: \(error)"))
        }
        processes[entry.id] = p
        return .success(p)
    }

    /// A plugin stopped. If it is still approved and nothing replaced it, start it again after a short wait,
    /// within the start limit.
    /// It can come from inside `running` (a program that stopped at once), so it takes the lock on another queue.
    private func exited(_ process: PluginProcess) {
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.restartDelay) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let current = self.processes[process.entry.id] === process
            self.lock.unlock()
            guard current, let entry = self.all.first(where: { $0.hash == process.entry.hash }) else { return }
            _ = self.running(entry)
        }
    }

    private func received(_ message: PluginMessage, from manifest: PluginManifest) {
        switch message.type {
        case "targets":
            lock.lock()
            targetCache[manifest.id] = message.targets ?? []
            lock.unlock()
        case "answer":
            onAnswer?(message, manifest)
        default:
            break  // An unknown type is dropped: a newer plugin can talk to an older earshot.
        }
    }
}

/// One running plugin program, with its two pipes.
///
/// earshot starts the program with posix_spawn and "disclaims" it: macOS then treats the plugin as its own process
/// for the privacy permissions, not as a part of earshot. Without this, a child process gets the Microphone and
/// Accessibility permissions of earshot (R-PL-1). If macOS does not have the call, earshot does not start the plugin.
final class PluginProcess: @unchecked Sendable {
    let entry: PluginEntry
    var hash: String { entry.hash }
    /// The program files when the process started. See `stamp(of:)`.
    let stamp: String
    private let dataFolder: URL
    private let onMessage: (PluginMessage) -> Void
    private let onExit: (PluginProcess) -> Void
    private var pid: pid_t = 0
    private var input: FileHandle?
    private var output: FileHandle?
    private var exitSource: DispatchSourceProcess?
    private let stateLock = NSLock()
    private var alive = false
    /// Writes go on their own queue, so that a plugin that does not read cannot stop the command path (R-PL-5).
    private let writes = DispatchQueue(label: "earshot.plugin.write")
    private var buffer = Data()

    init(entry: PluginEntry, dataFolder: URL, onMessage: @escaping (PluginMessage) -> Void,
         onExit: @escaping (PluginProcess) -> Void) {
        self.entry = entry; self.dataFolder = dataFolder; self.onMessage = onMessage; self.onExit = onExit
        stamp = Self.stamp(of: entry)
    }

    /// The name, the size and the change date of the program and of each file directly in the plugin folder.
    /// A new build of the plugin changes it, also when plugin.json stays the same. The read is not recursive,
    /// so a large folder below the plugin folder does not slow it.
    static func stamp(of entry: PluginEntry) -> String {
        let fm = FileManager.default
        let first = entry.manifest.run.first ?? ""
        let program = first.hasPrefix("/") ? URL(fileURLWithPath: first) : entry.folder.appendingPathComponent(first)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let inFolder = (try? fm.contentsOfDirectory(at: entry.folder, includingPropertiesForKeys: keys)) ?? []
        var lines: [String] = []
        for file in [program.resolvingSymlinksInPath()] + inFolder.map({ $0.resolvingSymlinksInPath() }) {
            guard let v = try? file.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            let date = v.contentModificationDate?.timeIntervalSince1970 ?? 0
            lines.append("\(file.path) \(v.fileSize ?? 0) \(date)")
        }
        return Set(lines).sorted().joined(separator: "\n")
    }

    var isRunning: Bool { stateLock.lock(); defer { stateLock.unlock() }; return alive }

    struct SpawnError: Error, CustomStringConvertible {
        let description: String
    }

    /// The private call that makes the new process responsible for itself (libquarantine, macOS 10.14 and later).
    typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    static let disclaim: Disclaim? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim") else { return nil }
        return unsafeBitCast(symbol, to: Disclaim.self)
    }()

    /// The program path: a relative path starts at the plugin folder.
    var program: String {
        let first = entry.manifest.run[0]
        return first.hasPrefix("/") ? first : entry.folder.appendingPathComponent(first).path
    }

    /// The environment of the plugin: only these variables, no other part of earshot's environment.
    var environment: [String: String] {
        let env = ProcessInfo.processInfo.environment
        var vars = ["EARSHOT_PLUGIN_DATA": dataFolder.path, "EARSHOT_CONTRACT": String(PluginContract.version)]
        for key in ["PATH", "HOME", "LANG", "TMPDIR"] { vars[key] = env[key] }
        return vars
    }

    func start() throws {
        guard let disclaim = Self.disclaim else {
            throw SpawnError(description: "this macOS cannot start a program outside the permissions of earshot")
        }
        var toChild: [Int32] = [-1, -1], fromChild: [Int32] = [-1, -1]
        guard pipe(&toChild) == 0 else { throw SpawnError(description: "no pipe (\(errno))") }
        guard pipe(&fromChild) == 0 else {
            close(toChild[0]); close(toChild[1])
            throw SpawnError(description: "no pipe (\(errno))")
        }
        for fd in toChild + fromChild { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, toChild[0], 0)
        posix_spawn_file_actions_adddup2(&actions, fromChild[1], 1)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addchdir_np(&actions, entry.folder.path)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // Close every other file of earshot in the child, and give the child the default signal actions
        // (earshot ignores SIGPIPE).
        var defaults = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGPIPE)
        posix_spawnattr_setsigdefault(&attr, &defaults)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF))
        guard disclaim(&attr, 1) == 0 else {
            for fd in toChild + fromChild { close(fd) }
            throw SpawnError(description: "macOS refused to disclaim the plugin")
        }

        let args = [program] + entry.manifest.run.dropFirst()
        let env = environment.map { "\($0.key)=\($0.value)" }
        var argv = args.map { strdup($0) } + [nil]
        var envp = env.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var child: pid_t = 0
        let rc = posix_spawn(&child, program, &actions, &attr, &argv, &envp)
        close(toChild[0]); close(fromChild[1])
        guard rc == 0 else {
            close(toChild[1]); close(fromChild[0])
            throw SpawnError(description: String(cString: strerror(rc)))
        }

        pid = child
        stateLock.lock(); alive = true; stateLock.unlock()
        input = FileHandle(fileDescriptor: toChild[1], closeOnDealloc: true)
        let out = FileHandle(fileDescriptor: fromChild[0], closeOnDealloc: true)
        output = out
        out.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            self?.read(data)
        }
        let source = DispatchSource.makeProcessSource(identifier: child, eventMask: .exit, queue: .global())
        source.setEventHandler { [weak self] in
            var status: Int32 = 0
            _ = waitpid(child, &status, WNOHANG)
            self?.exited()
        }
        exitSource = source
        source.resume()
        // A program that stopped before the watch started gives no event. It waits as a zombie: reap it here.
        var status: Int32 = 0
        if waitpid(child, &status, WNOHANG) == child { exited() }
        send(.hello())
    }

    /// The program stopped. Runs once.
    private func exited() {
        stateLock.lock()
        let was = alive
        alive = false
        stateLock.unlock()
        guard was else { return }
        exitSource?.cancel()
        onExit(self)
    }

    func send(_ request: PluginRequest) {
        guard let handle = input, var line = try? JSONEncoder().encode(request) else { return }
        line.append(0x0A)
        writes.async { try? handle.write(contentsOf: line) }
    }

    /// Stops the plugin: SIGTERM, then the pipes close. A write that waits for a full pipe ends with an error.
    func stop() {
        output?.readabilityHandler = nil
        if isRunning, pid > 0 { kill(pid, SIGTERM) }
        let handle = input
        writes.async { try? handle?.close() }
    }

    /// Splits the output into lines. A line longer than the limit is dropped, with the rest of the buffer.
    private func read(_ data: Data) {
        buffer.append(data)
        while let end = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<end]
            buffer = Data(buffer[buffer.index(after: end)...])
            if let message = PluginMessage.parse(Data(line)) { onMessage(message) }
        }
        if buffer.count > PluginContract.maxLineBytes { buffer = Data() }
    }
}
