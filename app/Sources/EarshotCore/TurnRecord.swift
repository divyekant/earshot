import Foundation

// The turn recorder (R-ON-1, R-ON-3, D-11, E7). For each always-on turn and each rejected wake, earshot keeps the
// numbers of the turn for 7 days, so that a wake or voice problem can run again in a test with no audio.
// It keeps no audio. The wake frames are encoder frames of the spotter model, as the templates in `voice.json`:
// earshot cannot play them back.

/// The encoder frames of the spotter around one template match, and the match score of each frame (E5, E7).
/// The wake listener gives it with a wake or a rejected wake. It is not audio.
public struct WakeTrace: Codable, Equatable, Sendable {
    /// The encoder frames, 40 ms each, as 16-bit floats. Nil if the frames are not kept.
    public var frames: WakeTemplate?
    /// The match score of each frame: the mean of the 2 best templates. Nil where no template fits yet.
    public var scores: [Double?]
    /// The index of the first frame, counted from the last reset of the listener. A low value means that the
    /// match came soon after a reset of the encoder.
    public var firstFrame: Int
    /// The first and the last frame of the match, as indexes in `scores`.
    public var matchStart: Int
    public var matchEnd: Int
    /// The wake limit of the score.
    public var limit: Double

    public init(frames: WakeTemplate?, scores: [Double?], firstFrame: Int, matchStart: Int, matchEnd: Int, limit: Double) {
        self.frames = frames; self.scores = scores; self.firstFrame = firstFrame
        self.matchStart = matchStart; self.matchEnd = matchEnd; self.limit = limit
    }
}

/// The numbers of one always-on turn or one rejected wake (E7). It holds no audio.
public struct TurnRecord: Codable, Equatable, Sendable {
    /// How the turn started.
    public enum Kind: String, Codable, Sendable {
        /// The wake phrase in the owner's voice opened the turn.
        case wake
        /// Speech in the follow-up window opened the turn.
        case followUp
        /// The wake phrase matched, but the voice of the phrase did not reach the gate. No turn started.
        case rejectedWake
    }

    public var id = UUID()
    public var at = Date()
    public var kind: Kind
    /// How the turn ended: "end", or the reason of the drop, for example "not the owner's voice (0.21)".
    public var outcome: String

    // The wake. Nil for a follow-up turn with no phrase.
    public var wakeVoice: Double?
    public var gate: Double?
    public var matchScore: Double?
    public var matchWorst: Double?
    /// The phrase came this far into a follow-up turn, in seconds.
    public var wakeInTurnAfter: Double?
    public var trace: WakeTrace?

    // The sound levels.
    /// The length of one level frame, in ms.
    public var levelFrameMs: Double
    /// The level of each frame in dB of full scale, from up to 3 s before the turn to its end. Nil for a frame that the
    /// detector did not hear, because earshot played a sound.
    public var levels: [Double?]
    /// The noise floor of the detector at the first level, in dB of full scale.
    public var floorDb: Double
    /// The index in `levels` of the first frame in the turn. For a rejected wake, the frame of the wake.
    public var turnStart: Int
    /// A wake turn: true if the owner spoke after the phrase before the wake, and the quiet time since then.
    public var openHeardSpeech: Bool?
    public var openQuietMs: Double?
    /// True if the turn used the long end silence of dictation.
    public var dictation: Bool

    // The end of the turn.
    public var checks: [TurnCheck]
    public var end: TurnEnd?
    public var voice: TurnVoice?

    // From the activity log of the turn: the same text as the log, not more.
    public var activityID: UUID?
    public var heard: String?
    public var intent: String?
    public var ok: Bool?
    public var note: String?

    public init(kind: Kind, outcome: String, levelFrameMs: Double, levels: [Double?], floorDb: Double, turnStart: Int,
                dictation: Bool = false, checks: [TurnCheck] = [], end: TurnEnd? = nil, voice: TurnVoice? = nil) {
        self.kind = kind; self.outcome = outcome; self.levelFrameMs = levelFrameMs; self.levels = levels
        self.floorDb = floorDb; self.turnStart = turnStart; self.dictation = dictation; self.checks = checks
        self.end = end; self.voice = voice
    }

    /// Adds the wake to the record.
    public mutating func add(wake: WakeHit, gate: Double, trace: WakeTrace?) {
        wakeVoice = wake.voiceScore; self.gate = gate; matchScore = wake.matchScore; matchWorst = wake.matchWorst
        wakeInTurnAfter = wake.inTurnAfterSeconds; self.trace = trace
    }

