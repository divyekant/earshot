import EarshotCore
import Foundation

/// Short texts for intents, for the Test tab and the feedback note (R-FB-1), for example "→ Slack · Ravi".
public enum IntentText {
    public static func describe(_ intent: Intent, apps: [AppEntry] = [], screen: ScreenSnapshot? = nil) -> String {
        func app(_ id: String) -> String { apps.first { $0.id == id }?.name ?? id }
        func element(_ id: String) -> String {
            guard let e = screen?.elements.first(where: { $0.id == id }) else { return id }
            return e.label.isEmpty ? id : "\"\(e.label)\""
        }
        switch intent {
        case .none: return "Nothing to do"
        case .openApp(let id): return "→ \(app(id))"
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
        }
    }

    /// True if the result is below the confidence line. The app then shows the result and does nothing.
    public static func belowLine(_ route: RouteResult) -> Bool { route.confidence < SafetyPolicy.minimumConfidence }
}
