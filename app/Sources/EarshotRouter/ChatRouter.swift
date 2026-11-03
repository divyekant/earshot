import EarshotCore

/// One option of the short list. Tier 2 sees the label. The label holds no message text (R-MD-1, D-9).
struct RouteOption {
    let intent: Intent
    let label: String
    let score: Double
}

/// The answer of a rules step: the intent, if the rules are sure, and the short list for tier 2.
struct RulesDecision {
    var intent: Intent
    var sure: Bool
    /// True if the words match the name or label exactly (tier "rules"). False for a fuzzy match (tier "fuzzy").
    var exact: Bool
    var why: String
    /// Best first. "None" is not in the list: tier 2 returns nil for "none of these".
    var options: [RouteOption]
    /// The name words that no known name explains, as the owner said them. The app can search for them (E1, section 6).
    var heardName: String?
    var heardApp: String?
    /// True only for a bare "type" (RouteResult.awaitsText).
    var awaitsText = false
    /// True only if a trailing send phrase was removed from the text of the intent (RouteResult.sendAfter).
    var sendAfter = false
}

/// Opens a chat or an app. Ported from probe E1Router (E1, section 6). It knows no app and no person in advance.
/// It uses only the catalogue rows and the name entries of the context (R-MT-1, R-MT-2).
enum ChatRouter {
    static let leadFillers: Set<String> = Set(["hey", "ok", "okay", "earshot", "please", "can", "could", "you", "would"])
        .union(TextKit.hesitations)
    static let commandVerbs: Set<String> = ["message", "text", "ping", "dm", "tell", "write", "chat", "open", "go",
                                            "switch", "launch", "show", "reply", "jump", "start", "send", "bring",
                                            "pull", "talk", "find", "reach"]
    /// Words that end the name part. The message text comes after them.
    static let textLeads: Set<String> = ["saying", "say", "that"]
    static let selfWords: Set<String> = ["me", "myself", "self"]
    /// Words that are never part of a name.
    static let stopWords: Set<String> = commandVerbs.union(leadFillers).union([
        "to", "on", "in", "at", "with", "my", "the", "a", "an", "and", "app", "chat", "conversation", "channel",
        "i", "am", "is", "for", "of", "up", "back", "new", "own", "about", "over", "there", "here", "into",
    ])
    /// Short words that speech to text splits from the start of a name: "a ditty" for "Udita".
    static let joinable: Set<String> = ["a", "an"]

    static let shortListSize = 8
    static let strongMatch = 0.8
    static let weakMatch = 0.6
    /// Sound scores. An exact sound code is a strong match. A close sound code is just above the strong mark.
    static let soundExact = 0.9
    static let soundClose = 0.82
    /// Another name with a sound code this close makes a sound match unsure ("Manal": Manel or Mrunal?).
    static let soundRival = 0.75

    private struct Gram {
        let text: String
        let first: Int
        let last: Int
    }

    private struct Scored {
        let entry: NameEntry
        let score: Double
        let text: Double
        let sound: Double
        let gram: Gram?
    }

