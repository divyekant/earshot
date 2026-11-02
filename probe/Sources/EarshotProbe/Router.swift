import Foundation

/// The result of routing one utterance. No model is used (tier 0 rules, R-SP-2).
struct Command {
    let app: AppRow
    let person: Person?
    /// The words heard for the name, when no known person matched.
    let unmatchedName: String?
    let text: String?
    let nameScore: Double

    var describe: String {
        var s = app.name
        if let p = person { s += " · \(p.me ? "me" : p.name)" }
        if let n = unmatchedName { s += " · ?\(n)" }
        if let t = text { s += " · \"\(t)\"" }
        return s
    }
}

struct Router {
    let apps: [AppRow]
    let people: [Person]

    private struct Token {
        let raw: String
        let key: String
        let boundaryAfter: Bool
    }

    private static let fillers: Set<String> = ["hey", "ok", "okay", "earshot", "please", "open", "go", "to", "switch"]
    private static let verbs: Set<String> = ["message", "text", "ping", "dm", "send", "write", "tell"]
    private static let textLeads: Set<String> = ["saying", "say", "that"]

    func route(_ utterance: String) -> Command? {
        var tokens = Self.tokenize(utterance)
        while let first = tokens.first, Self.fillers.contains(first.key) { tokens.removeFirst() }
        guard !tokens.isEmpty else { return nil }

        // Form B: "message Ravi on Slack, running late". It must start with a verb.
        if Self.verbs.contains(tokens[0].key), let found = findOnApp(tokens), found.0 > 1 {
            let (onIndex, app, aliasLength) = found
            let nameTokens = Array(tokens[1..<onIndex])
            let rest = Array(tokens[(onIndex + 1 + aliasLength)...])
            return build(app: app, nameTokens: nameTokens, rest: rest, exactName: true)
        }

        // Form A: "<app> <name>[,] [text]".
        guard let matched = matchApp(tokens, at: 0) else { return nil }
        let (app, aliasLength) = matched
        let after = Array(tokens[aliasLength...])
        if after.isEmpty {
            return Command(app: app, person: nil, unmatchedName: nil, text: nil, nameScore: 0)
        }
        return build(app: app, nameTokens: after, rest: [], exactName: false)
    }

    // MARK: - Steps

    private func build(app: AppRow, nameTokens: [Token], rest: [Token], exactName: Bool) -> Command {
        if let match = matchPerson(nameTokens, allowPrefix: !exactName) {
            let (person, used, score) = match
            let textTokens = Array(nameTokens[used...]) + rest
            return Command(app: app, person: person, unmatchedName: nil, text: Self.joinText(textTokens), nameScore: score)
        }
        // No known person. Keep the first words as the heard name. Do not type anything.
        let headLength = min(exactName ? nameTokens.count : 1, nameTokens.count)
        let heard = nameTokens.prefix(headLength).map(\.raw).joined(separator: " ")
        return Command(app: app, person: nil, unmatchedName: Self.clean(heard), text: nil, nameScore: 0)
    }

    private func matchApp(_ tokens: [Token], at index: Int) -> (AppRow, Int)? {
        var best: (AppRow, Int)?
        for length in stride(from: min(3, tokens.count - index), through: 1, by: -1) {
            let phrase = tokens[index..<(index + length)].map(\.key).joined()
            for app in apps where app.aliases.contains(where: { Text.key($0) == phrase }) {
                if best == nil { best = (app, length) }
            }
            if best != nil { break }
        }
        return best
    }

    private func findOnApp(_ tokens: [Token]) -> (Int, AppRow, Int)? {
        for i in tokens.indices where tokens[i].key == "on" && i + 1 < tokens.count {
            if let m = matchApp(tokens, at: i + 1) { return (i, m.0, m.1) }
        }
        return nil
    }

    /// Tries the first 1 to 3 words as a name. A comma or full stop ends the name.
    private func matchPerson(_ tokens: [Token], allowPrefix: Bool) -> (Person, Int, Double)? {
        guard !tokens.isEmpty else { return nil }
        var best: (Person, Int, Double)?
        let maxLength = allowPrefix ? min(3, tokens.count) : tokens.count
        for length in 1...maxLength {
            let phrase = tokens.prefix(length).map(\.key).joined()
            for person in people {
                var candidates = [person.name] + (person.aliases ?? [])
                // A name that one app shows in place of the spoken name.
                candidates += person.handles.values.filter { $0 != "-" && !$0.contains(where: \.isNumber) && !$0.contains("@") }
                for candidate in candidates {
                    let score = Text.similarity(phrase, Text.key(candidate))
                    guard score >= 0.75 else { continue }
                    if best == nil || score > best!.2 || (score == best!.2 && length > best!.1) {
                        best = (person, length, score)
                    }
                }
            }
            if tokens[length - 1].boundaryAfter { break }
        }
        return best
    }

    // MARK: - Text helpers

    private static func tokenize(_ s: String) -> [Token] {
        s.split(whereSeparator: { $0.isWhitespace }).compactMap { piece in
            let raw = String(piece)
            let key = Text.key(raw)
            guard !key.isEmpty else { return nil }
            let boundary = raw.last.map { ",.;:!?".contains($0) } ?? false
            return Token(raw: raw, key: key, boundaryAfter: boundary)
        }
    }

    private static func joinText(_ tokens: [Token]) -> String? {
        var t = tokens
        while let first = t.first, textLeads.contains(first.key) { t.removeFirst() }
        let joined = clean(t.map(\.raw).joined(separator: " "))
        return joined.isEmpty ? nil : joined
    }

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:-\u{2014} ").union(.whitespacesAndNewlines))
    }
}
