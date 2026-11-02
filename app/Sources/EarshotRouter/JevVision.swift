import EarshotCore
import Foundation

/// The screenshot fallback for clicks with Jev (D-10). Jev runs in the cloud.
///
/// The owner turns it on with its own setting ("Jev sees the screen"). It is off by default, separate from tier 2.
/// It sends the command words and one JPEG of the front window with the "show numbers" numbers drawn on it.
/// It asks two questions in one request: which number marks the target (choice), and where the target is (box).
/// The box is used only if Jev picks no number. It sends no audio. It returns `.none` after the budget or on an error.
/// The key comes from the caller (the Keychain). This type never logs the key or the picture.
public final class JevScreenPicker: ScreenPicker, @unchecked Sendable {
    public static let endpoint = JevChooser.endpoint
    public typealias Transport = JevChooser.Transport

    public let model: String
    private let key: String
    private let transport: Transport

    static let asset = "earshot-front-window"
    static let goal = "Pick the number on the screenshot that marks the element that the owner's voice command asks for."
    static let rules = """
    The screenshot shows the front window of the owner's Mac. Yellow badges with numbers are drawn at the top left \
    of the elements that earshot can click. The command comes from speech to text, so words can be heard wrong. \
    A command can name only part of a label, or describe the element by its look or its place. \
    Pick the number whose element the command asks for. If no number marks that element, pick none.
    """
    static let boxRule = "Locate the one element on the screenshot that the owner's voice command asks for. "
        + "The command is: "
    static let noneID = "none"
    static let noneLabel = "None: no number marks the element that the command asks for"

    public init(apiKey: String, model: String = "jev-latest", transport: Transport? = nil) {
        key = apiKey
        self.model = model
        if let transport {
            self.transport = transport
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 5
            config.urlCache = nil
            let session = URLSession(configuration: config)
            self.transport = { request in
                let (data, response) = try await session.data(for: request)
                return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
            }
        }
    }

    public func pick(_ command: String, shot: VisionShot, budgetMs: Int) async -> VisionPick {
        guard !shot.jpeg.isEmpty, let request = try? makeRequest(command, shot: shot) else { return .none }
        let marks = shot.marks
        let send = transport
        return await withBudget(budgetMs) { () -> VisionPick? in
            guard let reply = try? await send(request), reply.1 == 200 else { return nil }
            return Self.parse(reply.0, marks: marks)
        } ?? .none
    }

    /// The request: the command words and the picture in `state`, a choice over the drawn numbers, and a box question.
    func makeRequest(_ command: String, shot: VisionShot) throws -> URLRequest {
        var criteria: [String: Any] = [:]
        for n in shot.marks { criteria["n\(n)"] = ["label": "number \(n)"] }
        criteria[Self.noneID] = ["label": Self.noneLabel]
        let body: [String: Any] = [
            "model": model,
            "state": ["command": command, "screenshot": Self.asset],
            "questions": [
                "mark": ["type": "choice", "criteria": criteria, "instructions": ["goal": Self.goal, "rules": Self.rules]],
                "where": ["type": "box", "instructions": Self.boxRule + "\"\(command)\""],
            ],
            "assets": [Self.asset: ["type": "image", "format": "jpeg", "data_base64": shot.jpeg.base64EncodedString()]],
        ]
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        // The API asks for this header for image assets and box questions.
        request.setValue("true", forHTTPHeaderField: "TypeSafe-Danger-Zone-Images")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// Reads the answer. A number wins if the choice checks pass (JevChooser.parse) and the number was drawn.
    /// Else a box, if its edges are fractions in order. Else `.none`.
    static func parse(_ data: Data, marks: [Int]) -> VisionPick {
        let ids = marks.map { "n\($0)" } + [noneID]
        if let choice = try? JevChooser.parse(data, ids: ids, question: "mark"), choice != noneID,
           let n = Int(choice.dropFirst()), marks.contains(n) {
            return .mark(n)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = root["answers"] as? [String: Any],
              let a = answers["where"] as? [String: Any],
              let box = a["box"] as? [String: Any] else { return .none }
        func edge(_ k: String) -> Double? { (box[k] as? NSNumber)?.doubleValue }
        guard let t = edge("top"), let l = edge("left"), let b = edge("bottom"), let r = edge("right"),
              [t, l, b, r].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }), b > t, r > l else { return .none }
        return .box(top: t, left: l, bottom: b, right: r)
    }
}

/// Makes the screenshot picker for the owner's settings.
public enum ScreenPickerFactory {
    /// Nil if the setting is off (the default) or if there is no key. Nil keeps every picture on the Mac (R-MD-1).
    public static func make(_ settings: EarshotSettings, jevKey: String?) -> ScreenPicker? {
        guard settings.jevSeesScreen,
              let key = jevKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return JevScreenPicker(apiKey: key)
    }
}
