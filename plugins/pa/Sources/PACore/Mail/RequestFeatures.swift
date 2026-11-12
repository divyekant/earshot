import Foundation

/// Step 2 of the request flags (phase 3 build spec, 8.4): prepare the text, cut it into sentences, and give each
/// sentence and each message its features. The PA selects a sentence of the mail. It writes no text.
public enum RequestFeatures {
    /// One candidate sentence, as written in the text.
    public struct Sentence: Equatable, Sendable {
        public var text: String
        /// The features of section 8.4, each 0 or 1.
        public var f: [Double]
    }

    /// The prepared message.
    public struct Prepared: Sendable {
        public var sentences: [Sentence]
        /// The name in the greeting ("Hi Maya," gives "maya"), in lower case, or nil.
        public var greeting: String?
        /// The length of the prepared text in characters.
        public var length: Int
    }

    public static let sentenceNames = ["question", "please", "command", "duty", "time", "owner name", "past", "no action",
                                       "third person", "help offer", "question mark", "you"]

    static let questionStarts = ["can you", "could you", "would you", "will you", "are you able", "do you have",
                                 "when can you", "are you", "do you", "did you", "have you", "which", "what time",
                                 "when will you", "would it be"]
    static let commands: Set<String> = ["send", "call", "confirm", "sign", "pay", "bring", "check", "review", "reply",
                                        "book", "fill", "return", "update", "share", "pick", "let", "remember", "renew",
                                        "collect", "choose", "forward", "print", "read", "tell", "ring", "text", "email",
                                        "submit", "complete", "order", "arrange", "add"]
    static let duty = ["need you to", "i need", "we need", "you must", "you have to", "required", "make sure",
                       "do not forget", "don't forget", "please remember", "you need to", "is due"]
    static let timeWords = [" by ", " before ", " until ", "no later than", "as soon as possible", "asap", " today",
                            " tomorrow", " tonight", "this week", "next week", "end of the", " monday", " tuesday",
                            " wednesday", " thursday", " friday", " saturday", " sunday", "january", "february",
                            "march", "april", " may ", "june", "july", "august", "september", "october", "november",
                            "december", " pm", " am", "o'clock", " noon"]
    static let past = ["thanks for", "thank you for", "i sent", "we sent", "i have sent", "already", "was sent",
                       "we received", "you sent", "i paid", "we got", "has been", "have been", "is done", "is now"]
    static let noAction = ["no need to", "no action", "nothing to do", "you do not need", "you don't need",
                           "ignore this", "no reply"]
    static let help = ["let me know if you have", "feel free to", "if you have any questions", "happy to help",
                       "if you need", "let us know if", "any questions", "here to help", "in case you"]
    static let ads = ["buy now", "shop now", "order now", "subscribe", "unsubscribe", "sale ends", "% off", "free delivery",
                      "offer ends", "click here", "limited time"]

