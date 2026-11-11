import EarshotCore
import Foundation

// Spoken keys and "undo that" in the command path (I-34, D-13). The action module checks the focused field
// (KeyRules). This file holds the rules that need the state of the pipeline: the voice of the turn and the last typing.
extension CommandPipeline {
    /// "Undo that" works only within this time after the typing.
    static let undoSeconds: TimeInterval = 120

    /// The intent to run, or the reason to block it. Other intents pass as they are.
    /// - "new line" (Return) in always-on mode needs the owner's checked voice. A chain gives `ownerVoice: false`, so an
    ///   always-on chain never presses Return. The action module also blocks Return in a message box (R-NV-5, D-12).
    /// - "undo that" gets the text of the last typing, only if the same app is in front and the typing is recent.
    ///   Never across apps.
    func keyRule(_ intent: Intent, mode: InputMode, ownerVoice: Bool, front: String?, now: Date) -> (intent: Intent, block: String?) {
        switch intent {
        case .pressKey(.newLine, _):
            if mode == .alwaysOn, !ownerVoice { return (intent, "new line needs the hold key, or your checked voice") }
            return (intent, nil)
        case .undoTyping:
            guard let t = lastTyped, let text = lastTypedText, !text.isEmpty else { return (intent, "nothing that earshot typed to undo") }
            guard t.app != nil, t.app == front else { return (intent, "earshot typed in another app: undo works only there") }
            guard now.timeIntervalSince(t.at) <= Self.undoSeconds else { return (intent, "too late to undo the last typing") }
            return (.undoTyping(text), nil)
        default:
            return (intent, nil)
        }
    }

    /// After "undo that" worked, the text is gone: forget it, so a second "undo that" or a "send" does nothing.
    func afterKey(_ intent: Intent, ok: Bool) {
        guard ok, case .undoTyping = intent else { return }
        lastTypedText = nil
        forgetTyping()
    }

    /// The text that a typing intent types, for "undo that".
    static func typedText(_ intent: Intent) -> String? {
        switch intent {
        case .typeText(let t), .typeInto(_, let t): return t
        case .openChat(_, _, let t): return t
        default: return nil
        }
    }
}
