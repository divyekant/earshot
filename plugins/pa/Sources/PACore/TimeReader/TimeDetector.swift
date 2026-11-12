import Foundation

/// One time phrase that a date detector found.
public struct DetectedTime: Equatable, Sendable {
    public var date: Date
    /// The range of the phrase in the text, in characters.
    public var range: Range<Int>
    /// False if the detector found a day with no clock time.
    public var hasClock: Bool

    public init(date: Date, range: Range<Int>, hasClock: Bool) {
        self.date = date; self.range = range; self.hasClock = hasClock
    }
}

/// A date detector, for example the one of macOS (NSDataDetector). The PA reads time phrases with its own rules
/// first. Probe 2 of the build measures the detector on the same 100 phrases.
public protocol TimeDetector {
    func detect(_ text: String, now: Date, calendar: Calendar) -> [DetectedTime]
}