    /// Adds the activity record of the turn: the words and the result, as the log has them.
    public mutating func add(activity: ActivityRecord) {
        activityID = activity.id; heard = activity.heard; intent = activity.intent; ok = activity.ok
        note = activity.note
    }

    /// The record with no wake frames. The scores stay.
    public var withoutFrames: TurnRecord {
        var copy = self
        copy.trace?.frames = nil
        return copy
    }

    /// The value rounded for the file: levels to 0.1 dB, scores to 0.001. A value that is not finite becomes nil.
    public static func rounded(_ value: Double?, places: Double) -> Double? {
        guard let value, value.isFinite else { return nil }
        return (value * places).rounded() / places
    }
}

/// Keeps the turn records for `keepDays` days in the `turns` folder of the store folder: one JSON line for each
/// record, one file for each day (UTC). It keeps no audio (R-MD-1). It writes on its own queue.
public final class TurnStore: @unchecked Sendable {
    /// The folder in the store folder.
    public static let folderName = "turns"
    /// Records older than this go.
    public static let keepDays = 7
    /// After this many bytes in one day, the records of that day have no wake frames. Room sound can match the phrase
    /// every few seconds (live run 2026-11-03), and the frames are most of a record.
    public static let framesDayBytes = 40_000_000
    /// After this many bytes in one day, no more records that day.
    public static let maxDayBytes = 60_000_000
    /// The most records with wake frames in one hour. The scores of the others stay.
    public static let framesPerHour = 60

    public let folder: URL
    /// True if the records keep the wake frames.
    public let keepsFrames: Bool
    private let now: @Sendable () -> Date
    private let queue = DispatchQueue(label: "earshot.turns", qos: .utility)
    // Used only on `queue`.
    private var framesHour = ""
    private var framesInHour = 0
    private var prunedDay = ""

    public init(store: Store = Store(), keepsFrames: Bool, now: @escaping @Sendable () -> Date = { Date() }) {
        folder = store.folder.appendingPathComponent(Self.folderName, isDirectory: true)
        self.keepsFrames = keepsFrames
        self.now = now
    }

    /// Writes the record later, on the queue of the store.
    public func append(_ record: TurnRecord) {
        queue.async { [self] in try? write(record) }
    }

    /// Waits for the writes that started before.
    public func flush() { queue.sync {} }

    /// Deletes all records. The owner turned the recorder off.
    public func removeAll() {
        queue.sync { [self] in try? FileManager.default.removeItem(at: folder) }
    }

    /// The records of all kept days, oldest first. For the replay tests.
    public func all() -> [TurnRecord] {
        flush()
        return Self.read(folder: folder)
    }

    /// Reads the records in a turns folder, oldest first. A line that does not decode is left out.
    public static func read(folder: URL) -> [TurnRecord] {
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decoder = JSONDecoder()
        var out: [TurnRecord] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                if let record = try? decoder.decode(TurnRecord.self, from: Data(line.utf8)) { out.append(record) }
            }
        }
        return out
    }

    /// The file name of the day of a date: for example "2026-11-11.jsonl" (UTC).
    public static func fileName(for date: Date) -> String { day(date) + ".jsonl" }

    private static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func write(_ record: TurnRecord) throws {
        let date = now()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        prune(date)
        let url = folder.appendingPathComponent(Self.fileName(for: date))
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
        guard size < Self.maxDayBytes else { return }
        var record = record
        if record.trace?.frames != nil {
            if !keepsFrames || size >= Self.framesDayBytes || !takeFrameSlot(date) { record = record.withoutFrames }
        }
        var line = try JSONEncoder().encode(record)
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    /// True if this hour can have one more record with frames.
    private func takeFrameSlot(_ date: Date) -> Bool {
        let hour = String(Int(date.timeIntervalSince1970 / 3600))
        if hour != framesHour { framesHour = hour; framesInHour = 0 }
        guard framesInHour < Self.framesPerHour else { return false }
        framesInHour += 1
        return true
    }

    /// Deletes the files of days older than `keepDays`, one time each day.
    private func prune(_ date: Date) {
        let today = Self.day(date)
        guard today != prunedDay else { return }
        prunedDay = today
        let oldest = Self.day(date.addingTimeInterval(-Double(Self.keepDays - 1) * 86400))
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "jsonl" {
            // The names are dates, so the order of the text is the order of the days.
            if file.deletingPathExtension().lastPathComponent < oldest { try? FileManager.default.removeItem(at: file) }
        }
    }
}
