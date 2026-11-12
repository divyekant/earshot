import EarshotCore
import Foundation

/// Short texts for intents, for the Test tab and the feedback note (R-FB-1), for example "→ Slack · Ravi".
public enum IntentText {
    public static func describe(_ intent: Intent, apps: [AppEntry] = [], screen: ScreenSnapshot? = nil) -> String {
        func app(_ id: String) -> String { apps.first { $0.id == id }?.name ?? id }
        func element(_ id: String) -> String {
            if let path = MenuElements.path(id) { return "menu " + path.joined(separator: " › ") }
            guard let e = screen?.elements.first(where: { $0.id == id }) else { return id }
            return e.label.isEmpty ? id : "\"\(e.label)\""
        }
        switch intent {
        case .none: return "Nothing to do"
        case .openApp(let id): return "→ \(app(id))"
        case .openURL(let address): return "Open \(URL(string: address)?.host ?? address)"
        case .openChat(let id, let target, let text):
            let base = "→ \(app(id)) · \(target)"
            guard let text, !text.isEmpty else { return base }
            return "\(base) · type \"\(text)\""
        case .click(let id): return "Click \(element(id))"
        case .typeInto(let id, let text): return "Type \"\(text)\" in \(element(id))"
        case .typeText(let text): return "Type \"\(text)\""
        case .scroll(let d): return "Scroll \(d.rawValue)"
        case .back: return "Back"
        case .showNumbers: return "Show numbers"
        case .hideNumbers: return "Hide numbers"
        case .send: return "Send"
        case let .pressKey(key, times): return "Press \(KeyText.name(key))" + (times > 1 ? " \(times) times" : "")
        // The typed text stays out of the note and the log: only its length.
        case .undoTyping(let text): return text.isEmpty ? "Undo the last typing" : "Undo the last typing (\(text.count) characters)"
        case .handOff(let id, let lead, _): return "→ plugin \(id) · \"\(lead)\""
        case let .openTarget(id, name, _): return "Open \(name) (plugin \(id))"
        }
    }

    /// The spoken name of a key, for the note.
    public enum KeyText {
        public static func name(_ key: SpokenKey) -> String {
            switch key {
            case .backspace: return "Backspace"
            case .forwardDelete: return "Forward Delete"
            case .newLine: return "Return"
            case .tab: return "Tab"
            case .escape: return "Escape"
            case .left: return "Left Arrow"
            case .right: return "Right Arrow"
            case .up: return "Up Arrow"
            case .down: return "Down Arrow"
            }
        }
    }

    /// True if the result is below the confidence line. The app then shows the result and does nothing.
    public static func belowLine(_ route: RouteResult) -> Bool { route.confidence < SafetyPolicy.minimumConfidence }
}
