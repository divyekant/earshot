import Foundation

/// The PA. One object owns the store, the settings and the answers. The program calls it from one serial queue
/// only, so the store has one writer.
public final class Engine {
    public let folder: URL
    public let clock: Clock
    public let output: Output
    public let reminders: ReminderStore?
    public let detector: TimeDetector?
    public internal(set) var store: Store?
    public internal(set) var settings = PASettings()
    let log: PALog
    /// A note for the next answer, for example after a new store started.
    var pendingNotice: String?
    var settingsStamp: Date?
    var lastCapture: LastCapture?
    var helloDone = false
    var pagesDirty = true
    var pagesWrittenAt: Date?
    var lastPull: Date?
    /// Runs a block on the queue of the engine after some seconds. The program sets it to the engine queue.
    /// Tests run the block at once.
    public var runLater: (TimeInterval, @escaping () -> Void) -> Void = { _, block in block() }
    var startedAt: Date?

    public var storeURL: URL { folder.appendingPathComponent("pa.sqlite") }
    public var settingsURL: URL { folder.appendingPathComponent("settings.json") }
    public var pagesFolder: URL { folder.appendingPathComponent("pages", isDirectory: true) }
    public var backupsFolder: URL { folder.appendingPathComponent("backups", isDirectory: true) }

    public init(folder: URL, clock: Clock, output: Output, reminders: ReminderStore? = nil, detector: TimeDetector? = nil) {
        self.folder = folder
        self.clock = clock
        self.output = output
        self.reminders = reminders
        self.detector = detector
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        log = PALog(url: folder.appendingPathComponent("pa.log"))
    }

    /// Opens the store and reads the settings. Call it one time, before the first message.
    public func start() {
        let now = clock.now
        startedAt = now
        log.write(now, "start")
        loadSettings(announce: true)
        do {
            let s = try Store(url: storeURL, now: now)
            store = s
            if s.recoveredFrom != nil {
                pendingNotice = "The PA store had an error. A new store started. The old file is kept."
                log.write(now, "store-recovered")
                s.log("store-recovered", .store, nil, at: now)
            }
            log.write(now, "store-open", ["search": s.searchKind.rawValue])
            saveSpares()
        } catch {
            log.write(now, "store-failed")
        }
    }

    /// Reads settings.json. Sends the error note one time if the file has an error.
    func loadSettings(announce: Bool) {
        let (s, problem) = PASettings.load(settingsURL)
        settings = s
        settingsStamp = (try? FileManager.default.attributesOfItem(atPath: settingsURL.path))?[.modificationDate] as? Date
        if let problem, announce { output.send(.note(nil, problem)) }
    }

    /// Reads settings.json again if the file changed. Gives true if it changed.
    @discardableResult
    public func reloadSettingsIfChanged() -> Bool {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: settingsURL.path))?[.modificationDate] as? Date
        guard stamp != settingsStamp else { return false }
        let old = settings
        loadSettings(announce: true)
        log.write(clock.now, "settings-read")
        settingsChanged(from: old)
        return true
    }

    /// The PA got a new settings file. Later packages act on it (the clock, the copy in Reminders).
    func settingsChanged(from old: PASettings) {
        if old.reminders.copy && !settings.reminders.copy { stopMirror() }
        if !old.reminders.copy && settings.reminders.copy { startMirror() }
        if old.reminders.list != settings.reminders.list || old.reminders.alertBy != settings.reminders.alertBy {
            // A new list name or alert owner: copy all again into the list of the new name.
            try? store?.setMeta(listIDKey, nil)
            _ = try? store?.db.run("DELETE FROM mirror")
            syncAll()
        }
        markPagesDirty()
    }

    /// The end: stdin closed.
    public func stop() {
        log.write(clock.now, "stop")
        store?.db.close()
    }

    // MARK: - Messages

    /// Reads one line from earshot. A line that is not a message is dropped. The PA never stops for bad input.
    public func receive(_ line: Data) {
        guard let msg = Incoming.parse(line) else {
            log.write(clock.now, "bad-line", ["bytes": String(line.count)])
            return
        }
        handle(msg)
    }

    public func handle(_ msg: Incoming) {
        switch msg {
        case .hello(let contract):
            log.write(clock.now, "hello", ["contract": String(contract)])
            hello()
        case .command(let id, let lead, let text, let context):
            let start = Date()
            let answer = command(id: id, lead: lead, text: text, context: context)
            output.send(answer)
            flushPages()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            log.write(clock.now, "command", ["lead": PACommand.from(lead: lead)?.rawValue ?? "unknown",
                                             "words": String(text.split(separator: " ").count), "ms": String(ms)])
        case .unknown(let type):
            log.write(clock.now, "unknown-type", ["chars": String(type.count)])
        }
    }

    /// After hello: the targets, and the question for Reminders.
    func hello() {
        afterHello()
    }

    /// Later packages add the targets, the missed list and the morning list here.
    func afterHello() {
        if !helloDone {
            helloDone = true
            missedList(at: startedAt ?? clock.now)
        }
        sendTargets()
        flushPages(force: true)
        tick()
        startMirror()
    }

    /// One command. Gives exactly one answer with `re`.
    public func command(id: String, lead: String, text: String, context: [String: String]) -> Outgoing {
        let answer: Outgoing
        if store == nil {
            answer = .note(id, "The PA store does not open. Nothing saved.")
        } else if let cmd = PACommand.from(lead: lead) {
            answer = run(cmd, id: id, text: text, context: context)
        } else {
            answer = .note(id, "The PA does not know this command.")
        }
        guard let notice = pendingNotice else { return answer }
        pendingNotice = nil
        store?.clearRecovered()
        if case .answer(let re, let kind, let t, let items) = answer {
            return .answer(re: re, kind: kind, text: notice + " " + t, items: items)
        }
        return answer
    }

    func run(_ cmd: PACommand, id: String, text: String, context: [String: String]) -> Outgoing {
        switch cmd {
        case .remindMe, .todo, .note: return capture(cmd, id: id, text: text, context: context)
        case .keepThis: return keep(id: id, text: text, context: context)
        case .newProject: return newProject(id: id, text: text)
        case .whatIsDue: return whatIsDue(id: id)
        case .whatAbout: return whatAbout(id: id, text: text)
        case .whereIs: return whereIs(id: id, text: text)
        case .done: return done(id: id, text: text)
        case .snooze: return snooze(id: id, text: text)
        case .drop: return drop(id: id, text: text)
        case .move: return move(id: id, text: text)
        case .quiet: return quiet(id: id, text: text)
        }
    }

    // MARK: - Changes

    /// An item is new or changed. The clock, the pages and the copy in Reminders act on it.
    func itemChanged(_ it: Item, old: Item?) {
        planAlerts(it, old: old)
        markPagesDirty()
        push(it)
    }

    /// A document is new or changed.
    func docsChanged() { markPagesDirty() }

    /// A project is new or changed. earshot gets the new targets.
    func projectsChanged() {
        markPagesDirty()
        sendTargets()
    }
}
