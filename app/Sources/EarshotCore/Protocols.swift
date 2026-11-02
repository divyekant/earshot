import Foundation

// The seams between the modules. Each module (speech, router, actions, discovery, input)
// implements one of these, and EarshotApp connects them.

/// Speech to text on the Mac (R-MD-1). Implementations: Apple SpeechTranscriber, Parakeet.
public protocol SpeechEngine: AnyObject {
    var id: String { get }
    /// Loads the model. Call once at start, not for each command.
    func prepare() async throws
    /// Starts to listen. Partial text goes to `onPartial`.
    func begin() throws
    /// Stops, and returns the final text.
    func end() async throws -> Utterance
    var onPartial: (@Sendable (String) -> Void)? { get set }
}

/// What starts and stops one utterance: a held key, or the always-on gate (R-ON-1, R-ON-4).
public protocol InputTrigger: AnyObject {
    var onStart: (() -> Void)? { get set }
    var onStop: (() -> Void)? { get set }
    func start() throws
    func stop()
}

/// Text to one intent. Rules first; a model only when the rules are unsure (R-SP-2).
public protocol Router {
    func route(_ text: String, context: RouteContext) async -> RouteResult
}

/// The tier-2 hook: picks one option from a short list when the rules are unsure.
/// EarshotSettings.tier2 selects the implementation. "off" means no tier 2.
public protocol Tier2Chooser {
    /// Returns the index of the chosen option, or nil for "none of these". It must return within `budgetMs`.
    func choose(_ text: String, options: [String], budgetMs: Int) async -> Int?
}

/// Runs one intent in the user interface (R-MD-6). It obeys SafetyPolicy.
public protocol ActionRunner {
    func run(_ intent: Intent, context: RouteContext) async -> ActionOutcome
    /// The front window and its elements, for voice clicks. Nil if earshot cannot read it.
    func screen() async -> ScreenSnapshot?
}

/// Builds catalogue rows from the running and installed apps (R-MT-1, R-MT-2).
public protocol CatalogueBuilder {
    func discover() async -> [AppEntry]
}

/// Finds chat names: sidebars, the app's own search, Contacts.
public protocol NameFinder {
    func names(appID: String) async -> [NameEntry]
    func search(appID: String, term: String) async -> [NameEntry]
}

/// The small note on screen (R-FB-1).
public protocol FeedbackSink: AnyObject {
    func show(_ text: String, ok: Bool)
    func hide()
}
