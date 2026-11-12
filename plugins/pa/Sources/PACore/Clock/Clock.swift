import Foundation

/// The time source of the PA. The program uses the system clock. Tests use a fixed clock, so the logic does not
/// depend on the time zone and the locale of the test machine.
public protocol Clock: AnyObject {
    var now: Date { get }
    var calendar: Calendar { get }
    var locale: Locale { get }
}

/// The system clock, with the calendar, the time zone and the locale of the Mac.
public final class SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        c.locale = Locale.current
        return c
    }
    public var locale: Locale { Locale.current }
}

/// A clock that tests move by hand.
public final class FixedClock: Clock {
    public var now: Date
    public let calendar: Calendar
    public let locale: Locale

    public init(_ now: Date, timeZone: TimeZone = TimeZone(identifier: "Europe/London")!, locale: Locale = Locale(identifier: "en_GB")) {
        self.now = now
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = locale
        self.calendar = c
        self.locale = locale
    }

    public func advance(minutes: Double) { now = now.addingTimeInterval(minutes * 60) }
}
