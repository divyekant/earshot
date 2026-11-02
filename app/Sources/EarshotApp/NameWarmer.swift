import Foundation

// T7: keeps the sidebar reads (66-121 ms for each chat app, T4) off the command path.
// It reads the name cache at start, and again before the cache gets old. It reads only. It presses no key.

final class NameWarmer {
    /// Reads the sidebars of the approved chat apps (NameIndex.refresh). It must press nothing.
    let refresh: () async -> Void
    /// True if Accessibility is on. With it off, a sidebar read gives nothing, so the warmer waits.
    let trusted: () -> Bool
    /// The time between reads. Shorter than NameIndex.maxAge, so that a command normally hits the cache.
    let interval: TimeInterval
    /// Changes when the catalogue changes (apps.json), for example when the owner approves a chat app.
    /// A change starts a read before the interval ends, so that a new app's names are ready for the next command.
    let changeToken: () -> Date?
    /// How often the warmer looks at `changeToken`.
    let checkEvery: TimeInterval
    private var task: Task<Void, Never>?
    private var lastRead: Date?
    private var lastToken: Date?

    init(interval: TimeInterval, checkEvery: TimeInterval = 15, trusted: @escaping () -> Bool,
         refresh: @escaping () async -> Void, changeToken: @escaping () -> Date? = { nil }) {
        self.interval = interval; self.checkEvery = min(checkEvery, interval); self.trusted = trusted
        self.refresh = refresh; self.changeToken = changeToken
    }

    /// Reads one time now (if Accessibility is on), then every `interval`, and after each catalogue change, until `stop()`.
    func start() {
        stop()
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                if self.due() { await self.tick() }
                try? await Task.sleep(nanoseconds: UInt64(self.checkEvery * 1_000_000_000))
            }
        }
    }

    /// True if a read is due: the first read, the interval ended, or the catalogue changed.
    func due(now: Date = Date()) -> Bool {
        let token = changeToken()
        guard let last = lastRead else { return true }
        return now.timeIntervalSince(last) >= interval || token != lastToken
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// One read, if Accessibility is on. Returns true if it read.
    @discardableResult
    func tick() async -> Bool {
        guard trusted() else { return false }
        lastToken = changeToken()
        await refresh()
        lastRead = Date()
        return true
    }
}
