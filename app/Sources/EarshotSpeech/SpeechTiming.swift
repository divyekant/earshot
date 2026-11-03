import Foundation

/// The parts of the speech stage of one command, from key release to the final text.
/// EarshotApp puts `stages` into the activity record, so that the log shows where the time goes.
public struct SpeechTiming: Codable, Equatable, Sendable {
    /// The engine that made the text: "parakeet" or "apple".
    public var engine: String
    /// Why this engine runs, for example "auto: Parakeet model file found" or "fallback to Apple: ...".
    public var why: String
    /// The length of the audio that the engine read, with the preroll and the tail silence.
    public var audioMs: Double = 0
    /// The time from the end of the last model run to the key press (Parakeet). A long idle time can make the next run slow.
    public var idleMs: Double = 0
    /// True if the engine started a warm-up run at the key press, because the model was idle.
    public var warmed: Bool = false
    /// Key release to closed audio: 200 ms more of real audio (`TailPad.captureSeconds`, 0 in always-on), stop the audio feed,
    /// add the tail silence, collect the samples.
    /// The audio conversion runs in the microphone callback while the owner speaks, so it adds no time here.
    public var tailMs: Double = 0
    /// Wait for the model: a warm-up or partial run that was still in progress (Parakeet), or the analyzer start (Apple).
    public var waitMs: Double = 0
    /// The model run (Parakeet), or the finalize step of the analyzer (Apple).
    public var decodeMs: Double = 0
    /// Key release to the final text.
    public var totalMs: Double = 0

    public init(engine: String, why: String) { self.engine = engine; self.why = why }

    /// Stage names for the activity record.
    public static let tailStage = "speech.tail"
    public static let waitStage = "speech.wait"
    public static let decodeStage = "speech.decode"

    public var stages: [String: Double] {
        [Self.tailStage: Self.round(tailMs), Self.waitStage: Self.round(waitMs), Self.decodeStage: Self.round(decodeMs)]
    }

    /// One line for the log, for example "parakeet (auto: ...) audio 2140 ms, idle 61000 ms, warmed".
    public var summary: String {
        var s = "\(engine) (\(why)) audio \(Int(audioMs.rounded())) ms"
        if idleMs > 0 { s += ", idle \(Int(idleMs.rounded())) ms" }
        if warmed { s += ", warmed" }
        return s
    }

    static func round(_ v: Double) -> Double { (v * 10).rounded() / 10 }
}

/// An engine that reports the timing of its last `end()`. All engines of this module conform.
/// EarshotApp reads it with `(engine as? SpeechTimingReporting)?.lastTiming` after each command.
public protocol SpeechTimingReporting: AnyObject {
    var lastTiming: SpeechTiming? { get }
    /// Why this engine runs. `SpeechEngines.make` sets it.
    var reason: String { get set }
}

/// Keeps macOS from slowing the process during one command. earshot is a menu-bar app and is almost
/// never the front app, so App Nap can lower its CPU and timer priority between commands.
/// An activity with `.userInitiated` and `.latencyCritical` turns App Nap off until `end`.
final class TurnActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var token: NSObjectProtocol?

    func begin(_ reason: String) {
        lock.withLock {
            if token != nil { return }
            token = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: reason)
        }
    }

    func end() {
        let t = lock.withLock { () -> NSObjectProtocol? in defer { token = nil }; return token }
        if let t { ProcessInfo.processInfo.endActivity(t) }
    }

    var isActive: Bool { lock.withLock { token != nil } }
}
