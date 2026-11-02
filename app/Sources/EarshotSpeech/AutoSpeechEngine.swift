import EarshotCore
import Foundation

/// The memory pressure level of macOS.
public enum MemoryPressureLevel: String, Codable, Sendable {
    case normal, warning, critical

    /// Reads kern.memorystatus_vm_pressure_level (1 normal, 2 warning, 4 critical). It takes a few microseconds.
    public static func current() -> MemoryPressureLevel {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}

/// The rules of the engine "auto" for one command.
public struct AutoPolicy: Sendable {
    /// The warm-up run of a turn must end within this time, or the model weights are not in memory.
    public var minWarmLimitMs = 120.0
    /// Or within this many times the warm-up time right after the load.
    public var warmFactor = 4.0

    public init() {}

    public func warmLimit(baselineMs: Double) -> Double { max(minWarmLimitMs, baselineMs * warmFactor) }

    /// At the key press: start a Parakeet turn too?
    public func tryParakeet(loaded: Bool, pressure: MemoryPressureLevel) -> (Bool, String) {
        if !loaded { return (false, "apple: Parakeet not loaded yet") }
        if pressure != .normal { return (false, "apple: memory pressure \(pressure.rawValue)") }
        return (true, "")
    }

    /// At key release: use the Parakeet text? `warmMs` is nil if the warm-up run is not done.
    public func useParakeet(warmMs: Double?, baselineMs: Double) -> (Bool, String) {
        let limit = warmLimit(baselineMs: baselineMs)
        guard let warmMs else { return (false, "apple: Parakeet warm-up not done (weights not in memory)") }
        if warmMs > limit {
            return (false, "apple: Parakeet warm-up \(Int(warmMs.rounded())) ms > \(Int(limit.rounded())) ms (weights not in memory)")
        }
        return (true, "parakeet: warm-up \(Int(warmMs.rounded())) ms")
    }
}

/// The engine for the setting "parakeet": Parakeet when it is fast now, else Apple, per command (live test 2026-11-02).
///
/// Live test: with the memory of the Mac full (swap nearly full), macOS moved the Parakeet weights out of memory
/// between commands, and the speech stage grew from 0.4 s to 6.9 s. So "auto" checks for each command:
/// - At the key press, Apple always starts. Parakeet starts too, with a short warm-up run, only if it is loaded
///   and the memory pressure is normal.
/// - At key release, Parakeet makes the text only if its warm-up run ended in time. Else Apple makes the text,
///   and Parakeet stops with no decode. So a slow Parakeet never makes the owner wait.
/// - Until Parakeet is loaded (about 15 s), Apple makes the text.
/// `lastTiming.why` tells which engine ran and why.
public final class AutoSpeechEngine: SpeechEngine, SpeechTimingReporting, @unchecked Sendable {
    public let parakeet: ParakeetEngine
    public let apple: AppleSpeechEngine
    public var policy = AutoPolicy()
    public var reason = ""
    var pressure: () -> MemoryPressureLevel = MemoryPressureLevel.current

    private let lock = NSLock()
    private var parakeetReady = false
    private var parakeetInTurn = false
    private var turnWhy = ""
    private var timing: SpeechTiming?
    private var partial: (@Sendable (String) -> Void)?
    /// The error of the Parakeet load, if it failed.
    public private(set) var parakeetError: String?

    public init(parakeet: ParakeetEngine, apple: AppleSpeechEngine) {
        self.parakeet = parakeet
        self.apple = apple
        parakeet.warmEveryTurn = true
        parakeet.warmAfterIdleSeconds = nil
    }

    /// "parakeet" when Parakeet is loaded, else "apple". The engine of each command is in `lastTiming`.
    public var id: String { lock.withLock { parakeetReady } ? ParakeetEngine.engineID : AppleSpeechEngine.engineID }

    public var lastTiming: SpeechTiming? { lock.withLock { timing } }

    /// Apple sends the partial text. Parakeet sends none in "auto".
    public var onPartial: (@Sendable (String) -> Void)? {
        get { lock.withLock { partial } }
        set { lock.withLock { partial = newValue }; apple.onPartial = newValue }
    }

    /// Prepares Apple, then loads Parakeet in the background. Commands work as soon as Apple is ready.
    public func prepare() async throws {
        try await apple.prepare()
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                try await self.parakeet.prepare()
                self.lock.withLock { self.parakeetReady = true }
            } catch {
                self.lock.withLock { self.parakeetError = "\(error)" }
            }
        }
    }

    public func begin() throws {
        let (start, why) = policy.tryParakeet(loaded: lock.withLock { parakeetReady }, pressure: pressure())
        try apple.begin()
        var inTurn = false
        if start {
            do { try parakeet.begin(); inTurn = true } catch { }
        }
        lock.withLock { parakeetInTurn = inTurn; turnWhy = why }
    }

    public func end() async throws -> Utterance {
        let (inTurn, why) = lock.withLock { () -> (Bool, String) in
            defer { parakeetInTurn = false }
            return (parakeetInTurn, turnWhy)
        }
        var useP = false
        var reasonNow = why
        if inTurn {
            (useP, reasonNow) = policy.useParakeet(warmMs: parakeet.turnWarmMs, baselineMs: parakeet.baselineWarmMs)
        }
        if useP {
            apple.cancelTurn()
            let u = try await parakeet.end()
            record(parakeet.lastTiming, why: reasonNow)
            return u
        }
        if inTurn { parakeet.cancelTurn() }
        let u = try await apple.end()
        record(apple.lastTiming, why: reasonNow)
        return u
    }

    /// Drops the turn of both engines.
    public func cancelTurn() {
        let inTurn = lock.withLock { () -> Bool in defer { parakeetInTurn = false }; return parakeetInTurn }
        apple.cancelTurn()
        if inTurn { parakeet.cancelTurn() }
    }

    public func shutdown() { apple.shutdown(); parakeet.shutdown() }

    private func record(_ t: SpeechTiming?, why: String) {
        guard var t else { return }
        t.why = reason.isEmpty ? why : "\(reason); \(why)"
        lock.withLock { timing = t }
    }
}
