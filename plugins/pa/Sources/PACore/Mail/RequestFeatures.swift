import Foundation

/// Step 2 of the request flags (phase 3 build spec, 8.4): prepare the text, cut it into sentences, and give each
/// sentence and each message its features. The PA selects a sentence of the mail. It writes no text.
public enum RequestFeatures {
    /// One candidate sentence, as written in the text.
    public struct Sentence: Equatable, Sendable {
        public var text: String
        /// The features of section 8.4 and of the v2 spec, each 0 or 1.
        public var f: [Double]
    }

    /// The prepared message.
    public struct Prepared: Sendable {
        /// The candidate sentences that passed gate 2 (and, for an organization, the duty rule of gate 3).
        public var sentences: [Sentence]
        /// The name in the greeting ("Hi Maya," gives "maya"), in lower case, "*" for a group, or nil.
        public var greeting: String?
        /// The length of the prepared text in characters.
        public var length: Int
        /// The gate that removes the message (v2 spec, section 4), or nil if it passes gates 2 and 3.
        public var gate: String?
        /// Gate 3: an organization writes.
        public var org: Bool = false
    }

    public static let sentenceNames = ["question", "please", "command", "duty", "time", "owner name", "past", "no action",
                                       "third person", "help offer", "question mark", "you", "no request word",
                                       "done or taken back", "offer or small talk"]

    static let questionStarts = ["can you", "could you", "would you", "will you", "are you able", "do you have",
                                 "when can you", "are you", "do you", "did you", "have you", "which", "what time",
                                 "when will you", "would it be"]
    static let commands: Set<String> = ["send", "call", "confirm", "sign", "pay", "bring", "check", "review", "reply",
                                        "book", "fill", "return", "update", "share", "pick", "let", "remember", "renew",
                                        "collect", "choose", "forward", "print", "read", "tell", "ring", "text", "email",
                                        "submit", "complete", "order", "arrange", "add", "upload", "provide", "phone", "drop",
                                        "leave", "come", "make", "write", "give", "choose", "look"]
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

