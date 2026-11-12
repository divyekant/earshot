import Foundation

/// The PA. One object owns the store, the settings and the answers. The program calls it from one serial queue
/// only, so the store has one writer.
public final class Engine {
    public let folder: URL
    public let clock: Clock
    public let output: Output
    public let reminders: ReminderStore?
    public let detector: TimeDetector?
    /// Reads the text of kept files (phase 2). Nil: the PA keeps references only.
    public let textReader: TextReader?
    public internal(set) var store: Store?
    /// index.sqlite: passages and numbers (phase 2).
    public internal(set) var index: IndexStore?
    var lastFileCheck: Date?
    /// The watch on kept folders (phase 2, Q6). Nil: no watch; the hourly file check still reads changed files.
    public var folderWatcher: FolderWatcher?
    /// The embedding model (phase 2, Q3). Nil: the search uses keywords only.
    public var models: ModelHost? {
        didSet {
            // The log gets the process id of each new worker, and each fault of the model (follow-up R3).
            models?.onLoad = { [weak self] m in
                let pid = (m as? WorkerEmbedder).map { String($0.pid) } ?? "none"
                self?.runLater(0) { [weak self] in
                    guard let self else { return }
                    self.log.write(self.clock.now, "model-loaded", ["worker": pid])
                }
            }
            models?.onFault = { [weak self] in
                self?.runLater(0) { [weak self] in
                    guard let self else { return }
                    self.log.write(self.clock.now, "model-fault")
                }
            }
        }
    }
    /// The batches of the index that failed 3 times in this run of the PA: "passage:<id>" or "item:<id>". The PA
    /// skips them until the next start (follow-up R3).
    var indexSkip = Set<String>()
    /// The count of failures of each batch, by the key of its first text.
    var indexTries: [String: Int] = [:]
    /// A job of the index runs in the background.
    var indexing = false
    /// The start and the count of texts of the current run of index jobs, for the line "index-done" in the log.
    var indexRun: (start: Date, texts: Int)?
    /// The numbers of the index in memory, while the model is loaded (build spec 7.6).
    var vectorCache: VectorCache?
    /// Runs a block at background priority, off the engine queue (phase 2 build rule 6). Tests run it at once.
    public var background: (@escaping () -> Void) -> Void = { block in block() }
    public internal(set) var settings = PASettings()
    /// Phase 3: the calendar (EventKit on the Mac, a fixture in tests). Nil: no calendar read.
    public var calendarSource: CalendarSource?
    var lastCalendarRead: Date?
    /// The title of each event at its last link by a rule. A new or a changed title gets new links.
    var ruleLinkTitles: [Int64: String] = [:]
    /// Phase 3, S4: the mail source, and the state of the mail read.
    public var mailSource: MailSource?
    let mailReader = SourceReader(name: "mail")
    var lastMailRead: Date?
    var mailFrontSince: Date?
    var mailReading = false
    /// Phase 3, S6: the notes source, and the state of the notes read.
    public var notesSource: NotesSource?
    let notesReader = SourceReader(name: "notes")
    var lastNotesRead: Date?
    var notesReading = false
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

    public init(folder: URL, clock: Clock, output: Output, reminders: ReminderStore? = nil, detector: TimeDetector? = nil,
                textReader: TextReader? = nil) {
        self.folder = folder
        self.textReader = textReader
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
            openIndex()
            checkFilesIfDue(force: true)
            startModelIndex()
            watchFolders()
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
        // Phase 3 (spec 7.2): a source that goes off loses what the PA kept from it, at once.
        if old.sources.calendar && !settings.sources.calendar { try? store?.forgetSource(.calendar) }
        if old.linkEvents && !settings.linkEvents {
            try? store?.db.run("DELETE FROM cal_event_link WHERE by = 'rule'")
            ruleLinkTitles = [:]
        }
        if old.sources.mail && !settings.sources.mail { try? store?.forgetSource(.mail) }
        if old.sources.notes && !settings.sources.notes { try? store?.forgetSource(.note); forgetNotes() }
        markPagesDirty()
    }

    /// The end: stdin closed.
    public func stop() {
        log.write(clock.now, "stop")
        // Free the model before exit (llama.cpp with Metal stops the program if a model is still loaded).
        models?.unload()
        store?.db.close()
        index?.db.close()
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
        case .pageText(let m):
            receivePageText(m)
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
        case .whatProjects: return whatProjects(id: id)
        case .finishProject: return finishProject(id: id, text: text)
        case .mainPoints: return mainPoints(id: id, text: text, context: context)
        case .keep: return keepFlag(id: id, text: text, context: context)
        case .whatIsNew: return whatIsNew(id: id)
        }
    }

    // MARK: - Changes

    /// An item is new or changed. The clock, the pages and the copy in Reminders act on it.
    func itemChanged(_ it: Item, old: Item?) {
        planAlerts(it, old: old)
        itemIndexChanged(it, old: old)
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
