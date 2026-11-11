import Foundation

/// What the time words of a capture mean.
public enum TimeKind: String, Sendable {
    /// A reminder time. The alert comes at this time.
    case remind
    /// A due date.
    case due
    /// No time, or a time that the reader cannot make into a date.
    case none
}

/// The time words of a capture, as the reader found them. Code makes the date from them (design, "Capture rules":
/// the due date score went from 0.46 to 0.91 when code made the date).
public struct TimeReading: Equatable, Sendable {
    public var kind: TimeKind = .none
    /// The time. For a day with no clock time: the morning time of a reminder, or nil.
    public var at: Date?
    /// The day of the time, or the due day.
    public var day: Day?
    /// True if the owner said a clock time.
    public var hasClock = false
    /// The words with the time phrase cut, if the phrase was at the start or at the end. Else all the words.
    public var rest: String
    /// True if the words have time words that the reader cannot read. Then the kind is `none`.
    public var unsure = false

    public init(rest: String) { self.rest = rest }
}

/// Reads spoken time phrases with fixed rules. No model. If the reader is not sure, it gives no time: a wrong time
/// is worse than no time, because the PA saves the words in all cases (design, "If the PA is not sure").
///
/// Rules (design, "Time rules"):
/// - "at 5" with no "am" or "pm" is the next 5 o'clock between 07:00 and 23:00.
/// - A day with no clock time stays a day. The capture rules make it the time of the morning list.
/// - "in 20 minutes" counts from now.
/// - "Friday", "this Friday" and "next Friday" are the first Friday after today. The note shows the date.
/// - "before Friday" is the day before Friday.
public struct TimeReader: Sendable {
    public var calendar: Calendar
    public var parts: DayParts
    /// The window for a clock time with no "am" or "pm".
    public var window: TimeSpan

    public init(calendar: Calendar, parts: DayParts = DayParts(),
                window: TimeSpan = TimeSpan(from: ClockTime(7, 0), to: ClockTime(23, 0))) {
        self.calendar = calendar
        self.parts = parts
        self.window = window
    }

    public init(calendar: Calendar, settings: PASettings) {
        self.init(calendar: calendar, parts: settings.dayParts, window: settings.bareHourWindow)
    }

    // MARK: - Words

    struct Tok {
        var w: String
        /// The index of the source word in the text.
        var src: Int
    }

