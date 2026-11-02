import EarshotCore
import Foundation

/// Makes the tier-2 chooser for the owner's settings.
public enum Tier2Factory {
    /// Nil if tier 2 is off (the default) or if there is no key. Nil keeps all decisions on the Mac (R-MD-1).
    public static func make(_ settings: EarshotSettings, jevKey: String?) -> Tier2Chooser? {
        switch settings.tier2 {
        case .off: return nil
        case .jev:
            guard let key = jevKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
            return JevChooser(apiKey: key)
        }
    }
}

/// Tier 2 with Jev, the TypeSafe "systemone" model. Jev runs in the cloud. Ported from probe Jev.swift (E1, E2).
///
/// The owner turns it on in the settings. It is off by default (R-MD-1, D-9).
/// It sends text only: the command words and the labels of the short list. It sends no audio, no screenshot
/// and no text from the apps. It returns nil after the budget, on an error, or for "none of these".
/// The caller then keeps the rules answer. The key comes from the caller (the Keychain); this type never logs it.
public final class JevChooser: Tier2Chooser, @unchecked Sendable {
    public static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    /// Sends one request and returns the body and the HTTP status. Tests replace it.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    public let model: String
    private let key: String
    private let transport: Transport

    static let goal = "Pick the option that the owner's voice command asks for."
    static let rules = """
    The command comes from speech to text, so words and names can be heard wrong. \
    "Me", "myself" or "my own chat" means the owner's own chat. \
    If the command names an app, pick an option in that app. \
    A command can name only part of a label. \
    If the command asks only to open or switch to an app, pick the app option. \
    Do not pick an option only because it is the closest option. \
    If no option has the meaning of the command, or the words are not a command, pick none.
    """
    static let noneID = "none"
    static let noneLabel = "None: the words do not ask for any of these options"

    public init(apiKey: String, model: String = "jev-latest", transport: Transport? = nil) {
        key = apiKey
        self.model = model
        if let transport {
            self.transport = transport
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 5
            config.urlCache = nil
            // One session for all calls, so that the connection stays open between calls.
            let session = URLSession(configuration: config)
            self.transport = { request in
                let (data, response) = try await session.data(for: request)
                return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
            }
        }
    }

    public func choose(_ text: String, options: [String], budgetMs: Int) async -> Int? {
        guard !options.isEmpty, let request = try? makeRequest(text, options: options) else { return nil }
        let ids = options.indices.map { "o\($0 + 1)" } + [Self.noneID]
        let send = transport
        return await withBudget(budgetMs) {
            guard let reply = try? await send(request), reply.1 == 200,
                  let choice = try? Self.parse(reply.0, ids: ids), choice != Self.noneID,
                  let i = ids.firstIndex(of: choice) else { return nil }
            return i
        }
    }

    /// The request body: the model, the command words, and one criterion for each option label.
    func makeRequest(_ text: String, options: [String]) throws -> URLRequest {
        var criteria: [String: Any] = [:]
        for (i, label) in options.enumerated() { criteria["o\(i + 1)"] = ["label": label] }
        criteria[Self.noneID] = ["label": Self.noneLabel]
        let body: [String: Any] = [
            "model": model,
            "state": ["command": text],
            "questions": ["route": ["type": "choice", "criteria": criteria,
                                    "instructions": ["goal": Self.goal, "rules": Self.rules]]],
        ]
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    struct BadAnswer: Error { let why: String }

    /// Reads the choice and checks it with the rules of the probe: the choice is one of the ids,
    /// the probabilities cover exactly the ids, each is in 0...1, they add up to 1 (± 0.02),
    /// and the chosen option has the highest probability.
    static func parse(_ data: Data, ids: [String], question: String = "route") throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = root["answers"] as? [String: Any],
              let a = answers[question] as? [String: Any],
              let choice = a["choice"] as? String else { throw BadAnswer(why: "no choice") }
        guard ids.contains(choice) else { throw BadAnswer(why: "unknown option") }
        let probs = (a["probabilities"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        guard Set(probs.keys) == Set(ids) else { throw BadAnswer(why: "probabilities do not match the options") }
        guard probs.values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else { throw BadAnswer(why: "probability out of range") }
        guard abs(probs.values.reduce(0, +) - 1) <= 0.02 else { throw BadAnswer(why: "probabilities do not add up to 1") }
        guard let top = probs.values.max(), probs[choice] == top else { throw BadAnswer(why: "choice is not the most probable") }
        return choice
    }
}
