import EarshotCore
import Foundation

/// Makes the speech engine from the owner's settings. EarshotApp calls this one time at start.
public enum SpeechEngines {
    /// Returns the engine for the settings, and the reason for the log.
    /// For "auto" and "parakeet", if Parakeet fails to load, the engine falls back to Apple.
    public static func make(_ settings: EarshotSettings,
                            locator: ParakeetModelLocator = ParakeetModelLocator()) -> (engine: SpeechEngine, why: String) {
        let locale = Locale(identifier: settings.locale)
        let (resolved, why) = EngineResolver.resolve(settings.engine, configuredModel: settings.parakeetModelPath, locator: locator)
        switch resolved {
        case .apple:
            return (AppleSpeechEngine(locale: locale), why)
        case .parakeet(let path):
            let engine = FallbackSpeechEngine(primary: ParakeetEngine(modelPath: path),
                                              fallback: { AppleSpeechEngine(locale: locale) })
            return (engine, why)
        }
    }
}

/// Uses `primary`. If `primary` fails in `prepare`, it uses the fallback engine.
/// So a broken model file never stops voice commands.
public final class FallbackSpeechEngine: SpeechEngine, @unchecked Sendable {
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

    public var id: String { lock.lock(); defer { lock.unlock() }; return current.id }

    /// The engine in use now.
    public var active: SpeechEngine { lock.lock(); defer { lock.unlock() }; return current }

    public var onPartial: (@Sendable (String) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return partial }
        set { lock.lock(); partial = newValue; current.onPartial = newValue; lock.unlock() }
    }

    public func prepare() async throws {
        do {
            try await active.prepare()
        } catch {
            lock.lock()
            guard let make = makeFallback else { lock.unlock(); throw error }
            let next = make()
            next.onPartial = partial
            current = next
            makeFallback = nil
            fallbackReason = "\(error)"
            lock.unlock()
            try await next.prepare()
        }
    }

    public func begin() throws { try active.begin() }
    public func end() async throws -> Utterance { try await active.end() }
}
