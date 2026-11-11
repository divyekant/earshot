import EarshotCore
import Foundation

/// A chain of commands in one sentence (I-28): "click on this, click on that, type this and press send".
/// The cut is text only. It adds no verb and no intent (DESIGN 3.0): each step is one ordinary command,
/// and the app routes each step on a new screen read, after the step before it ran.
extension CommandRouter {
    /// The most steps in one chain (dk, 2026-11-03).
    public static let maxSteps = 10

    /// Words that start a new step after a joiner. The first word of the rest must be one of them.
    /// Fewer words than `commandStarts`: a word such as "text" or "back" in the middle of a sentence is most often
    /// not a new command.
    static let stepStarts: Set<String> = ["click", "press", "tap", "select", "choose", "hit", "focus", "open", "go",
                                          "switch", "launch", "scroll", "type", "enter", "write", "search", "message",
                                          "dm", "ping", "reply", "show", "hide"]
    /// Verbs whose words after them are text. In a text step, only a strong joiner can end the text.
    static let textVerbs: Set<String> = ["type", "enter", "write", "search", "find", "look", "message", "text", "dm",
                                         "ping", "reply", "tell"]
    /// The verbs of a press. "click notes and type hi" stays one step: the router types into the box "notes" (#62).
    static let pressStepVerbs: Set<String> = pressOnly
    /// Send phrases at the end of a chain. "press send" and "click send" ask for a send, the same as "send".
    static let endSends: Set<String> = ["send", "send it", "send it now", "send now", "send this", "send that",
                                        "press send", "hit send", "click send", "tap send", "press the send button",
                                        "click the send button"]
    /// Words that may come between a joiner and the verb: "and then also click".
    static let stepLeads: Set<String> = ["then", "also", "now", "please", "next", "and"]

    /// The steps of the words, in order. One step (the words as they are) if the words hold no chain.
    ///
    /// Rules:
    /// - A cut is at a comma, a sentence end, "and", "then", "and then" or "after that".
    /// - A cut needs a step verb (`stepStarts`) as the first word after the joiner.
    /// - After a text verb ("type", "message"), the text goes on to the end. Only "then", "and then", "after that"
    ///   or a sentence end before a step verb ends it. A send phrase at the very end also ends it.
    /// - A send phrase at the end, after text, stays on the text step as "and send". The router then sets
    ///   `sendAfter`, and the send rules of one command hold (D-12).
    /// - "open Notes and Calendar": two app names after one "open" give two steps.
    public static func steps(_ spoken: String, context: RouteContext) -> [String] {
        // The words after a plugin lead are text for the plugin, never a chain (R-PL-2).
        if PluginRouter.match(spoken, plugins: context.plugins, apps: context.apps) != nil { return [spoken] }
        let text = fromCommandSentence(spoken, apps: context.apps)
        let tokens = Tokens(text)
        let w = tokens.words
        guard w.count >= 3 else { return [spoken] }

        // Word positions after a comma or a sentence end. Position k: after word k - 1.
        var hardStop = Set<Int>(), softStop = Set<Int>()
        for k in tokens.stops {
            let piece = tokens.pieces[tokens.piece[k - 1]]
            if let last = piece.last, ".!?".contains(last) { hardStop.insert(k) } else { softStop.insert(k) }
        }

        var steps: [String] = []
        var start = 0
        var inText = isTextStep(Array(w[0...]))
        var i = 1
        while i < w.count {
            // The joiner at i, and the first word of the next step.
            var next = i
            var strong = hardStop.contains(i)
            var joiner = hardStop.contains(i) || softStop.contains(i)
            if w[i] == "and" || w[i] == "then" {
                joiner = true
                if w[i] == "then" || (i + 1 < w.count && w[i + 1] == "then") { strong = true }
                next = i + 1
            } else if w[i] == "after", i + 1 < w.count, w[i + 1] == "that" {
                joiner = true; strong = true; next = i + 2
            }
            guard joiner else { i += 1; continue }
            while next < w.count - 1, stepLeads.contains(w[next]) {
                if w[next] == "then" { strong = true }
                next += 1
            }
            guard next < w.count else { break }
            let rest = Array(w[next...])
            let restPhrase = rest.joined(separator: " ")

            // A send phrase at the very end.
            // Words that are not a command ("the blue fox jumps and send": dictation) stay whole.
            if endSends.contains(restPhrase) {
                let head = tokens.raw(start..<i)
                guard isCommandSentence(head, apps: context.apps) else { return steps.isEmpty ? [spoken] : steps + [head + " and send"] }
                if inText {
                    steps.append(head + " and send")
                } else {
                    steps.append(head)
                    steps.append("send")
                }
                // One step: the words with the send phrase as "and send", so "type hi, click send" never types "click send".
                return steps
            }

            let verb = rest[0]
            // The words before the cut must be a command too: "go ahead and open Slack" is one step.
            var cut = stepStarts.contains(verb) && isCommandSentence(tokens.raw(start..<i), apps: context.apps)
                && !["go ahead", "i want", "i need"].contains(Array(w[start..<i]).joined(separator: " "))
            if cut, inText, !strong { cut = false }
            // "click notes and type hi", "focus on notes then type hi": one step (the router types into the box).
            // Not after a comma or a sentence end.
            if cut, !softStop.contains(i), !hardStop.contains(i), w[i] == "and" || w[i] == "then",
               ["type", "enter", "write"].contains(verb), pressStepVerbs.contains(firstVerb(Array(w[start..<i]))) {
                cut = false
                inText = true
            }
            if cut {
                steps.append(tokens.raw(start..<i))
                start = next
                inText = isTextStep(rest)
                i = next + 1
                continue
            }

            // "open Notes and Calendar": the rest is one app name, after a step that opens one app name.
            if !inText, w[i] == "and", let app = exactApp(rest.joined(), context.apps),
               let opened = openedApp(Array(w[start..<i]), apps: context.apps), opened.id != app.id {
                steps.append(tokens.raw(start..<i))
                steps.append("\(opened.verb) " + tokens.raw(next..<w.count))
                return steps
            }
            i += 1
        }
        steps.append(tokens.raw(start..<w.count))
        let out = steps.filter { !TextKit.words($0).isEmpty }
        return out.count > 1 ? out : [spoken]
    }

    /// The first word of a step that is not a filler.
    static func firstVerb(_ words: [String]) -> String {
        words.first { !leadFillers.contains($0) && !ScreenRouter.fillers.contains($0) } ?? ""
    }

    /// True if the step starts with a text verb, or is a press that types ("click notes and type hi").
    static func isTextStep(_ words: [String]) -> Bool {
        textVerbs.contains(firstVerb(words))
    }

    /// "open Notes" or "launch Notes": the open verb and the app. Nil for other words.
    static func openedApp(_ words: [String], apps: [AppEntry]) -> (id: String, verb: String)? {
        var rest = words
        while let f = rest.first, leadFillers.contains(f), rest.count > 1 { rest.removeFirst() }
        guard let verb = rest.first, ["open", "launch", "start"].contains(verb), rest.count >= 2 else { return nil }
        var name = Array(rest.dropFirst())
        while let f = name.first, ["the", "my"].contains(f), name.count > 1 { name.removeFirst() }
        guard let app = exactApp(name.joined(), apps) else { return nil }
        return (app.id, verb)
    }
}
