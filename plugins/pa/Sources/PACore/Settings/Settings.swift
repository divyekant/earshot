import Foundation

/// What a right-time rule does when it applies (design, "Your settings").
public enum RuleMode: String, Codable, Sendable {
    /// An alert: a note with a sound, and a line in the Notification Center.
    case alert
    /// A line in the morning list and in "what is due". No interruption.
    case list
    /// Nothing.
    case off
}

/// The right-time rules. "nearEvent" and "newArrival" have no effect in phase 1 (they need the calendar and sources).
public struct RuleModes: Codable, Equatable, Sendable {
    /// Rule 1: a reminder has its time now.
    public var time: RuleMode = .alert
    /// Rule 1: a to-do has its due date today or tomorrow.
    public var due: RuleMode = .list
    /// Rule 4: an open to-do had no change for some days.
    public var silence: RuleMode = .list
    /// Rule 2 (phase 3).
    public var nearEvent: RuleMode = .alert
    /// Rule 3 (phase 2 and 3).
    public var newArrival: RuleMode = .list
    /// Phase 3: a request flag from a mail or a note (spec 8.6).
    /// Off by default: the request flags failed their go mark on the sealed holdout (E11, 2026-11-12).
    public var request: RuleMode = .off

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RuleModes()
        time = try c.decodeIfPresent(RuleMode.self, forKey: .time) ?? d.time
        due = try c.decodeIfPresent(RuleMode.self, forKey: .due) ?? d.due
        silence = try c.decodeIfPresent(RuleMode.self, forKey: .silence) ?? d.silence
        nearEvent = try c.decodeIfPresent(RuleMode.self, forKey: .nearEvent) ?? d.nearEvent
        newArrival = try c.decodeIfPresent(RuleMode.self, forKey: .newArrival) ?? d.newArrival
        request = try c.decodeIfPresent(RuleMode.self, forKey: .request) ?? d.request
    }
}

/// The value of one project for some rules, for example {"due": "alert"}. A rule that is not in it uses the
/// general value.
public struct ProjectRules: Codable, Equatable, Sendable {
    public var time: RuleMode?
    public var due: RuleMode?
    public var silence: RuleMode?
    public var nearEvent: RuleMode?
    public var newArrival: RuleMode?
    public var request: RuleMode?

    public init() {}
}

public struct TimeSpan: Codable, Equatable, Sendable {
    public var from: ClockTime
    public var to: ClockTime

    public init(from: ClockTime, to: ClockTime) { self.from = from; self.to = to }

    /// True if the clock time is in the span. A span can cross midnight (22:00 to 08:00).
    public func contains(_ t: ClockTime) -> Bool {
        if from.minutes == to.minutes { return false }
        if from.minutes < to.minutes { return t.minutes >= from.minutes && t.minutes < to.minutes }
        return t.minutes >= from.minutes || t.minutes < to.minutes
    }
}

public struct DayParts: Codable, Equatable, Sendable {
    public var morning = ClockTime(9, 0)
    public var noon = ClockTime(12, 0)
    public var afternoon = ClockTime(15, 0)
    public var evening = ClockTime(18, 0)
    public var tonight = ClockTime(20, 0)
    public var endOfDay = ClockTime(17, 0)

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DayParts()
        morning = try c.decodeIfPresent(ClockTime.self, forKey: .morning) ?? d.morning
        noon = try c.decodeIfPresent(ClockTime.self, forKey: .noon) ?? d.noon
        afternoon = try c.decodeIfPresent(ClockTime.self, forKey: .afternoon) ?? d.afternoon
        evening = try c.decodeIfPresent(ClockTime.self, forKey: .evening) ?? d.evening
        tonight = try c.decodeIfPresent(ClockTime.self, forKey: .tonight) ?? d.tonight
        endOfDay = try c.decodeIfPresent(ClockTime.self, forKey: .endOfDay) ?? d.endOfDay
    }
}

public struct ReminderSettings: Codable, Equatable, Sendable {
    /// The copy of open to-dos and reminders in Apple Reminders. If it changes to false, the PA removes its list.
    public var copy = true
    /// The name of the list in Apple Reminders.
    public var list = "earshot"
    /// "reminders": the Reminders app gives the alert of a copied reminder, and earshot does not.
    /// "earshot": earshot gives the alert, and the copy has no alarm.
    public var alertBy = "reminders"

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReminderSettings()
        copy = try c.decodeIfPresent(Bool.self, forKey: .copy) ?? d.copy
        list = try c.decodeIfPresent(String.self, forKey: .list) ?? d.list
        alertBy = try c.decodeIfPresent(String.self, forKey: .alertBy) ?? d.alertBy
    }
}