    /// Removes quoted old mail, the signature and small print (8.4).
    public static func prepare(_ body: String) -> [String] {
        var out: [String] = []
        for raw in body.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let low = line.lowercased()
            if line.hasPrefix(">") { continue }
            if low.hasPrefix("on "), low.hasSuffix("wrote:") { break }
            if low.hasPrefix("-----original message") || low.hasPrefix("---------- forwarded") { break }
            if line == "--" || raw.hasPrefix("-- ") || low.hasPrefix("sent from my") { break }
            if low.contains("this email and any attachments") || low.contains("confidential and intended") { continue }
            out.append(line)
        }
        return out
    }

    static func has(_ s: String, _ list: [String]) -> Bool { list.contains { s.contains($0) } }

    /// "Hi Maya," or "Dear Maya Rao," gives the first name in lower case.
    static func greetingName(_ line: String) -> String? {
        let w = line.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard w.count >= 2, w.count <= 4, line.hasSuffix(",") || line.hasSuffix("!"),
              ["hi", "hello", "dear", "hey", "morning", "evening", "afternoon"].contains(w[0].lowercased()) else { return nil }
        let n = w[1].lowercased()
        return ["all", "everyone", "team", "customer", "member", "parents", "friends", "there", "folks"].contains(n) ? "*" : n
    }

    /// The features of one sentence. `owner` has the owner names in lower case.
    public static func sentenceFeatures(_ s: String, owner: Set<String>, timeFound: Bool) -> [Double] {
        let low = " " + s.lowercased() + " "
        let words = EventLinker.words(s)
        let first = words.first ?? ""
        let question = s.hasSuffix("?") && (has(low, questionStarts.map { " " + $0 }) || words.contains("you"))
        let please = low.contains("please")
        let command = commands.contains(first) || (first == "please" && words.count > 1 && commands.contains(words[1]))
        let dutyHit = has(low, duty)
        let time = timeFound || has(low, timeWords)
        let ownerName = words.contains { owner.contains($0) }
        let pastHit = has(low, past)
        let noAct = has(low, noAction)
        // "Amara, could you ..." or "I asked Tom to": a request to another person.
        var third = low.contains(" asked ") && low.contains(" to ")
        if let comma = s.firstIndex(of: ","), s.distance(from: s.startIndex, to: comma) < 15 {
            let head = s[..<comma]
            if head.split(separator: " ").count == 1, let c = head.first, c.isUppercase,
               !owner.contains(head.lowercased()), !["Hi", "Hello", "Dear", "Also", "So", "Yes", "No", "Thanks", "Ok", "OK", "Well"].contains(String(head)) {
                third = true
            }
        }
        let helpHit = has(low, help) || has(low, ads)
        return [question, please, command, dutyHit, time, ownerName, pastHit, noAct, third, helpHit, s.hasSuffix("?"),
                words.contains("you") || words.contains("your")].map { $0 ? 1 : 0 }
    }

    /// The prepared message with its candidate sentences. The greeting and the sign-off are not candidates.
    public static func prepared(_ m: MailMessage, owner: Set<String>, time: (String) -> Bool = { _ in false }) -> Prepared {
        let lines = prepare(m.text)
        var greeting: String?
        var sents: [Sentence] = []
        var length = 0
        for (i, line) in lines.enumerated() where !line.isEmpty {
            length += line.count
            if i < 3, greeting == nil, let g = greetingName(line) { greeting = g; continue }
            let wc = line.split(separator: " ").count
            if wc <= 3, line.hasSuffix(",") || !line.contains(" ") || line.first?.isUppercase == true && !".!?".contains(line.last ?? " ") {
                continue
            }
            for s in TextCut.sentences(line) where s.split(separator: " ").count >= 3 {
                sents.append(Sentence(text: s, f: sentenceFeatures(s, owner: owner, timeFound: time(s))))
            }
        }
        return Prepared(sentences: sents, greeting: greeting, length: length)
    }

    // MARK: - Variant A: points by hand

    /// Points by hand for one sentence (variant A).
    public static func handScore(_ f: [Double]) -> Double {
        let w: [Double] = [3, 1, 2, 3, 1, 1, -3, -4, -4, -3, 1, 1]
        return zip(w, f).map(*).reduce(0, +)
    }

    /// The message features (8.4) for variant B: the features of the best sentence, then the message facts.
    public static func messageFeatures(_ m: MailMessage, _ p: Prepared, best: Int?, sentenceScores: [Double],
                                       owner: Set<String>, ownerAddresses: Set<String>, middle: Double) -> [Double] {
        var v = best.map { p.sentences[$0].f } ?? Array(repeating: 0, count: sentenceNames.count)
        v.append(best.map { sentenceScores[$0] } ?? -5)
        v.append(Double(sentenceScores.filter { $0 >= middle }.count))
        let to = Set(m.to.map { $0.lowercased() })
        v.append(to.isDisjoint(with: ownerAddresses) ? 0 : 1)
        v.append(Double(m.to.count + m.cc.count) / 10)
        let from = m.fromAddress.lowercased()
        v.append(from.contains("noreply") || from.contains("no-reply") || from.contains("donotreply") ? 1 : 0)
        v.append(m.subject.lowercased().hasPrefix("re:") ? 1 : 0)
        v.append(min(Double(p.length) / 1000, 3))
        v.append(p.greeting.map { owner.contains($0) ? 1 : 0 } ?? 0)
        v.append(p.greeting.map { !owner.contains($0) && $0 != "*" ? 1 : 0 } ?? 0)
        v.append(p.greeting == "*" ? 1 : 0)
        v.append(1)
        return v
    }

    public static let messageNames = sentenceNames.map { "best " + $0 } + ["best score", "count above middle", "owner in To",
        "addresses / 10", "noreply", "Re:", "length / 1000", "greets owner", "greets another", "greets a group", "bias"]
}

/// A logistic regression with an L2 penalty toward start weights (8.8 uses the same form). Plain gradient descent.
public struct Logistic: Codable, Equatable, Sendable {
    public var w: [Double]
    /// Feature scale: the mean and the spread of each feature on the fit data.
    public var mean: [Double]
    public var scale: [Double]

    public init(w: [Double], mean: [Double], scale: [Double]) { self.w = w; self.mean = mean; self.scale = scale }

    static func sigmoid(_ z: Double) -> Double { 1 / (1 + exp(-max(-30, min(30, z)))) }

    func norm(_ x: [Double]) -> [Double] { x.indices.map { (x[$0] - mean[$0]) / scale[$0] } }

    public func p(_ x: [Double]) -> Double {
        let z = norm(x)
        return Self.sigmoid(zip(w, z).map(*).reduce(0, +) + w[x.count])
    }

    /// Fits on rows `x` with labels `y` (0 or 1). `lambda` pulls the weights toward `start` (zero by default).
    public static func fit(_ x: [[Double]], _ y: [Double], lambda: Double = 0.01, steps: Int = 600, rate: Double = 0.5,
                           start: [Double]? = nil, weight positive: Double = 1) -> Logistic {
        let d = x.first?.count ?? 0
        var mean = Array(repeating: 0.0, count: d), scale = Array(repeating: 1.0, count: d)
        if !x.isEmpty {
            for j in 0..<d {
                let col = x.map { $0[j] }
                let m = col.reduce(0, +) / Double(col.count)
                let v = col.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(col.count)
                mean[j] = m
                scale[j] = v > 1e-9 ? sqrt(v) : 1
            }
        }
        var model = Logistic(w: start ?? Array(repeating: 0, count: d + 1), mean: mean, scale: scale)
        let base = start ?? Array(repeating: 0, count: d + 1)
        let z = x.map(model.norm)
        let n = Double(max(1, x.count))
        for _ in 0..<steps {
            var g = Array(repeating: 0.0, count: d + 1)
            for (i, row) in z.enumerated() {
                let pr = sigmoid(zip(model.w, row).map(*).reduce(0, +) + model.w[d])
                let c = y[i] > 0.5 ? positive : 1
                let e = (pr - y[i]) * c
                for j in 0..<d { g[j] += e * row[j] }
                g[d] += e
            }
            for j in 0...d {
                let pen = j < d ? lambda * (model.w[j] - base[j]) : 0
                model.w[j] -= rate * (g[j] / n + pen)
            }
        }
        return model
    }
}
