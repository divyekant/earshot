import EarshotCore
import Foundation

// Gap item 13 (2026-11-11): the talk state. Before, the pipeline kept the state between turns in seven separate
// variables (armedUntil, pendingChain, pendingChoice, keptText, lastTyped, lastTypedText, lastTypedAlwaysOn).
// Two waits could be set at the same time, and no code said which one the next turn used.
// Now one value holds it, with named states. docs/DESIGN.md, section 3.9, describes the states.

/// What the next turn can mean, and the last typing. Memory only: never in the log and never on disk.
struct TalkState {
    /// The one thing that the next turn can answer. A new wait replaces the old one, because the note on screen
    /// shows only the newest question.
    enum Wait {
        /// No wait. The next turn is a new command.
        case none
        /// After a bare "type" (R-NV-4): the next turn that starts before `until` is text for the focused field,
        /// unless its first sentence is a command.
        case text(until: Date)
        /// A chain stopped at a step (I-28): the next turn can say "go on", "stop", "yes" or the step again.
        case chainAnswer(CommandPipeline.PendingChain)
        /// A "not sure" note shows its choices (gap item 5): the next turn can say "yes", "the second one" or "no".
        case choiceAnswer(CommandPipeline.PendingChoice)
        /// The voice check dropped a wake turn (gap item 7): one hold-key press with no words types its words.
        case keptWords(KeptText)
    }

    /// The named state. The tests and DESIGN 3.9 use these names.
    enum Name: String, CaseIterable {
        case idle = "idle"
        case waitsForText = "waits for text"
        case waitsForChainAnswer = "waits for a chain answer"
        case waitsForChoiceAnswer = "waits for a choice answer"
        case keepsDroppedWords = "keeps dropped words"
    }

    /// The last typing that worked. "send" alone (D-12), go-on typing and "undo that" (I-34) use it.
    struct Typing {
        var at: Date
        /// The front app of the typing. Nil if earshot did not know it.
        var app: String?
        /// The typed text, for "undo that". Nil after the undo.
        var text: String?
        /// True if the typing was in always-on mode. Only then can the next turn go on with the text.
        var alwaysOn: Bool
    }

    private(set) var wait: Wait = .none
    var lastTyping: Typing?

    /// The end of the wait, or nil if no wait has an end time.
    var until: Date? {
        switch wait {
        case .none: return nil
        case .text(let until): return until
        case .chainAnswer(let chain): return chain.until
        case .choiceAnswer(let choice): return choice.until
        case .keptWords(let kept): return kept.until
        }
    }

    /// The named state at `now`. A wait whose time is over is idle.
    func name(at now: Date) -> Name {
        if let until, now > until { return .idle }
        switch wait {
        case .none: return .idle
        case .text: return .waitsForText
        case .chainAnswer: return .waitsForChainAnswer
        case .choiceAnswer: return .waitsForChoiceAnswer
        case .keptWords: return .keepsDroppedWords
        }
    }

    /// Sets a new wait. It replaces the old wait.
    mutating func set(_ wait: Wait) { self.wait = wait }

    /// Ends the wait.
    mutating func clear() { wait = .none }

    // The parts of the wait, by state. Each getter is nil if the wait is in another state. Each setter with nil
    // ends the wait only if it is in that state, so one part cannot end another wait.

    var textUntil: Date? {
        get { if case .text(let until) = wait { return until }; return nil }
        set { if let newValue { wait = .text(until: newValue) } else if textUntil != nil { wait = .none } }
    }

    var chain: CommandPipeline.PendingChain? {
        get { if case .chainAnswer(let chain) = wait { return chain }; return nil }
        set { if let newValue { wait = .chainAnswer(newValue) } else if chain != nil { wait = .none } }
    }

    var choice: CommandPipeline.PendingChoice? {
        get { if case .choiceAnswer(let choice) = wait { return choice }; return nil }
        set { if let newValue { wait = .choiceAnswer(newValue) } else if choice != nil { wait = .none } }
    }

    var kept: KeptText? {
        get { if case .keptWords(let kept) = wait { return kept }; return nil }
        set { if let newValue { wait = .keptWords(newValue) } else if kept != nil { wait = .none } }
    }
}

// The names that the pipeline and its extensions used before the talk state. They read and write `talk`.
extension CommandPipeline {
    /// The end of the armed window after a bare "type", or nil when not armed.
    var armedUntil: Date? {
        get { talk.textUntil }
        set { talk.textUntil = newValue }
    }

    /// A chain of commands that stopped at a step (I-28), or nil.
    var pendingChain: PendingChain? {
        get { talk.chain }
        set { talk.chain = newValue }
    }

    /// The choices of a "not sure" note for one command (CommandPipeline+Answer.swift), or nil.
    var pendingChoice: PendingChoice? {
        get { talk.choice }
        set { talk.choice = newValue }
    }

    /// The words of the last wake turn that the voice check dropped (CommandPipeline+Dropped.swift), or nil.
    var keptText: KeptText? {
        get { talk.kept }
        set { talk.kept = newValue }
    }

    /// The last typing that worked: the time and the front app. Nil after a send or an undo.
    var lastTyped: (at: Date, app: String?)? {
        talk.lastTyping.map { (at: $0.at, app: $0.app) }
    }

    /// The text of the last typing, for "undo that" (I-34).
    var lastTypedText: String? {
        get { talk.lastTyping?.text }
        set { talk.lastTyping?.text = newValue }
    }

    /// True if the last typing was in always-on mode.
    var lastTypedAlwaysOn: Bool { talk.lastTyping?.alwaysOn ?? false }

    /// The named talk state now.
    var talkStateName: TalkState.Name { talk.name(at: now()) }
}
