import EarshotCore
import Foundation

/// An engine with turns that the caller can drop, and a microphone that the caller can close.
/// AutoSpeechEngine uses the Apple engine through this protocol, so that it works with either Apple engine.
public protocol TurnSpeechEngine: SpeechEngine, SpeechTimingReporting {
    /// Drops the turn with no final text.
    func cancelTurn()
    /// Closes the microphone.
    func shutdown()
}

/// The Apple speech engine for this Mac.
public enum AppleSpeech {
    /// The id of the Apple engine in the settings and in "auto".
    public static let engineID = "apple"

    /// SpeechTranscriber on macOS 26, with on-device dictation as the fallback if SpeechTranscriber does not load
    /// (it is reported to need Apple silicon). On-device dictation alone on older macOS.
    /// Both keep the audio on the Mac (R-MD-1).
    public static func make(locale: Locale) -> TurnSpeechEngine {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            return FallbackSpeechEngine(primary: AppleSpeechEngine(locale: locale), fallback: { DictationEngine(locale: locale) })
        }
        #endif
        return DictationEngine(locale: locale)
    }
}

/// Makes the speech engine from the owner's settings. EarshotApp calls this one time at start.
public enum SpeechEngines {
    /// Returns the engine for the settings, and the reason for the log.
    /// "auto" and "apple": Apple (see EngineResolver).
    /// "parakeet" with a model file: AutoSpeechEngine. It uses Parakeet for a command only when Parakeet is fast now,
    /// else Apple, so that a slow Parakeet never makes the owner wait. If Parakeet fails to load, Apple does all commands.
    public static func make(_ settings: EarshotSettings,
                            locator: ParakeetModelLocator = ParakeetModelLocator()) -> (engine: SpeechEngine, why: String) {
        let locale = Locale(identifier: settings.locale)
        let (resolved, why) = EngineResolver.resolve(settings.engine, configuredModel: settings.parakeetModelPath, locator: locator)
        switch resolved {
        case .apple:
            let apple = AppleSpeech.make(locale: locale)
            apple.reason = why
            return (apple, why)
        case .parakeet(let path):
            let engine = AutoSpeechEngine(parakeet: ParakeetEngine(modelPath: path), apple: AppleSpeech.make(locale: locale))
            engine.reason = why
            return (engine, why)
        }
    }
}

/// Uses `primary`. If `primary` fails in `prepare`, it uses the fallback engine.
/// So a broken model file never stops voice commands.
public final class FallbackSpeechEngine: TurnSpeechEngine, PrerollControl, @unchecked Sendable {
    private let lock = NSLock()
    private var current: SpeechEngine
    private var makeFallback: (() -> SpeechEngine)?
    private var partial: (@Sendable (String) -> Void)?
    /// The error of the primary engine, if the fallback engine is in use.
    public private(set) var fallbackReason: String?

    public init(primary: SpeechEngine, fallback: @escaping () -> SpeechEngine) {
        current = primary
        makeFallback = fallback
    }

    public var id: String { lock.withLock { current.id } }

    /// The timing of the last command of the engine in use.
    public var lastTiming: SpeechTiming? { (active as? SpeechTimingReporting)?.lastTiming }

    /// Why the engine in use runs.
    public var reason: String {
        get { (active as? SpeechTimingReporting)?.reason ?? "" }
        set { (active as? SpeechTimingReporting)?.reason = newValue }
    }

    /// The engine in use now.
    public var active: SpeechEngine { lock.withLock { current } }

    public var onPartial: (@Sendable (String) -> Void)? {
        get { lock.withLock { partial } }
        set { lock.withLock { partial = newValue; current.onPartial = newValue } }
    }

    public func prepare() async throws {
        do {
            try await active.prepare()
        } catch {
            let next = lock.withLock { () -> SpeechEngine? in
                guard let make = makeFallback else { return nil }
                let next = make()
                next.onPartial = partial
                (next as? SpeechTimingReporting)?.reason = "fallback: \(error)"
                current = next
                makeFallback = nil
                fallbackReason = "\(error)"
                return next
            }
            guard let next else { throw error }
            try await next.prepare()
        }
    }

    public func begin() throws { try active.begin() }
    public func setNextPreroll(seconds: Double) { (active as? PrerollControl)?.setNextPreroll(seconds: seconds) }
    public func end() async throws -> Utterance { try await active.end() }
    public func cancelTurn() { (active as? TurnSpeechEngine)?.cancelTurn() }
    public func shutdown() { (active as? TurnSpeechEngine)?.shutdown() }
}
