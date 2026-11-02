import Foundation

/// Runs `op` and returns its answer, or nil after `ms` milliseconds.
/// It does not wait for `op` to stop: an operation that ignores cancellation cannot hold the command (R-SP-2).
func withBudget<T: Sendable>(_ ms: Int, _ op: @escaping @Sendable () async -> T?) async -> T? {
    let once = Once<T>()
    return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        once.start(continuation)
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(ms, 0)) * 1_000_000
        let work = Task {
            let value = await op()
            // An answer after the budget does not count, even if the timer task has not run yet (a busy Mac).
            guard !Task.isCancelled, DispatchTime.now().uptimeNanoseconds <= deadline else { return }
            once.finish(value)
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(max(ms, 0)) * 1_000_000)
            // Finish first, then cancel: a cancelled operation can return at once, and it must not win.
            once.finish(nil)
            work.cancel()
        }
    }
}

/// Resumes the continuation one time only: with the first answer, or with nil at the end of the budget.
private final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    func start(_ c: CheckedContinuation<T?, Never>) {
        lock.lock()
        continuation = c
        lock.unlock()
    }

    func finish(_ value: T?) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}
