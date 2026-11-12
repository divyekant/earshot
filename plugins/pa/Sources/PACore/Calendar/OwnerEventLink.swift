import Foundation

/// Links by the owner (phase 3 build spec, 9.2): "remind me before the dentist to bring the x-ray",
/// "todo print the contract for the meeting with Sam". Sure, with no "?".
public enum OwnerEventLink {
    /// The words before the event: "before", "at", and "for the".
    static let triggers: [[String]] = [["before"], ["at"], ["for", "the"]]
    static let connectors: Set<String> = ["to", "and", "then", "so"]

    /// Finds the event that the words name. Each content word of the event phrase must be a whole word of the title,
    /// and exactly one event of `events` must match. Gives the event and the words with the event phrase cut.
    public static func match(_ text: String, events: [CalEvent]) -> (event: CalEvent, rest: String)? {
        let raw = text.split(separator: " ").map(String.init)
        let low = raw.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        let titles = events.map { Set(EventLinker.words($0.title)) }
        var best: (start: Int, end: Int, events: [Int])?
        for t in triggers {
            var i = 0
            while i + t.count <= low.count {
                guard Array(low[i..<(i + t.count)]) == t else { i += 1; continue }
                var j = i + t.count
                if j < low.count, ["the", "my", "our"].contains(low[j]) { j += 1 }
                // The longest phrase after the trigger whose content words are all in one or more titles.
                var found: (end: Int, events: [Int])?
                var content: [String] = []
                var k = j
                while k < low.count {
                    let w = low[k].hasSuffix("'s") ? String(low[k].dropLast(2)) : low[k]
                    if connectors.contains(w), !content.isEmpty { break }
                    if !Words.stop.contains(w) { content.append(w) }
                    let hits = titles.indices.filter { idx in !content.isEmpty && content.allSatisfy { titles[idx].contains($0) } }
                    if hits.isEmpty { break }
                    found = (k + 1, hits)
                    k += 1
                }
                if let f = found, (best == nil || f.end - j > best!.end - best!.start) {
                    best = (i, f.end, f.events)
                }
                i += 1
            }
        }
        guard let b = best, b.events.count == 1 else { return nil }
        var rest = Array(raw[..<b.start]) + Array(raw[b.end...])
        if rest.first.map({ connectors.contains($0.lowercased()) }) ?? false { rest.removeFirst() }
        if b.start > 0, b.end < raw.count, connectors.contains(raw[b.end].lowercased()) {
            rest = Array(raw[..<b.start]) + Array(raw[(b.end + 1)...])
        }
        return (events[b.events[0]], rest.joined(separator: " "))
    }

    /// "Thu 10:00" for an event in the next 6 days, else "Thu 26 Nov 10:00".
    public static func when(_ e: CalEvent, now: Date, _ cal: Calendar, locale: Locale) -> String {
        let d = Day(e.startsAt, cal)
        let wd = TimeText.weekdays[d.weekday(cal) - 1]
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: e.startsAt)).day ?? 0
        let head = days <= 6 ? wd : "\(wd) \(d.day) \(TimeText.months[d.month - 1])"
        return head + " " + TimeText.clock(e.startsAt, cal, locale: locale)
    }
}
