import EarshotCore
import Foundation

/// The "is this for me?" gate for always-on (R-ON-2, R-ON-5, DESIGN.md 3.3).
/// It reads the final text of one utterance and decides if earshot acts on it.
///
/// The layers:
/// 1. Prefix rule. Text that starts with a command word or the name of an approved app passes.
///    Hesitation words at the start (`Hesitation.words`, for example "uh") do not count.
/// 2. Follow-up window. For a few seconds after a command, any text passes, for example the message text.
/// 3. Call context. If the owner is in a call, only the prefix rule counts.
/// 4. Safety. "send" passes only as a short command of its own, in the follow-up window, not in a call.
///    A false trigger can only open, focus or type. It can never send (R-ON-5).
///
/// The hold key does not use this gate: a held key is always for earshot.
/// The command words are grammar, the same for every app. App names come from the catalogue (R-MT-1).
public struct ForMeGate: Sendable {
    public struct Config: Sendable, Equatable {
        /// The follow-up window, in seconds after the last command.
        public var followUpSeconds: Double = 5
        /// Text with more words than this needs the prefix rule, also in the follow-up window. People talk in long sentences.
        public var followUpMaximumWords: Int = 30
        /// First words that mark a command.
        public var commandWords: Set<String> = [
            "open", "launch", "switch", "go", "click", "press", "tap", "select", "choose", "pick", "scroll", "page",
            "back", "forward", "show", "hide", "type", "write", "dictate", "search", "find", "focus", "message", "text",
            "tell", "reply", "chat", "dm", "earshot",
        ]
        /// Short commands that send. Only these pass as "send" (R-NV-5, R-ON-5).
        public var sendPhrases: Set<String> = ["send", "send it", "send that", "send this", "send message", "send the message", "send now"]
        public init() {}
    }

    public enum Verdict: Sendable, Equatable {
        /// Act on `text`. `maySend` is true only for an explicit, short "send" command (R-NV-5).
        case forMe(text: String, maySend: Bool, why: String)
        case notForMe(String)

        public var isForMe: Bool { if case .forMe = self { return true }; return false }
    }

    public let config: Config
    public init(config: Config = Config()) { self.config = config }

    /// Decides for one utterance.
    /// - Parameters:
    ///   - apps: the catalogue. Only approved, enabled rows count.
    ///   - secondsSinceLastCommand: nil if there was no command yet.
    ///   - inCall: true if the owner is in a call. Then only the prefix rule counts.
    public func check(_ text: String, apps: [AppEntry], secondsSinceLastCommand: Double?, inCall: Bool = false) -> Verdict {
        // Drop hesitation words at the start ("uh, Slack me ..."). The router uses the same list.
        let words = Array(SafetyPolicy.normalize(text).split(separator: " ").map(String.init)
            .drop(while: { Hesitation.words.contains($0) }))
        guard !words.isEmpty else { return .notForMe("no words") }
        let phrase = words.joined(separator: " ")
        let inWindow = !inCall && (secondsSinceLastCommand.map { $0 >= 0 && $0 <= config.followUpSeconds } ?? false)

        if words.contains("send") {
            guard config.sendPhrases.contains(phrase) else {
                // "send" inside a longer sentence: do not pass it as a command. Someone may talk about sending.
                if let why = prefixReason(words, apps: apps) { return .forMe(text: text, maySend: false, why: why) }
                return .notForMe("\"send\" inside a sentence")
            }
            guard inWindow else { return .notForMe(inCall ? "\"send\" during a call" : "\"send\" with no command before it") }
            return .forMe(text: text, maySend: true, why: "send in the follow-up window")
        }

        if let why = prefixReason(words, apps: apps) { return .forMe(text: text, maySend: false, why: why) }
        if inWindow && words.count <= config.followUpMaximumWords {
            return .forMe(text: text, maySend: false, why: "follow-up window")
        }
        if inCall { return .notForMe("in a call, and no command word") }
        return .notForMe("no command word or app name at the start")
    }

    /// The reason if the text starts with a command word or an app name, else nil.
    func prefixReason(_ words: [String], apps: [AppEntry]) -> String? {
        if config.commandWords.contains(words[0]) { return "command word \"\(words[0])\"" }
        for app in apps where app.approved && app.enabled {
            for spoken in [app.name] + app.aliases {
                let n = SafetyPolicy.normalize(spoken).split(separator: " ").map(String.init)
                if !n.isEmpty, words.starts(with: n) { return "app name \"\(spoken)\"" }
            }
        }
        return nil
    }
}