    /// Removes quoted old mail, forwarded mail, the signature and small print (8.4, v2 gate 2).
    public static func prepare(_ body: String) -> [String] {
        var out: [String] = []
        for raw in body.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let low = line.lowercased()
            if line.hasPrefix(">") { continue }
            if low.hasSuffix("wrote:") { break }
            if low.hasPrefix("-----original message") || low.contains("forwarded message") || low.hasPrefix("begin forwarded") { break }
            if low.hasPrefix("from:"), out.contains(where: { $0.lowercased().hasPrefix("sent:") || $0.isEmpty }) { break }
            if line == "--" || raw.hasPrefix("-- ") || low.hasPrefix("sent from my") { break }
            if low.contains("this email and any attachments") || low.contains("confidential and intended") { continue }
            out.append(line)
        }
        return out
    }

    static func has(_ s: String, _ list: [String]) -> Bool { list.contains { s.contains($0) } }

    static func letters(_ w: Substring) -> String { String(w.filter { $0.isLetter || $0 == "'" || $0 == "-" }) }

    /// The names of a greeting line in lower case: "Hi Paul, hi Rosa," gives paul and rosa, "Dear Mr. Brandt," gives
    /// brandt, "Maya love," gives maya, "Dear Parent," gives "*". Nil if the line is not a greeting.
    static func greetingNames(_ line: String) -> [String]? {
        guard line.hasSuffix(",") || line.hasSuffix("!") || line.hasSuffix(":") else { return nil }
        let w = line.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "!" || $0 == ":" }).map(letters).filter { !$0.isEmpty }
        guard !w.isEmpty, w.count <= 6 else { return nil }
        let startsWithGreet = RequestWords.greet.contains(w[0].lowercased())
        // "Maya," or "Maya love," as a greeting: one capital word first, at most 2 words.
        if !startsWithGreet {
            guard w.count <= 2, let c = w[0].first, c.isUppercase, !RequestWords.notNames.contains(w[0].lowercased()) else { return nil }
            return [w[0].lowercased()]
        }
        var names: [String] = []
        var groupHit = false
        for x in w.dropFirst() {
            let l = x.lowercased()
            if RequestWords.greet.contains(l) || RequestWords.titles.contains(l.replacingOccurrences(of: ".", with: "")) { continue }
            if RequestWords.group.contains(l) { groupHit = true; continue }
            if l == "and" || l == "&" { continue }
            if let c = x.first, c.isUppercase { names.append(l) }
        }
        if names.isEmpty { return groupHit || w.count == 1 ? ["*"] : ["*"] }
        return names
    }

    /// "Hi Maya," or "Dear Maya Rao," gives the first name in lower case; a group gives "*".
    static func greetingName(_ line: String) -> String? { greetingNames(line)?.first }

    /// The name at the start of a sentence, before a comma, a dash or a colon ("Lena, can you ...", "Will - can you",
    /// "And Arun, you bring"), in lower case, or nil.
    static func headName(_ s: String) -> String? {
        var t = Substring(s)
        for w in ["And ", "So ", "Also ", "Oh ", "But ", "Ok ", "OK "] where t.hasPrefix(w) { t = t.dropFirst(w.count) }
        guard let cut = t.firstIndex(where: { $0 == "," || $0 == ":" || $0 == "-" || $0 == "–" }),
              t.distance(from: t.startIndex, to: cut) < 15 else { return nil }
        if t[cut] == "-" || t[cut] == "–" {
            guard cut > t.startIndex, t[t.index(before: cut)] == " " else { return nil }
        }
        let head = t[..<cut].trimmingCharacters(in: .whitespaces)
        guard head.split(separator: " ").count == 1, let c = head.first, c.isUppercase else { return nil }
        let l = letters(Substring(head)).lowercased()
        return l.isEmpty || RequestWords.notNames.contains(l) ? nil : l
    }

    /// Cuts a line into sentences. A question mark before a small letter also ends a sentence ("on saturday? they").
    static func sentences(_ line: String) -> [String] {
        TextCut.sentences(line).flatMap { s -> [String] in
            var out: [String] = []
            var cur = ""
            let chars = Array(s)
            for (i, ch) in chars.enumerated() {
                cur.append(ch)
                if ch == "?", i + 2 < chars.count, chars[i + 1] == " ", chars[i + 2].isLowercase {
                    out.append(cur.trimmingCharacters(in: .whitespaces))
                    cur = ""
                }
            }
            let rest = cur.trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { out.append(rest) }
            return out
        }
    }

    /// A label line such as "Return: 9 March 2027" is not a sentence.
    static func isLabel(_ s: String) -> Bool {
        guard let colon = s.firstIndex(of: ":") else { return false }
        let head = s[..<colon]
        let rest = s[s.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        let short = rest.first?.isNumber == true || rest.split(separator: " ").count <= 4
        return short && head.split(separator: " ").count <= 3 && !head.contains(",") && s.distance(from: s.startIndex, to: colon) < 25
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
        if let n = headName(s), !owner.contains(n) { third = true }
        let helpHit = has(low, help) || has(low, ads)
        let offerIf = has(low, RequestWords.offerIf) || has(low, RequestWords.smallTalk)
        let implicit = has(low, RequestWords.implicit) || (command && time && !offerIf)
        let withdrawn = has(low, RequestWords.withdrawn)
        return [question, please, command, dutyHit, time, ownerName, pastHit, noAct, third, helpHit, s.hasSuffix("?"),
                words.contains("you") || words.contains("your"), implicit, withdrawn, offerIf].map { $0 ? 1 : 0 }
    }

    /// Gate 3: true if an organization writes (a role address, or a display name that is not a person's name).
    public static func isOrganization(_ m: MailMessage) -> Bool {
        let addr = m.fromAddress.lowercased()
        let local = String(addr.split(separator: "@").first ?? "")
        let parts = local.split(whereSeparator: { ".-_+".contains($0) || $0.isNumber }).map(String.init)
        if local.contains("noreply") || local.contains("no-reply") || local.contains("donotreply") { return true }
        if parts.contains(where: RequestWords.roleAddress.contains) { return true }
        let name = m.fromName.trimmingCharacters(in: .whitespaces)
        let w = name.split(separator: " ").map(String.init)
        let personParts = parts.count >= 2 && parts.allSatisfy { $0.allSatisfy(\.isLetter) }
        if w.contains(where: { RequestWords.orgNames.contains($0.lowercased()) }) { return true }
        // A first.last address ("j.marsh@") with no organization word in the name: a person.
        if personParts { return false }
        if w.isEmpty { return true }
        let caps = w.allSatisfy { x in x.first?.isUppercase == true && x.dropFirst().allSatisfy { $0.isLetter || $0 == "'" || $0 == "-" || $0 == "." } }
        if w.count >= 2, w.count <= 3, caps { return false }
        // One word ("Joe" from joe@): a person only if the address is that name.
        if w.count == 1, caps { return !(parts.count == 1 && parts[0] == w[0].lowercased()) }
        return true
    }

    /// The prepared message with its candidate sentences, after gates 2 and 3 (v2 spec, section 4). The greeting and
    /// the sign-off are not candidates. `ownerAddresses` has the owner's addresses in lower case.
    /// A note (`note` true) is the owner's own text: it has no sender gate and no To rule.
    public static func prepared(_ m: MailMessage, owner: Set<String>, ownerAddresses: Set<String> = [], note: Bool = false,
                                time: (String) -> Bool = { _ in false }) -> Prepared {
        let lines = prepare(m.text)
        var greeting: String?
        var greetNames: [String]?
        var sents: [Sentence] = []
        var length = 0
        var gate: String?
        if !note, ownerAddresses.contains(m.fromAddress.lowercased()) { gate = "from owner" } else if m.replied { gate = "replied" }
        let to = m.to.map { $0.lowercased() }
        let ownerInTo = note || ownerAddresses.isEmpty || to.contains(where: ownerAddresses.contains)
        let fewTo = ownerInTo && to.count <= 3
        var paragraphName: String?
        var seen = 0
        var named: [(text: String, forOwner: Bool)] = []
        for line in lines {
            if line.isEmpty { paragraphName = nil; continue }
            length += line.count
            seen += 1
            if seen <= 3, greetNames == nil, let g = greetingNames(line) {
                greetNames = g
                greeting = g.first
                continue
            }
            // A name alone on a line starts a paragraph for that person ("Daniel,").
            if line.hasSuffix(","), line.split(separator: " ").count == 1, let n = headName(line + " x") ?? headName(line) {
                paragraphName = n
                continue
            }
            let wc = line.split(separator: " ").count
            if wc <= 3, line.hasSuffix(",") || !line.contains(" ") || line.first?.isUppercase == true && !".!?".contains(line.last ?? " ") {
                continue
            }
            var lineName: String?
            for (k, s) in sentences(line).enumerated() where s.split(separator: " ").count >= 3 && !isLabel(s) {
                // A name that starts the first sentence of a paragraph names the person of that paragraph.
                if let n = headName(s) {
                    lineName = n
                    if k == 0, paragraphName == nil { paragraphName = n }
                }
                let addressee = headName(s) ?? lineName ?? paragraphName
                let forOwner: Bool
                if let a = addressee {
                    forOwner = owner.contains(a)
                } else if let g = greetNames, g != ["*"] {
                    forOwner = g.contains(where: owner.contains)
                } else {
                    forOwner = fewTo
                }
                named.append((s, forOwner))
            }
        }
        let org = note ? false : isOrganization(m)
        var kept = named.filter(\.forOwner).map(\.text)
        if kept.isEmpty, gate == nil {
            gate = greetNames.map { $0 != ["*"] && !$0.contains(where: owner.contains) } == true ? "greets another" : "not for owner"
        }
        if org, gate == nil {
            let all = (m.subject + "\n" + lines.joined(separator: "\n"))
            let low = all.lowercased()
            let thing = has(low, RequestWords.ownerThing) || RequestWords.hasReference(all)
            let salesSigns = RequestWords.countWords(low, RequestWords.sales) + (RequestWords.hasFromPrice(all) ? 1 : 0)
            if salesSigns >= 2, !thing {
                gate = "sales"
            } else {
                let limitAll = lines.contains { time($0) } || has(" " + low + " ", RequestWords.limit)
                kept = kept.filter { has(" " + $0.lowercased() + " ", RequestWords.acts) }
                if !thing || !limitAll || kept.isEmpty { gate = "no duty" }
            }
        }
        for s in kept { sents.append(Sentence(text: s, f: sentenceFeatures(s, owner: owner, timeFound: time(s)))) }
        return Prepared(sentences: sents, greeting: greeting, length: length, gate: gate, org: org)
    }

    // MARK: - Variant A: points by hand

    /// Points by hand for one sentence (variant A).
    public static let handWeights: [Double] = [3, 1, 2, 3, 1, 1, -3, -4, -4, -3, 1, 1, 3, -4, -3]

    public static func handScore(_ f: [Double]) -> Double { zip(handWeights, f).map(*).reduce(0, +) }

    /// The message features (8.4) for variant B: the features of the best sentence, then the message facts.
    public static func messageFeatures(_ m: MailMessage, _ p: Prepared, best: Int?, sentenceScores: [Double],
                                       owner: Set<String>, ownerAddresses: Set<String>, middle: Double,
                                       known: Bool = true) -> [Double] {
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
        v.append(p.org ? 1 : 0)
        v.append(p.org && !known ? 1 : 0)
        v.append(1)
        return v
    }

    public static let messageNames = sentenceNames.map { "best " + $0 } + ["best score", "count above middle", "owner in To",
        "addresses / 10", "noreply", "Re:", "length / 1000", "greets owner", "greets another", "greets a group", "organization",
        "first mail of an organization", "bias"]
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