    static func decide(_ spoken: String, apps allApps: [AppEntry], names allNames: [NameEntry],
                       frontBundleID: String? = nil) -> RulesDecision {
        let apps = allApps.filter { $0.approved && $0.enabled }
        let chatApps = Set(apps.filter(\.isChat).map(\.id))
        let frontApp = apps.first { $0.bundleID == frontBundleID && $0.isChat }?.id
        let names = allNames.filter { chatApps.contains($0.appID) }
        func appName(_ id: String) -> String { apps.first(where: { $0.id == id })?.name ?? id }

        var tokens = Tokens(spoken)
        var lead = 0
        while lead < tokens.count, leadFillers.contains(tokens.words[lead]) { lead += 1 }
        tokens.dropFirst(lead)
        let words = tokens.words
        let commas = tokens.stops.filter { $0 < words.count }
        guard !words.isEmpty else {
            return RulesDecision(intent: .none, sure: true, exact: true, why: "no words", options: [])
        }

        // App names, anywhere in the words. Almost exact (0.9): "message" must not match the app "Messages".
        var mentioned: [String: Double] = [:]
        var appTokens = Set<Int>()
        var appAtStart = false
        var onApp = false
        let aliasesByApp = apps.map { app in
            (app, Set((app.aliases + [app.name]).map(TextKit.normalize)).filter { !$0.isEmpty })
        }
        // Words that alone are an app name. A join never takes such a word: "notes app" stays the app Notes.
        let oneWordApps = Set(aliasesByApp.flatMap { $0.1 }.filter { !$0.contains(" ") })
        for (app, aliases) in aliasesByApp {
            for alias in aliases {
                let parts = alias.split(separator: " ").map(String.init)
                // Speech to text can split a one-word name into 2 or 3 words: "TigerVNC" gives "Tiger VNC" (E2),
                // "iMessage" gives "I message", "ChatGPT" gives "chat GPT". A join must give the exact name.
                let spans = parts.count == 1 && parts[0].count >= 4 ? [1, 2, 3] : [parts.count]
                for span in spans where span <= words.count {
                    for start in 0...(words.count - span) {
                        let piece = words[start..<(start + span)]
                        let phrase = piece.joined()
                        let joined = parts.count == 1 && span > 1
                        if joined, piece.contains(where: { oneWordApps.contains($0) }) { continue }
                        let score = TextKit.similarity(phrase, parts.joined())
                        guard joined ? score >= 1 : score >= 0.9 else { continue }
                        mentioned[app.id] = max(mentioned[app.id] ?? 0, score)
                        for i in start..<(start + span) { appTokens.insert(i) }
                        if start == 0 { appAtStart = true }
                        if start > 0, ["on", "in"].contains(words[start - 1]) { onApp = true }
                    }
                }
            }
        }

        // The name part ends at a comma or at a text lead word ("tell Ravi that ...").
        // A comma right after the app name does not end it: "Slack, Ravi" names Ravi.
        func hasNameWord(_ range: Range<Int>) -> Bool {
            range.contains { i in !appTokens.contains(i) && !stopWords.contains(words[i]) }
        }
        var nameEnd = commas.first(where: { hasNameWord(0..<$0) }) ?? words.count
        if let lead = words.indices.dropFirst().first(where: { textLeads.contains(words[$0]) }) {
            nameEnd = min(nameEnd, lead)
        }

        let nameEndMarked = nameEnd < words.count
        // A self word right after the command word or the app name ends the name part, as in E0.
        // Speech to text often drops the comma: "Slack me running late" is the own chat, with the text "running late".
        // "get me Felix's chat" does not count: "get" is not a command word.
        if let i = words.indices.first(where: { $0 < nameEnd && (selfWords.contains(words[$0])
                                                                  || (words[$0] == "own" && $0 > 0 && words[$0 - 1] == "my")) }),
           (0..<i).allSatisfy({ appTokens.contains($0) || stopWords.contains(words[$0]) }),
           (0..<i).contains(where: { appTokens.contains($0) || commandVerbs.contains(words[$0]) }) {
            var end = i + 1
            if words[i] == "own", end < nameEnd, ["chat", "conversation", "channel"].contains(words[end]) { end += 1 }
            nameEnd = end
        }

        // A command word in the first three words: "let's write to Ravi", "can you pull up Ravi".
        let isCommand = words.prefix(3).contains { commandVerbs.contains($0) } || appAtStart || onApp
        let head = words.prefix(nameEnd)
        let wantsSelf = head.contains { selfWords.contains($0) } || (head.contains("my") && head.contains("own"))

        // Name words: the name part without stop words, app names and self words.
        let nameIdx = words.indices.filter { i in
            i < nameEnd && !appTokens.contains(i) && !stopWords.contains(words[i]) && !selfWords.contains(words[i])
        }
        var grams: [Gram] = []
        for n in 1...3 where nameIdx.count >= n {
            for s in 0...(nameIdx.count - n) {
                let idx = nameIdx[s..<(s + n)]
                grams.append(Gram(text: idx.map { words[$0] }.joined(), first: idx.first!, last: idx.last!))
            }
        }
        // Join a short word that comes right before a name word: "a ditty" gives "aditty".
        for (k, i) in nameIdx.enumerated() where i > 0 && joinable.contains(words[i - 1]) && !appTokens.contains(i - 1) {
            grams.append(Gram(text: words[i - 1] + words[i], first: i - 1, last: i))
            if k + 1 < nameIdx.count, nameIdx[k + 1] == i + 1 {
                grams.append(Gram(text: words[i - 1] + words[i] + words[i + 1], first: i - 1, last: i + 1))
            }
        }

        // Chat apps whose one-word name is the chat verb, or the verb with "s" or "es" ("message" and "Messages").
        var verbApps = Set<String>()
        if let verb = words.prefix(3).first(where: { commandVerbs.contains($0) }) {
            for (app, aliases) in aliasesByApp where app.isChat
                && aliases.contains(where: { $0 == verb || $0 == verb + "s" || $0 == verb + "es" }) {
                verbApps.insert(app.id)
            }
        }

        // Only a chat app name changes the name scores. An app such as "Lock Screen" can match a common word.
        let chatMentioned = Set(mentioned.keys.filter { chatApps.contains($0) })

        var scored: [Scored] = []
        for entry in names {
            var best = 0.0, bestText = 0.0, bestSound = 0.0
            var bestGram: Gram?
            for full in ([entry.name] + entry.aliases).map(TextKit.key) where !full.isEmpty {
                let parts = TextKit.words(entry.name)
                // The first name counts alone only for a name of words with spaces ("Prakash Iyer"). A channel name
                // such as "all-team" is one name: the common word "all" must not match it (live test, 2026-11-03).
                let spaced = entry.name.split(whereSeparator: \.isWhitespace).count >= 2
                let firstName = spaced && parts.count >= 2 && full == TextKit.key(entry.name) ? parts[0] : ""
                for g in grams where g.text.count >= 3 || g.text == full {
                    var t = TextKit.similarity(g.text, full)
                    if !firstName.isEmpty { t = max(t, 0.95 * TextKit.similarity(g.text, firstName)) }
                    var snd = SoundCode.similarity(g.text, full)
                    if !firstName.isEmpty, firstName.count >= 3 { snd = max(snd, SoundCode.similarity(g.text, firstName)) }
                    let sndScore = snd >= 1 ? soundExact : (snd >= 0.8 ? soundClose : 0)
                    let s = max(t, sndScore)
                    if s > best { best = s; bestGram = g }
                    bestText = max(bestText, t)
                    bestSound = max(bestSound, snd)
                }
            }
            if entry.isSelf && wantsSelf { best = 1.0; bestText = 1.0 }
            if !chatMentioned.isEmpty {
                best += chatMentioned.contains(entry.appID) ? 0.1 : -0.15
            } else {
                // No app named: the front chat app wins a tie ("message myself" while Messages is in front).
                if let front = frontApp, entry.appID == front { best += 0.1 }
                // The chat verb is the singular of a chat app's name: "message me" leans to "Messages". Weak evidence:
                // enough to break a tie, less than a known name that only one app has.
                if verbApps.contains(entry.appID) { best += 0.06 }
            }
            if best >= 0.45 {
                scored.append(Scored(entry: entry, score: best, text: bestText, sound: bestSound, gram: bestGram))
            }
        }
        scored.sort { $0.score > $1.score }

        // Name words that nothing explains. A word counts as known if it is in a gram that matched a name well.
        var known = Set<Int>()
        for s in scored where s.score >= weakMatch { if let g = s.gram { for i in g.first...g.last { known.insert(i) } } }
        // A known name at the start of the name words, with no comma after it: the words after it are the message text,
        // not an unknown name ("Slack Prakash running late").
        var textFrom = Int.max
        if let first = nameIdx.first, let top = scored.first, top.score >= strongMatch, let g = top.gram, g.first == first {
            textFrom = g.last + 1
        }
        let unknownIdx = nameIdx.filter { !known.contains($0) && $0 < textFrom }
        // With no comma, the end of an unknown name is not known. Give the first word to the app's search:
        // the next route then knows the name, and the words after it become the text.
        let heardIdx = nameEndMarked ? unknownIdx : Array(unknownIdx.prefix(1))
        let heardName: String? = heardIdx.isEmpty ? nil : tokens.raw(heardIdx.first!..<(heardIdx.last! + 1))
        let heardApp = mentioned.filter { chatApps.contains($0.key) }.max(by: { $0.value < $1.value })?.key

        // The message text: after the name part, or after the name words that matched the name.
        func messageText(_ s: Scored) -> String? {
            var start = nameEnd
            if let g = s.gram, let lastName = nameIdx.last, lastName > g.last, nameIdx.allSatisfy({ $0 >= g.first }) {
                start = g.last + 1
            }
            var end = words.count
            // Remove "on Slack" at the end.
            while end > start, appTokens.contains(end - 1) { end -= 1 }
            if end < words.count, end > start, ["on", "in"].contains(words[end - 1]) { end -= 1 }
            while start < end, appTokens.contains(start)
                || (["on", "in"].contains(words[start]) && start + 1 < end && appTokens.contains(start + 1)) {
                start += 1
            }
            if start < end, textLeads.contains(words[start]) { start += 1 }
            let text = tokens.raw(start..<end)
            return text.isEmpty ? nil : text
        }

        var options: [RouteOption] = []
        var chatScored: [(RouteOption, Scored)] = []
        for s in scored.prefix(shortListSize) {
            let name = appName(s.entry.appID)
            let label = s.entry.isSelf ? "\(name): open the owner's own chat (\(s.entry.name))"
                : "\(name): open the chat \"\(s.entry.name)\""
            let o = RouteOption(intent: .openChat(appID: s.entry.appID, target: s.entry.name, text: messageText(s)),
                                label: label, score: s.score)
            options.append(o)
            chatScored.append((o, s))
        }
        let appOptions = mentioned.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).map { id, score in
            RouteOption(intent: .openApp(appID: id), label: "Open the app \(appName(id))", score: score)
        }
        options += appOptions

