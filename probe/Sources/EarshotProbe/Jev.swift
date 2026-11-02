import Foundation

/// A client for Jev, the TypeSafe "systemone" model. Jev runs in the cloud.
///
/// E1 sends text only: the command words and the option labels. It sends no audio,
/// no screenshot and no message text from the apps. The owner approved this for E1 only.
/// R-MD-1 does not change unless the owner decides so after E1.
final class JevClient {
    static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    static let keyName = "TYPESAFE_API_KEY"
    /// The file that jev-qa reads the key from.
    static var keyFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/jev-qa/env")
    }

    private let key: String
    let model: String
    /// One session for all calls, so that the HTTP/2 connection stays open between calls.
    private let session: URLSession

    init() throws {
        key = try JevClient.loadKey()
        model = ProcessInfo.processInfo.environment["TYPESAFE_MODEL"] ?? "jev-latest"
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    /// Reads the key from the TYPESAFE_API_KEY environment variable, else from ~/.config/jev-qa/env.
    /// The probe never prints, logs or saves the key.
    static func loadKey() throws -> String {
        if let k = ProcessInfo.processInfo.environment[keyName]?.trimmingCharacters(in: .whitespaces), !k.isEmpty {
            return k
        }
        if let text = try? String(contentsOf: keyFile, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                var l = line.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("export ") { l = String(l.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
                guard l.hasPrefix("\(keyName)=") else { continue }
                var v = String(l.dropFirst(keyName.count + 1)).trimmingCharacters(in: .whitespaces)
                if v.count >= 2, let first = v.first, first == v.last, first == "\"" || first == "'" {
                    v = String(v.dropFirst().dropLast())
                }
                if !v.isEmpty { return v }
            }
        }
        throw ProbeError("no Jev key. Set \(keyName), or put it in ~/.config/jev-qa/env")
    }

    struct Answer {
        let choice: String
        let confidence: Double
        let probabilities: [String: Double]
        let ms: Double
        let tries: Int
        let inputTokens: Int?
        let outputTokens: Int?
        let modelVersion: String?
    }

    /// Asks one "choice" question. Jev picks one option id.
    /// It tries again on HTTP 429, 503 and 529, after 0.5 s and then 1.0 s, as jev-qa does.
    func choose(id: String, options: [(id: String, label: String)], goal: String, rules: String,
                state: [String: Any]) async throws -> Answer {
        var criteria: [String: Any] = [:]
        for o in options { criteria[o.id] = ["label": o.label] }
        let body: [String: Any] = [
            "model": model,
            "state": state,
            "questions": [id: ["type": "choice", "criteria": criteria,
                               "instructions": ["goal": goal, "rules": rules]]],
        ]
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let t0 = Clock.nowNs()
        var tries = 0
        let waits = [500, 1000]
        while true {
            tries += 1
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if [429, 503, 529].contains(status), tries <= waits.count {
                await sleepMs(waits[tries - 1])
                continue
            }
            guard status == 200 else {
                // The error body holds no secret. Cut it short.
                let text = String(data: data.prefix(300), encoding: .utf8) ?? ""
                throw ProbeError("Jev HTTP \(status): \(text)")
            }
            let ms = Clock.ms(since: t0)
            return try Self.parse(data, question: id, ids: options.map(\.id), ms: ms, tries: tries)
        }
    }

    /// Reads the answer and checks it with the same rules as jev-qa: the choice is one of the ids,
    /// the probabilities cover exactly the ids, each is in 0...1, they add up to 1 (± 0.02),
    /// and the chosen option has the highest probability.
    static func parse(_ data: Data, question: String, ids: [String], ms: Double, tries: Int) throws -> Answer {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = root["answers"] as? [String: Any],
              let a = answers[question] as? [String: Any],
              let choice = a["choice"] as? String else {
            throw ProbeError("Jev answer has no choice")
        }
        let probs = (a["probabilities"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        guard ids.contains(choice) else { throw ProbeError("Jev chose an unknown option: \(choice)") }
        guard Set(probs.keys) == Set(ids) else { throw ProbeError("Jev probabilities do not match the options") }
        guard probs.values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else { throw ProbeError("Jev probability out of range") }
        let sum = probs.values.reduce(0, +)
        guard abs(sum - 1) <= 0.02 else { throw ProbeError("Jev probabilities add up to \(sum)") }
        guard let top = probs.values.max(), probs[choice] == top else { throw ProbeError("Jev choice is not the most probable option") }
        let usage = root["usage"] as? [String: Any]
        return Answer(choice: choice,
                      confidence: (a["confidence"] as? NSNumber)?.doubleValue ?? 0,
                      probabilities: probs, ms: ms, tries: tries,
                      inputTokens: (usage?["input_tokens"] as? NSNumber)?.intValue,
                      outputTokens: (usage?["output_tokens"] as? NSNumber)?.intValue,
                      modelVersion: root["model"] as? String)
    }

    /// One call with no personal data. It opens the connection, so that later calls are warm.
    func warmUp() async throws -> Answer {
        try await choose(id: "fruit", options: [("apple", "apple"), ("banana", "banana")],
                         goal: "Which fruit is red?", rules: "", state: [:])
    }
}
