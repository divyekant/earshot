import EarshotCore
import Foundation

/// Makes the speech engine from the owner's settings. EarshotApp calls this one time at start.
public enum SpeechEngines {
    /// Returns the engine for the settings, and the reason for the log.
    /// "auto" with a Parakeet model file: AutoSpeechEngine picks Parakeet or Apple for each command.
    /// "parakeet": Parakeet only; if it fails to load, the engine falls back to Apple.
    public static func make(_ settings: EarshotSettings,
                            locator: ParakeetModelLocator = ParakeetModelLocator()) -> (engine: SpeechEngine, why: String) {
        let locale = Locale(identifier: settings.locale)
        let (resolved, why) = EngineResolver.resolve(settings.engine, configuredModel: settings.parakeetModelPath, locator: locator)
        switch resolved {
        case .apple:
            let apple = AppleSpeechEngine(locale: locale)
            apple.reason = why
            return (apple, why)
        case .parakeet(let path) where settings.engine == .auto:
            let engine = AutoSpeechEngine(parakeet: ParakeetEngine(modelPath: path), apple: AppleSpeechEngine(locale: locale))
            engine.reason = why
            return (engine, why)
        case .parakeet(let path):
            let parakeet = ParakeetEngine(modelPath: path)
            parakeet.reason = why
            let engine = FallbackSpeechEngine(primary: parakeet, fallback: { AppleSpeechEngine(locale: locale) })
            return (engine, why)
        }
    }
}

/// Uses `primary`. If `primary` fails in `prepare`, it uses the fallback engine.
/// So a broken model file never stops voice commands.
public final class FallbackSpeechEngine: SpeechEngine, SpeechTimingReporting, @unchecked Sendable {
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
                (next as? SpeechTimingReporting)?.reason = "fallback to Apple: \(error)"
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
    public func end() async throws -> Utterance { try await active.end() }
}