        func result(_ intent: Intent, _ sure: Bool, _ exact: Bool, _ why: String) -> RulesDecision {
            RulesDecision(intent: intent, sure: sure, exact: exact, why: why, options: options,
                          heardName: heardName, heardApp: heardApp)
        }

        guard isCommand else {
            // A known name with no command word: the rules cannot tell ("get me Ravi's chat").
            if let c = chatScored.first, c.0.score >= strongMatch {
                return result(.none, false, false, "a known name, but no command word")
            }
            return result(.none, true, true, "no command word or app name")
        }
        let c1 = chatScored.first
        let c2 = chatScored.dropFirst().first
        if let c1, c1.0.score >= strongMatch {
            let o1 = c1.0, s1 = c1.1
            let exact = s1.text >= 1
            if let o2 = c2?.0, o2.score >= o1.score - 0.05 {
                return result(o1.intent, false, exact, "two chats match")
            }
            if s1.text < strongMatch {
                // A match by sound only. Another name that sounds alike makes it unsure.
                let key = TextKit.key(s1.entry.name)
                let rival = scored.dropFirst().contains { $0.sound >= soundRival && TextKit.key($0.entry.name) != key }
                if rival { return result(o1.intent, false, false, "name match by sound, another name sounds alike") }
                return result(o1.intent, true, false, "name match by sound")
            }
            return result(o1.intent, true, exact, exact ? "name match" : "close name match")
        }
        if let a = appOptions.first, (c1?.0.score ?? 0) < weakMatch {
            let sure = unknownIdx.isEmpty
            return result(a.intent, sure, a.score >= 1, sure ? "app name" : "app name, other words unknown")
        }
        if let o1 = c1?.0, o1.score >= weakMatch {
            return result(o1.intent, false, false, "weak name match")
        }
        return result(.none, false, false, "nothing matches")
    }
}
