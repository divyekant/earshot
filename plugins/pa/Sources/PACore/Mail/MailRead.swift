import Foundation

/// Step 1 of the request flags, fixed rules (phase 3 build spec, 8.1). A message that fails gets no request flag.
public enum BulkFilter {
    public static let maxAddresses = 20

    /// The reason that removes the message, or nil if it passes. `owner` is the list of the owner's addresses in
    /// lower case.
    public static func reason(_ m: MailMessage, owner: Set<String>) -> String? {
        if m.junk { return "junk" }
        if owner.contains(m.fromAddress.lowercased()) { return "from owner" }
        if m.listHeader { return "list header" }
        if ["bulk", "list", "junk"].contains(where: { m.precedence.contains($0) }) { return "precedence" }
        if m.autoSubmitted || m.precedence.contains("auto_reply") { return "automatic" }
        let all = (m.to + m.cc).map { $0.lowercased() }
        if !all.contains(where: owner.contains) { return "owner not in to or cc" }
        if all.count > maxAddresses { return "many addresses" }
        if m.replied { return "replied" }
        return nil
    }
}

/// The plan of one mail read (spec 6.1): one small Apple event at a time, a cheap check first, a budget for each
/// read. It runs off the engine queue and uses only the source. The engine applies the result on its queue.
public struct MailReadPlan: Sendable {
    public var known: Set<String>
    /// The newest id at the end of the last complete read.
    public var lastNewest: String?
    public var batch = 10
    public var maxLookBack = 50
    public var maxMessages = 10
    public var maxTexts = 10
    /// The most Apple event time in one read.
    public var maxSeconds: TimeInterval = 6
    /// At the first read: only messages after this time.
    public var since: Date?
    public var owner: Set<String>
    /// Open mail flags: the PA checks if the owner replied.
    public var openFlagIDs: [String] = []

    public init(known: Set<String>, lastNewest: String?, owner: Set<String>) {
        self.known = known; self.lastNewest = lastNewest; self.owner = owner
    }

    public struct Seen: Sendable {
        public var message: MailMessage
        /// nil if the message passes the filter.
        public var bulk: String?
        /// True if the PA read the text.
        public var hasText: Bool
        /// True if the message is older than the first-read limit.
        public var old: Bool
    }

    public struct Result: Sendable {
        public var unchanged = false
        public var seen: [Seen] = []
        /// The read reached a known id or the end: the next cheap check can compare with `newest`.
        public var complete = false
        public var newest: String?
        public var answered: [String] = []
        /// Ids that failed, for a retry.
        public var failed: [String] = []
        public var seconds: TimeInterval = 0
        public var events = 0
        /// The owner addresses that the read used, in lower case (for gate 2 of the request flags).
        public var owner: Set<String> = []
    }

    public func run(_ source: MailSource, clock: () -> Date = Date.init) -> Result {
        var r = Result()
        r.owner = owner
        let start = clock()
        func spent() -> TimeInterval { clock().timeIntervalSince(start) }
        // 1. The cheap check.
        guard let newest = try? source.ids(from: 0, count: 1).first else { r.events = 1; r.seconds = spent(); return r }
        r.events += 1
        r.newest = newest
        if newest == lastNewest || (lastNewest == nil && known.contains(newest)) {
            r.unchanged = true
            r.complete = true
        } else {
            // 2. The new ids, newest first, in steps, up to the first known id.
            var fresh: [String] = []
            var pos = 0
            var reachedKnown = false
            while pos < maxLookBack, fresh.count < maxMessages, spent() < maxSeconds {
                guard let ids = try? source.ids(from: pos, count: batch) else { break }
                r.events += 1
                if ids.isEmpty { reachedKnown = true; break }
                for id in ids {
                    if known.contains(id) { reachedKnown = true; break }
                    fresh.append(id)
                }
                if reachedKnown || ids.count < batch { reachedKnown = true; break }
                pos += batch
            }
            if pos >= maxLookBack { reachedKnown = true }
            // 3. The envelope of each new message. The text only after the filter.
            var texts = 0
            var stoppedEarly = false
            for id in fresh.prefix(maxMessages) {
                if spent() >= maxSeconds { stoppedEarly = true; break }
                guard var m = try? source.envelope(id: id) else { r.failed.append(id); r.events += 1; continue }
                r.events += 1
                if let since, m.date < since {
                    r.seen.append(Seen(message: m, bulk: "old", hasText: false, old: true))
                    // The rest is older: the look back ends here.
                    reachedKnown = true
                    break
                }
                let bulk = BulkFilter.reason(m, owner: owner)
                var hasText = false
                if bulk == nil, texts < maxTexts, spent() < maxSeconds {
                    if let t = try? source.text(id: id) {
                        m.text = String(t.prefix(MailMessage.maxText))
                        hasText = true
                        texts += 1
                    } else {
                        r.failed.append(id)
                        r.events += 1
                        continue
                    }
                    r.events += 1
                } else if bulk == nil {
                    // No budget for the text: the next read takes it.
                    stoppedEarly = true
                    break
                }
                r.seen.append(Seen(message: m, bulk: bulk, hasText: hasText, old: false))
            }
            if fresh.count > maxMessages { stoppedEarly = true }
            r.complete = reachedKnown && !stoppedEarly && r.failed.isEmpty
        }
        // 4. Replies of the owner to open flags.
        for id in openFlagIDs where spent() < maxSeconds {
            if let m = try? source.envelope(id: id) {
                r.events += 1
                if m.replied { r.answered.append(id) }
            }
        }
        r.seconds = spent()
        return r
    }
}