/// Phase 3: the sources that the PA reads. If a source is false, the PA does not read it and does not ask for its
/// permission. If it changes to false, the PA deletes what it kept from that source.
public struct SourceSwitches: Codable, Equatable, Sendable {
    public var calendar = true
    public var mail = true
    public var notes = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SourceSwitches()
        calendar = try c.decodeIfPresent(Bool.self, forKey: .calendar) ?? d.calendar
        mail = try c.decodeIfPresent(Bool.self, forKey: .mail) ?? d.mail
        notes = try c.decodeIfPresent(Bool.self, forKey: .notes) ?? d.notes
    }
}

/// Phase 3: the mail read (spec 6.1 and 7.2).
public struct MailSettings: Codable, Equatable, Sendable {
    /// The time between two reads while Mail runs.
    public var everyMinutes = 5
    /// At the first read, the PA looks at the mail of this count of days.
    public var firstDays = 3
    /// The most messages that the PA looks back at, at the first read or after a long pause.
    public var maxPerRead = 50
    /// The most messages in one read. The rest waits for the next read.
    public var batch = 10

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MailSettings()
        everyMinutes = try c.decodeIfPresent(Int.self, forKey: .everyMinutes) ?? d.everyMinutes
        firstDays = try c.decodeIfPresent(Int.self, forKey: .firstDays) ?? d.firstDays
        maxPerRead = try c.decodeIfPresent(Int.self, forKey: .maxPerRead) ?? d.maxPerRead
        batch = try c.decodeIfPresent(Int.self, forKey: .batch) ?? d.batch
    }
}

/// Phase 3: the notes read.
public struct NotesSettings: Codable, Equatable, Sendable {
    /// The time between two reads while Notes runs.
    public var everyMinutes = 15

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        everyMinutes = try c.decodeIfPresent(Int.self, forKey: .everyMinutes) ?? NotesSettings().everyMinutes
    }
}

/// Phase 3: the names and the addresses of the owner. If both lists are empty, the PA reads them from the Mail
/// accounts.
public struct OwnerSettings: Codable, Equatable, Sendable {
    public var names: [String] = []
    public var addresses: [String] = []

    public init() {}

    public init(names: [String], addresses: [String]) { self.names = names; self.addresses = addresses }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        names = try c.decodeIfPresent([String].self, forKey: .names) ?? []
        addresses = try c.decodeIfPresent([String].self, forKey: .addresses) ?? []
    }
}

