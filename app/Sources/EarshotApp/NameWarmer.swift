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
    private var task: Task<Void, Never>?

    init(interval: TimeInterval, trusted: @escaping () -> Bool, refresh: @escaping () async -> Void) {
        self.interval = interval; self.trusted = trusted; self.refresh = refresh
    }

    /// Reads one time now (if Accessibility is on), then every `interval`, until `stop()`.
    func start() {
        stop()
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// One read, if Accessibility is on. Returns true if it read.
    @discardableResult
    func tick() async -> Bool {
        guard trusted() else { return false }
        await refresh()
        return true
    }
}