    static let numberWords: [String: Int] = [
        "zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40,
        "fifty": 50,
    ]
    static let ordinalWords: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8,
        "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
        "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19, "twentieth": 20,
        "thirtieth": 30,
    ]
    static let weekdays: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
        "sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7,
    ]
    static let months: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8,
        "september": 9, "october": 10, "november": 11, "december": 12, "jan": 1, "feb": 2, "mar": 3, "apr": 4,
        "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12,
    ]
    /// Month names that are also common words. They are a month only next to a day number.
    static let weakMonths: Set<String> = ["may", "march", "mar", "jan", "sat", "sun", "wed", "mon"]

    /// Splits the text into words, and the words into parts: "5pm" is "5" and "pm", "p.m." is "pm",
    /// "20th" is "#20", "twenty five" is "25".
    static func tokens(_ words: [String]) -> [Tok] {
        var out: [Tok] = []
        for (i, raw) in words.enumerated() {
            var w = raw.lowercased()
            w = w.replacingOccurrences(of: "\u{2019}", with: "'")
            if w == "p.m." || w == "p.m" || w == "p.m.," { w = "pm" }
            if w == "a.m." || w == "a.m" || w == "a.m.," { w = "am" }
            w = w.trimmingCharacters(in: CharacterSet(charactersIn: ",.!?;\"()[]"))
            if w == "o'clock" || w == "oclock" { out.append(Tok(w: "oclock", src: i)); continue }
            w = w.replacingOccurrences(of: "'s", with: "")
            if w.isEmpty { continue }
            // "5pm", "5:30pm", "11am"
            for suffix in ["pm", "am", "p.m.", "a.m.", "p.m", "a.m"] where w.hasSuffix(suffix) && w.count > suffix.count {
                let head = String(w.dropLast(suffix.count))
                if head.allSatisfy({ $0.isNumber || $0 == ":" }) {
                    out.append(Tok(w: head, src: i))
                    w = suffix.hasPrefix("p") ? "pm" : "am"
                }
                break
            }
            // "20th", "1st", "2nd", "3rd"
            for suffix in ["st", "nd", "rd", "th"] where w.hasSuffix(suffix) && w.count > suffix.count {
                let head = String(w.dropLast(2))
                if let n = Int(head), (1...31).contains(n) { w = "#\(n)" }
                break
            }
            if let n = ordinalWords[w] { w = "#\(n)" }
            if let n = numberWords[w] { w = String(n) }
            // "twenty-five", "twenty-first"
            if w.contains("-") {
                let p = w.split(separator: "-").map(String.init)
                if p.count == 2, let tens = numberWords[p[0]], tens >= 20 {
                    if let one = numberWords[p[1]], one < 10 { w = String(tens + one) }
                    else if let one = ordinalWords[p[1]], one < 10 { w = "#\(tens + one)" }
                }
            }
            out.append(Tok(w: w, src: i))
        }
        // "twenty five" is 25, "twenty first" is #21.
        var merged: [Tok] = []
        for t in out {
            if let last = merged.last, let tens = Int(last.w), [20, 30, 40, 50].contains(tens),
               let one = Int(t.w), (1...9).contains(one), last.src + 1 == t.src || last.src == t.src {
                merged[merged.count - 1].w = String(tens + one)
                continue
            }
            if let last = merged.last, let tens = Int(last.w), [20, 30].contains(tens), t.w.hasPrefix("#"),
               let one = Int(t.w.dropFirst()), (1...9).contains(one) {
                merged[merged.count - 1].w = "#\(tens + one)"
                continue
            }
            merged.append(t)
        }
        return merged
    }

    // MARK: - Parts

    enum Period { case morning, afternoon, evening, night }

    struct Clock: Equatable {
        var hour: Int
        var minute: Int
        /// True for "pm", false for "am", nil if the words do not say.
        var pm: Bool?

        /// A clock time from the settings: it has no doubt about am or pm.
        static func exact(_ t: ClockTime) -> Clock {
            Clock(hour: t.hour, minute: t.minute, pm: t.hour > 12 ? nil : (t.hour == 12 ? true : false))
        }
    }

    enum DayWord {
        case today, tomorrow, plusDays(Int), weekday(Int, next: Bool), date(month: Int?, day: Int)
        case nextWeek, weekend(next: Bool), endOfWeek, endOfMonth, nextMonth
    }

    enum Part {
        case minutes(Int)
        case days(Int)
        case clock(Clock)
        case day(DayWord)
        case period(Period)
        case midnight
        /// "end of day": the end-of-day time of the settings.
        case endOfDay
    }

    struct Match {
        var range: Range<Int>
        var parts: [Part]
        var due = false
        var before = false
    }

    static let duePreps: Set<String> = ["by", "before", "due", "until", "till", "til", "untill"]
    static let dayPreps: Set<String> = ["on", "for", "this", "coming", "the"]
    static let clockPreps: Set<String> = ["at", "around", "about", "@"]

    func num(_ t: [Tok], _ i: Int) -> Int? { i < t.count ? Int(t[i].w) : nil }
    func word(_ t: [Tok], _ i: Int) -> String { i < t.count ? t[i].w : "" }
    func ordinal(_ t: [Tok], _ i: Int) -> Int? {
        let w = word(t, i)
        guard w.hasPrefix("#") else { return nil }
        return Int(w.dropFirst())
    }

    /// "in 20 minutes", "in an hour", "in half an hour", "in 2 days", "20 minutes from now".
    func relative(_ t: [Tok], _ i: Int) -> Match? {
        var j = i
        let lead = ["in", "after", "within"].contains(word(t, j))
        if lead { j += 1 }
        var amount: Double?
        if word(t, j) == "half", ["an", "a"].contains(word(t, j + 1)), ["hour", "hr"].contains(word(t, j + 2)) {
            return Match(range: i..<(j + 3), parts: [.minutes(30)])
        }
        if word(t, j) == "half", ["hour", "hr"].contains(word(t, j + 1)) {
            return Match(range: i..<(j + 2), parts: [.minutes(30)])
        }
        if ["a", "an"].contains(word(t, j)) {
            if ["couple", "few"].contains(word(t, j + 1)) { return nil }
            amount = 1; j += 1
        } else if word(t, j) == "couple", word(t, j + 1) == "of" {
            amount = 2; j += 2
        } else if let n = num(t, j) {
            amount = Double(n); j += 1
        } else if let d = Double(word(t, j)) {
            amount = d; j += 1
        }
        guard var amount else { return nil }
        // "1 and a half hours", "an hour and a half"
        if word(t, j) == "and", word(t, j + 1) == "a", word(t, j + 2) == "half" { amount += 0.5; j += 3 }
        let unit = word(t, j)
        var minutes: Double?
        var days: Int?
        switch unit {
        case "minute", "minutes", "min", "mins": minutes = amount
        case "hour", "hours", "hr", "hrs": minutes = amount * 60
        case "day", "days": days = Int(amount)
        case "week", "weeks": days = Int(amount) * 7
        default: return nil
        }
        j += 1
        if word(t, j) == "and", word(t, j + 1) == "a", word(t, j + 2) == "half", unit.hasPrefix("h") {
            minutes = (minutes ?? 0) + 30; j += 3
        }
        var trail = false
        if word(t, j) == "from", word(t, j + 1) == "now" { j += 2; trail = true }
        else if word(t, j) == "later" { j += 1; trail = true }
        guard lead || trail else { return nil }
        if let minutes { return Match(range: i..<j, parts: [.minutes(Int(minutes.rounded()))]) }
        if let days, Double(days) == (unit.hasPrefix("w") ? amount * 7 : amount) { return Match(range: i..<j, parts: [.days(days)]) }
        return nil
    }

    /// The words after a clock time: "am", "pm", "o'clock", "in the morning", "at night", "sharp".
    func clockTail(_ t: [Tok], _ j: inout Int, _ c: inout Clock) -> Bool {
        var said = false
        switch word(t, j) {
        case "am": c.pm = false; j += 1; said = true
        case "pm": c.pm = true; j += 1; said = true
        case "oclock": j += 1; said = true
            if word(t, j) == "am" { c.pm = false; j += 1 } else if word(t, j) == "pm" { c.pm = true; j += 1 }
        default: break
        }
        if word(t, j) == "in", word(t, j + 1) == "the" {
            switch word(t, j + 2) {
            case "morning": c.pm = false; j += 3; said = true
            case "afternoon", "evening": c.pm = true; j += 3; said = true
            default: break
            }
        } else if word(t, j) == "at", word(t, j + 1) == "night" { c.pm = true; j += 2; said = true }
        if word(t, j) == "sharp" { j += 1 }
        return said
    }

    /// "at 5", "5pm", "at 5:30", "at half past 5", "at quarter to 6", "17:00", "at noon", "at 5 30".
    func clock(_ t: [Tok], _ i: Int) -> Match? {
        var j = i
        var due = false, before = false
        let w0 = word(t, j)
        var prep = false
        if Self.clockPreps.contains(w0) { prep = true; j += 1 }
        else if Self.duePreps.contains(w0) { prep = true; due = true; before = w0 == "before"; j += 1 }
        if word(t, j) == "noon" || word(t, j) == "midday" {
            return Match(range: i..<(j + 1), parts: [.clock(Clock.exact(parts.noon))], due: due)
        }
        if word(t, j) == "12", word(t, j + 1) == "noon" {
            return Match(range: i..<(j + 2), parts: [.clock(Clock(hour: 12, minute: 0, pm: true))], due: due)
        }
        if word(t, j) == "midnight" { return Match(range: i..<(j + 1), parts: [.midnight], due: due) }
        // "half past 5", "quarter past 5", "quarter to 6", "10 past 5", "20 to 6"
        var c: Clock?
        if ["half", "quarter", "a"].contains(word(t, j)) || num(t, j) != nil {
            var k = j
            var m: Int?
            if word(t, k) == "half" { m = 30; k += 1 }
            else if word(t, k) == "quarter" { m = 15; k += 1 }
            else if word(t, k) == "a", word(t, k + 1) == "quarter" { m = 15; k += 2 }
            else if let n = num(t, k), n < 60, ["past", "after", "to", "before", "till"].contains(word(t, k + 1))
                        || (["minutes", "mins"].contains(word(t, k + 1)) && ["past", "to"].contains(word(t, k + 2))) {
                m = n; k += 1
                if ["minutes", "mins"].contains(word(t, k)) { k += 1 }
            }
            if let m, ["past", "after", "to", "before", "till"].contains(word(t, k)), let h = num(t, k + 1), (1...12).contains(h) {
                let to = ["to", "before", "till"].contains(word(t, k))
                c = to ? Clock(hour: h == 1 ? 12 : h - 1, minute: 60 - m, pm: nil) : Clock(hour: h, minute: m, pm: nil)
                j = k + 2
                prep = true
            }
        }
        if c == nil {
            let w = word(t, j)
            if w.contains(":") {
                let p = w.split(separator: ":").compactMap { Int($0) }
                guard p.count == 2, (0...23).contains(p[0]), (0...59).contains(p[1]) else { return nil }
                c = Clock(hour: p[0], minute: p[1], pm: p[0] >= 13 ? true : nil)
                // "08:15" with a leading zero is a 24-hour time.
                if p[0] == 0 || (w.hasPrefix("0") && p[0] < 12) { c!.pm = false }
                j += 1
                prep = true
            } else if w.count == 4, let n = Int(w), prep, n / 100 <= 23, n % 100 <= 59 {
                // "at 1730"
                c = Clock(hour: n / 100, minute: n % 100, pm: n / 100 >= 13 ? true : nil)
                j += 1
            } else if let h = Int(w), (0...23).contains(h), w.count <= 2 {
                c = Clock(hour: h, minute: 0, pm: h >= 13 ? true : (h == 0 ? false : nil))
                j += 1
                // "at 5 30", "at 5 15"
                if let m = num(t, j), word(t, j).count == 2, (0...59).contains(m), h <= 12,
                   prep || ["am", "pm"].contains(word(t, j + 1)) {
                    c!.minute = m; j += 1
                }
            } else {
                return nil
            }
        }
        guard var clock = c else { return nil }
        let said = clockTail(t, &j, &clock)
        // A bare number is a time only after "at" or with "am", "pm" or "o'clock". "by 5" also needs one of them,
        // or the end of the words.
        if !said {
            if !prep { return nil }
            if due && j < t.count && !isTimeWord(word(t, j)) { return nil }
        }
        if clock.pm == true && clock.hour > 12 { clock.pm = nil }
        if clock.hour > 12 && clock.pm == false { return nil }
        return Match(range: i..<j, parts: [.clock(clock)], due: due, before: before)
    }

    func isTimeWord(_ w: String) -> Bool {
        ["today", "tonight", "tomorrow", "tmrw", "on", "this", "next"].contains(w) || Self.weekdays[w] != nil
    }

    /// "today", "tomorrow", "on Friday", "next Friday", "by the 20th", "on 20 November", "next week",
    /// "tomorrow morning", "this evening", "tonight".
    func day(_ t: [Tok], _ i: Int) -> Match? {
        var j = i
        var due = false, before = false
        if Self.duePreps.contains(word(t, j)) {
            due = true; before = word(t, j) == "before"; j += 1
            if word(t, j) == "on" { j += 1 }
        } else if word(t, j) == "on" || word(t, j) == "for" {
            j += 1
        }
        var next = false, this = false
        switch word(t, j) {
        case "next": next = true; j += 1
        case "this", "coming": this = true; j += 1
        case "the":
            if word(t, j + 1) == "coming" { this = true; j += 2 }
            else if word(t, j + 1) == "next" { next = true; j += 2 }
        default: break
        }
        let start = j
        var parts: [Part] = []
        let w = word(t, j)
        switch w {
        case "today" where !next && !this: parts = [.day(.today)]; j += 1
        case "tonight" where !next && !this: parts = [.day(.today), .period(.night)]; j += 1
        case "tomorrow", "tmrw", "tomorow":
            parts = [.day(.tomorrow)]; j += 1
        case "morning" where this: parts = [.day(.today), .period(.morning)]; j += 1
        case "afternoon" where this: parts = [.day(.today), .period(.afternoon)]; j += 1
        case "evening" where this: parts = [.day(.today), .period(.evening)]; j += 1
        case "week" where next: parts = [.day(.nextWeek)]; j += 1
        case "week" where this: parts = [.day(.endOfWeek)]; j += 1
        case "weekend": parts = [.day(.weekend(next: next))]; j += 1
        case "month" where next: parts = [.day(.nextMonth)]; j += 1
        case "month" where this: parts = [.day(.endOfMonth)]; j += 1
        case "day" where word(t, j + 1) == "after" && word(t, j + 2) == "tomorrow":
            parts = [.day(.plusDays(2))]; j += 3
        case "end", "eod":
            var k = j + (w == "eod" ? 1 : 1)
            if w == "end" {
                if word(t, k) == "of" { k += 1 }
                if word(t, k) == "the" { k += 1 }
                switch word(t, k) {
                case "day": parts = [.day(.today), .endOfDay]; k += 1
                case "week": parts = [.day(.endOfWeek)]; k += 1
                case "month": parts = [.day(.endOfMonth)]; k += 1
                default: return nil
                }
            } else {
                parts = [.day(.today), .endOfDay]
            }
            j = k
        default:
            if let wd = Self.weekdays[w], w.count > 3 || !Self.weakMonths.contains(w) {
                parts = [.day(.weekday(wd, next: next))]; j += 1
                // "Friday the 13th", "Friday 13 November": the date wins.
                var k = j
                if word(t, k) == "the" { k += 1 }
                if let d = dateWords(t, k) { parts = [.day(d.0)]; j = d.1 }
            } else if !next, let d = dateWords(t, j) {
                parts = [.day(d.0)]; j = d.1
            } else if w == "the", !next, let d = dateWords(t, j + 1) {
                parts = [.day(d.0)]; j = d.1
            } else {
                return nil
            }
        }
        guard !parts.isEmpty, j > start else { return nil }
        // "tomorrow morning", "Friday evening", "tomorrow at night", "tomorrow night"
        var k = j
        if word(t, k) == "in", word(t, k + 1) == "the" { k += 2 }
        else if word(t, k) == "at", word(t, k + 1) == "night" { k += 1 }
        switch word(t, k) {
        case "morning": parts.append(.period(.morning)); j = k + 1
        case "afternoon": parts.append(.period(.afternoon)); j = k + 1
        case "evening": parts.append(.period(.evening)); j = k + 1
        case "night": parts.append(.period(.night)); j = k + 1
        default: break
        }
        return Match(range: i..<j, parts: parts, due: due, before: before)
    }

    /// "the 20th", "20th", "20 November", "November 20", "Nov 20th", "the 20th of November".
    func dateWords(_ t: [Tok], _ i: Int) -> (DayWord, Int)? {
        var j = i
        if word(t, j) == "the" { j += 1 }
        if let d = ordinal(t, j) {
            j += 1
            var k = j
            if word(t, k) == "of" { k += 1 }
            if let m = Self.months[word(t, k)] { return (.date(month: m, day: d), k + 1) }
            return (.date(month: nil, day: d), j)
        }
        if let d = num(t, j), (1...31).contains(d), let m = Self.months[word(t, j + 1)] {
            return (.date(month: m, day: d), j + 2)
        }
        if let m = Self.months[word(t, j)] {
            if let d = ordinal(t, j + 1) { return (.date(month: m, day: d), j + 2) }
            if word(t, j + 1) == "the", let d = ordinal(t, j + 2) { return (.date(month: m, day: d), j + 3) }
            if let d = num(t, j + 1), (1...31).contains(d), !["am", "pm", "oclock", "minutes", "hours"].contains(word(t, j + 2)) {
                return (.date(month: m, day: d), j + 2)
            }
        }
        return nil
    }

    /// "this morning", "in the evening", "at night".
    func period(_ t: [Tok], _ i: Int) -> Match? {
        var j = i
        if word(t, j) == "in", word(t, j + 1) == "the" { j += 2 }
        else if word(t, j) == "at", word(t, j + 1) == "night" { return Match(range: i..<(i + 2), parts: [.period(.night)]) }
        else { return nil }
        switch word(t, j) {
        case "morning": return Match(range: i..<(j + 1), parts: [.period(.morning)])
        case "afternoon": return Match(range: i..<(j + 1), parts: [.period(.afternoon)])
        case "evening": return Match(range: i..<(j + 1), parts: [.period(.evening)])
        default: return nil
        }
    }

    /// Words that show a time phrase. If one of them stays after the reader, the reader is not sure.
    func isCue(_ t: [Tok], _ i: Int) -> Bool {
        let w = word(t, i)
        if ["am", "pm", "oclock", "noon", "midnight", "tomorrow", "tmrw", "tonight", "today", "minutes", "mins",
            "hours", "hrs", "weekend", "eod"].contains(w) { return true }
        if let _ = Self.weekdays[w], w.count > 3 { return true }
        if let _ = Self.months[w], !Self.weakMonths.contains(w), w.count > 3 { return true }
        if w.contains(":"), w.split(separator: ":").allSatisfy({ Int($0) != nil }) { return true }
        if ["at", "by", "around", "before"].contains(w), num(t, i + 1) != nil { return true }
        if w == "next", ["week", "month"].contains(word(t, i + 1)) { return true }
        return false
    }

    // MARK: - Read

    /// Finds the time phrases. Gives the matches and the tokens.
    func scan(_ words: [String]) -> (t: [Tok], matches: [Match]) {
        let t = Self.tokens(words)
        var matches: [Match] = []
        var i = 0
        while i < t.count {
            let options = [relative(t, i), clock(t, i), day(t, i), period(t, i)].compactMap { $0 }
            if let best = options.max(by: { $0.range.count < $1.range.count }) {
                matches.append(best)
                i = best.range.upperBound
            } else {
                i += 1
            }
        }
        return (t, matches)
    }

    /// Reads the time words of a capture. `now` is the time of the capture. For a to-do, each time is a due date.
    /// For a reminder, a time with no "by", "before", "until" or "due" is the reminder time, and a day with no clock
    /// time is the morning time of that day.
    public func read(_ text: String, now: Date, todo: Bool = false) -> TimeReading {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        let (t, matches) = scan(words)
        var none = TimeReading(rest: text)
        guard !matches.isEmpty else {
            none.unsure = t.indices.contains(where: { isCue(t, $0) })
            return none
        }
        // A source word is in a phrase only if all its parts are.
        var inPhrase = Set<Int>()
        for m in matches { for k in m.range { inPhrase.insert(t[k].src) } }
        for (k, tok) in t.enumerated() where inPhrase.contains(tok.src) {
            if !matches.contains(where: { $0.range.contains(k) }) { inPhrase.remove(tok.src) }
        }
        let leftover = t.indices.filter { !inPhrase.contains(t[$0].src) }
        if leftover.contains(where: { isCue(t, $0) }) { none.unsure = true; return none }

        // Each match has one type: a time of the day (a clock time, minutes from now, midnight) or a day (with or
        // without a part of the day). If two matches have the same type, the last one wins. A day and a clock time
        // in different places combine.
        var timeMatch: Int?, dayMatch: Int?
        for (n, m) in matches.enumerated() {
            let isTime = m.parts.contains { if case .clock = $0 { return true }; if case .minutes = $0 { return true }; if case .midnight = $0 { return true }; return false }
            let isDay = m.parts.contains { if case .day = $0 { return true }; if case .days = $0 { return true }; return false }
            if isTime && isDay { timeMatch = n; dayMatch = n }
            else if isTime { timeMatch = n }
            else if isDay { dayMatch = n }
            else if dayMatch == nil || timeMatch == nil {
                // A part of the day alone ("in the evening"): it is a day type with today.
                if dayMatch == nil { dayMatch = n }
            }
        }
        let used = Set([timeMatch, dayMatch].compactMap { $0 })
        var minutes: Int?, plusDays: Int?, clock: Clock?, dayWord: DayWord?, period: Period?, midnight = false
        var due = false, before = false, endOfDay = false
        for n in used.sorted() {
            let m = matches[n]
            due = due || m.due
            before = before || m.before
            for p in m.parts {
                switch p {
                case .minutes(let x): minutes = x
                case .days(let x): plusDays = x
                case .clock(let c): clock = c
                case .midnight: midnight = true
                case .day(let d): dayWord = d
                case .period(let x): period = x
                case .endOfDay: endOfDay = true
                }
            }
        }
        if minutes != nil && (dayWord != nil || plusDays != nil) { none.unsure = true; return none }

        // Cut the used phrases that are at the start or at the end of the words. The others stay in the title.
        var cut = Set<Int>()
        let sortedUsed = used.sorted()
        var front = 0
        for n in sortedUsed {
            let r = matches[n].range
            if t[r.lowerBound].src <= front { for k in r { cut.insert(t[k].src) }; front = t[r.upperBound - 1].src + 1 } else { break }
        }
        var back = words.count - 1
        for n in sortedUsed.reversed() {
            let r = matches[n].range
            if t[r.upperBound - 1].src >= back { for k in r { cut.insert(t[k].src) }; back = t[r.lowerBound].src - 1 } else { break }
        }
        let rest = words.enumerated().filter { !cut.contains($0.offset) }.map(\.element).joined(separator: " ")
        var out = TimeReading(rest: TimeReader.tidy(rest))
        let isDue = due || todo
        out.kind = isDue ? .due : .remind

        if let minutes {
            var at = calendar.date(byAdding: .minute, value: minutes, to: now)!
            // Seconds are noise: round to the minute.
            let s = calendar.component(.second, from: at)
            at = at.addingTimeInterval(TimeInterval(s >= 30 ? 60 - s : -s))
            out.at = at; out.day = Day(at, calendar); out.hasClock = true
            return out
        }
        let today = Day(now, calendar)
        var day: Day?
        if let plusDays { day = today.adding(days: plusDays, calendar) }
        if let dayWord { day = resolve(dayWord, today: today) }
        if before, let d = day { day = d.adding(days: -1, calendar) }
        if endOfDay, clock == nil { clock = Clock.exact(parts.endOfDay) }
        if midnight {
            let at = (day ?? today).adding(days: 1, calendar).date(calendar)
            out.at = at; out.day = Day(at, calendar); out.hasClock = true
            return out
        }
        if var clock {
            if let period {
                switch period {
                case .morning: if clock.pm == true && clock.hour != 12 { none.unsure = true; return none }; clock.pm = false
                case .afternoon, .evening, .night: if clock.pm == false { none.unsure = true; return none }; clock.pm = true
                }
            }
            let at = place(clock, on: day, now: now, today: today)
            out.at = at; out.day = Day(at, calendar); out.hasClock = true
            return out
        }
        if let period {
            let d = day ?? today
            let c = time(of: period)
            let at = d.date(calendar, hour: c.hour, minute: c.minute)
            if day == nil && at <= now { none.unsure = true; return none }
            out.at = at; out.day = d; out.hasClock = true
            return out
        }
        guard let day else { return none }
        out.day = day
        if !isDue {
            // A reminder on a day with no clock time: the morning time of that day. If it is past, no alert:
            // the reminder shows in the list for today.
            let at = day.date(calendar, hour: parts.morning.hour, minute: parts.morning.minute)
            if at > now { out.at = at }
        }
        return out
    }

    /// Removes spaces and the punctuation at the ends of the words.
    public static func tidy(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = out.last, ",;:.!-".contains(last) { out.removeLast(); out = out.trimmingCharacters(in: .whitespaces) }
        while let first = out.first, ",;:.-".contains(first) { out.removeFirst(); out = out.trimmingCharacters(in: .whitespaces) }
        return out
    }

    func time(of p: Period) -> ClockTime {
        switch p {
        case .morning: return parts.morning
        case .afternoon: return parts.afternoon
        case .evening: return parts.evening
        case .night: return parts.tonight
        }
    }

    /// The hours that a clock time can mean: 5 is 05:00 or 17:00, 5pm is 17:00, 17 is 17:00.
    func hours(_ c: Clock) -> [Int] {
        switch c.pm {
        case .some(true): return [c.hour == 12 ? 12 : c.hour + 12]
        case .some(false): return [c.hour == 12 ? 0 : c.hour]
        case .none:
            if c.hour == 0 || c.hour > 12 { return [c.hour] }
            if c.hour == 12 { return [12] }
            return [c.hour, c.hour + 12]
        }
    }

    func inWindow(_ h: Int, _ m: Int) -> Bool {
        let x = h * 60 + m
        return x >= window.from.minutes && x <= window.to.minutes
    }

    /// The date of a clock time. With no day: the next time in the future. With no "am" or "pm": only the hours in
    /// the window 07:00 to 23:00.
    func place(_ c: Clock, on day: Day?, now: Date, today: Day) -> Date {
        let hs = hours(c)
        let ambiguous = hs.count > 1
        func pick(_ d: Day, future: Bool) -> Date? {
            for h in hs.sorted() where !ambiguous || inWindow(h, c.minute) {
                let at = d.date(calendar, hour: h, minute: c.minute)
                if !future || at > now { return at }
            }
            return nil
        }
        if let day {
            if day == today, let at = pick(day, future: true) { return at }
            return pick(day, future: false) ?? day.date(calendar, hour: hs[0], minute: c.minute)
        }
        if let at = pick(today, future: true) { return at }
        let tomorrow = today.adding(days: 1, calendar)
        return pick(tomorrow, future: false) ?? tomorrow.date(calendar, hour: hs[0], minute: c.minute)
    }

    func resolve(_ w: DayWord, today: Day) -> Day {
        let wdToday = today.weekday(calendar)
        switch w {
        case .today: return today
        case .tomorrow: return today.adding(days: 1, calendar)
        case .plusDays(let n): return today.adding(days: n, calendar)
        case .weekday(let wd, _):
            // "Friday", "on Friday" and "next Friday" are the first Friday after today (build spec 9.2).
            // On a Friday, "Friday" is the Friday of the next week.
            var delta = (wd - wdToday + 7) % 7
            if delta == 0 { delta = 7 }
            return today.adding(days: delta, calendar)
        case .date(let month, let d):
            if let month {
                var y = today.year
                if Day(y, month, d) < today { y += 1 }
                return Day(y, month, d)
            }
            var y = today.year, m = today.month
            if d < today.day { m += 1; if m > 12 { m = 1; y += 1 } }
            // A day that the month does not have (the 31st in November) goes to the next month that has it.
            while d > daysIn(y, m) { m += 1; if m > 12 { m = 1; y += 1 } }
            return Day(y, m, d)
        case .nextWeek:
            let mondayOffset = (wdToday + 5) % 7
            return today.adding(days: 7 - mondayOffset, calendar)
        case .weekend(let next):
            var delta = (7 - wdToday + 7) % 7
            if delta == 0 && !next { return today }
            if wdToday == 1 { delta = 6 }
            var d = today.adding(days: delta, calendar)
            if next { d = d.adding(days: 7, calendar) }
            return d
        case .endOfWeek:
            let delta = (6 - wdToday + 7) % 7
            return today.adding(days: delta, calendar)
        case .endOfMonth:
            return Day(today.year, today.month, daysIn(today.year, today.month))
        case .nextMonth:
            return today.month == 12 ? Day(today.year + 1, 1, 1) : Day(today.year, today.month + 1, 1)
        }
    }

    func daysIn(_ y: Int, _ m: Int) -> Int {
        calendar.range(of: .day, in: .month, for: Day(y, m, 1).date(calendar, hour: 12))!.count
    }
}
