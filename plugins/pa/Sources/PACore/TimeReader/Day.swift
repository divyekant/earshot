import Foundation

/// One day of the calendar, with no clock time. The store keeps it as "2026-11-13".
public struct Day: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(_ year: Int, _ month: Int, _ day: Int) { self.year = year; self.month = month; self.day = day }

    public init(_ date: Date, _ cal: Calendar) {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(c.year!, c.month!, c.day!)
    }

    /// Reads "2026-11-13". Nil for another form.
    public init?(text: String) {
        let p = text.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        self.init(p[0], p[1], p[2])
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (a: Day, b: Day) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    /// The start of the day, or the clock time on the day.
    public func date(_ cal: Calendar, hour: Int = 0, minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    public func adding(days n: Int, _ cal: Calendar) -> Day {
        Day(cal.date(byAdding: .day, value: n, to: date(cal, hour: 12))!, cal)
    }

    /// 1 is Sunday, 7 is Saturday (the numbers of Calendar).
    public func weekday(_ cal: Calendar) -> Int { cal.component(.weekday, from: date(cal, hour: 12)) }

    /// The count of days from this day to the other day.
    public func days(to other: Day, _ cal: Calendar) -> Int {
        cal.dateComponents([.day], from: date(cal, hour: 12), to: other.date(cal, hour: 12)).day!
    }
}

/// A clock time of the day, in minutes after midnight.
public struct ClockTime: Hashable, Codable, Sendable, CustomStringConvertible {
    public var minutes: Int
    public init(_ hour: Int, _ minute: Int = 0) { minutes = hour * 60 + minute }
    public init?(text: String) {
        let p = text.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else { return nil }
        minutes = p[0] * 60 + p[1]
    }
    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }
    public var description: String { String(format: "%02d:%02d", hour, minute) }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let t = ClockTime(text: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not HH:MM: \(s)"))
        }
        self = t
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

/// The text forms of times and days on screen. Short, with no year: "today 17:00", "Fri 13 Nov".
public enum TimeText {
    static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "Wed 11 Nov 2026".
    public static func fullDay(_ d: Day, _ cal: Calendar) -> String {
        "\(weekdays[d.weekday(cal) - 1]) \(d.day) \(months[d.month - 1]) \(d.year)"
    }

    /// "20 Nov": the proposed day of a flag (phase 3, spec 8.6).
    public static func shortDay(_ d: Day) -> String { "\(d.day) \(months[d.month - 1])" }

    public static func day(_ d: Day, now: Date, _ cal: Calendar) -> String {
        let today = Day(now, cal)
        if d == today { return "today" }
        if d == today.adding(days: 1, cal) { return "tomorrow" }
        let base = "\(weekdays[d.weekday(cal) - 1]) \(d.day) \(months[d.month - 1])"
        return d.year == today.year ? base : base + " \(d.year)"
    }

    /// The clock time in the 12 or 24 hour style of the locale: "17:00" or "5:00 PM".
    public static func clock(_ date: Date, _ cal: Calendar, locale: Locale = Locale(identifier: "en_GB")) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = cal.timeZone
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: locale) ?? "HH:mm"
        return f.string(from: date)
    }

    public static func moment(_ date: Date, now: Date, _ cal: Calendar, locale: Locale = Locale(identifier: "en_GB")) -> String {
        day(Day(date, cal), now: now, cal) + " " + clock(date, cal, locale: locale)
    }
}