/// The settings file, settings.json in the data folder. The PA writes it with the defaults at the first start,
/// so the PA works with no setup. A key that is not in the file gets its default. An unknown key has no effect.
public struct PASettings: Codable, Equatable, Sendable {
    /// The time of the morning list.
    public var morningTime = ClockTime(9, 0)
    /// An alert in this time waits for the morning list. Exception: a reminder with a clock time in this time.
    public var quietHours = TimeSpan(from: ClockTime(22, 0), to: ClockTime(8, 0))
    /// The most alerts in one hour. More alerts go into the next list.
    public var maxAlertsPerHour = 3
    /// A reminder with no answer in this count of minutes shows one more time.
    public var repeatAfterMinutes = 10
    /// "snooze" with no time moves the item by this count of minutes.
    public var defaultSnoozeMinutes = 10
    /// A clock time with no "am" or "pm" is the next such time in this span.
    public var bareHourWindow = TimeSpan(from: ClockTime(7, 0), to: ClockTime(23, 0))
    /// The clock times of "morning", "noon", "afternoon", "evening", "tonight" and "end of day".
    public var dayParts = DayParts()
    public var rules = RuleModes()
    /// Rule "silence": an open to-do with no change for this count of days.
    public var silenceDays = 7
    /// Rule "silence": an item that starts with "waiting for" and had no change for this count of days.
    public var waitingDays = 3
    /// The value of one project for some rules. The key is the project name in lower case.
    public var projects: [String: ProjectRules] = [:]
    public var reminders = ReminderSettings()
    /// The embedding model of the search by sense (phase 2, D-16): "gemma", "qwen3" or "none" (keywords only).
    /// The install script downloads the model file. A change takes effect at the next start of the PA.
    public var searchModel = "gemma"
    /// Project proposals for a capture with no project (8.1). On by default since project rule version 2 passed
    /// its holdout (follow-up R1: 20 proposals, 19 correct, 1 wrong).
    public var proposeProject = true
    /// Project proposals also from a project name in the capture. Off by default: a name in another sense
    /// ("the soup kitchen") gives a wrong proposal. "for <project>" is the sure way to name a project.
    public var proposeByName = false
    /// After "new project", the next captures go to it for this count of minutes (8.3). 0 switches it off.
    public var projectFocusMinutes = 5
    /// Phase 3: the sources that the PA reads.
    public var sources = SourceSwitches()
    /// Phase 3: the near-event alert comes this count of minutes before the start of an event.
    public var nearEventMinutes = 15
    /// Phase 3: if false, the PA makes no link by a rule between an event and the records. Links by the owner stay.
    public var linkEvents = true
    public var mail = MailSettings()
    public var notes = NotesSettings()
    /// Phase 3: if false, the request flags use the base formula only (spec 8.8).
    public var flagsLearn = true
    /// Phase 3: the names and addresses of the owner.
    public var owner = OwnerSettings()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PASettings()
        morningTime = try c.decodeIfPresent(ClockTime.self, forKey: .morningTime) ?? d.morningTime
        quietHours = try c.decodeIfPresent(TimeSpan.self, forKey: .quietHours) ?? d.quietHours
        maxAlertsPerHour = try c.decodeIfPresent(Int.self, forKey: .maxAlertsPerHour) ?? d.maxAlertsPerHour
        repeatAfterMinutes = try c.decodeIfPresent(Int.self, forKey: .repeatAfterMinutes) ?? d.repeatAfterMinutes
        defaultSnoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .defaultSnoozeMinutes) ?? d.defaultSnoozeMinutes
        bareHourWindow = try c.decodeIfPresent(TimeSpan.self, forKey: .bareHourWindow) ?? d.bareHourWindow
        dayParts = try c.decodeIfPresent(DayParts.self, forKey: .dayParts) ?? d.dayParts
        rules = try c.decodeIfPresent(RuleModes.self, forKey: .rules) ?? d.rules
        silenceDays = try c.decodeIfPresent(Int.self, forKey: .silenceDays) ?? d.silenceDays
        waitingDays = try c.decodeIfPresent(Int.self, forKey: .waitingDays) ?? d.waitingDays
        projects = try c.decodeIfPresent([String: ProjectRules].self, forKey: .projects) ?? d.projects
        reminders = try c.decodeIfPresent(ReminderSettings.self, forKey: .reminders) ?? d.reminders
        searchModel = try c.decodeIfPresent(String.self, forKey: .searchModel) ?? d.searchModel
        proposeProject = try c.decodeIfPresent(Bool.self, forKey: .proposeProject) ?? d.proposeProject
        proposeByName = try c.decodeIfPresent(Bool.self, forKey: .proposeByName) ?? d.proposeByName
        projectFocusMinutes = try c.decodeIfPresent(Int.self, forKey: .projectFocusMinutes) ?? d.projectFocusMinutes
        sources = try c.decodeIfPresent(SourceSwitches.self, forKey: .sources) ?? d.sources
        nearEventMinutes = try c.decodeIfPresent(Int.self, forKey: .nearEventMinutes) ?? d.nearEventMinutes
        linkEvents = try c.decodeIfPresent(Bool.self, forKey: .linkEvents) ?? d.linkEvents
        mail = try c.decodeIfPresent(MailSettings.self, forKey: .mail) ?? d.mail
        notes = try c.decodeIfPresent(NotesSettings.self, forKey: .notes) ?? d.notes
        flagsLearn = try c.decodeIfPresent(Bool.self, forKey: .flagsLearn) ?? d.flagsLearn
        owner = try c.decodeIfPresent(OwnerSettings.self, forKey: .owner) ?? d.owner
    }

    /// The rules for an item in a project: the value of the project if it has one, or the general value.
    public func rules(project: String?) -> RuleModes {
        var r = rules
        guard let project, let p = projects[project.lowercased()] else { return r }
        if let v = p.time { r.time = v }
        if let v = p.due { r.due = v }
        if let v = p.silence { r.silence = v }
        if let v = p.nearEvent { r.nearEvent = v }
        if let v = p.newArrival { r.newArrival = v }
        if let v = p.request { r.request = v }
        return r
    }

    public static let errorNote = "The PA settings file has an error. The PA uses the defaults."

    /// Reads the file. If the file does not exist, writes it with the defaults. If the file has an error, gives the
    /// defaults and the error note. The PA never stops for a bad settings file.
    public static func load(_ url: URL) -> (settings: PASettings, problem: String?) {
        if !FileManager.default.fileExists(atPath: url.path) {
            let s = PASettings()
            try? s.write(url)
            return (s, nil)
        }
        do {
            let data = try Data(contentsOf: url)
            return (try JSONDecoder().decode(PASettings.self, from: data), nil)
        } catch {
            return (PASettings(), errorNote)
        }
    }

    public func write(_ url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
