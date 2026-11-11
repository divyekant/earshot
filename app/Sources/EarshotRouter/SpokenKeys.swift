import EarshotCore
import Foundation

/// Spoken keys and "undo that" (I-34, D-13). The words are text only (under 1 ms). The key list is fixed: it names
/// no app and no feature (DESIGN 3.0, rule 2). The action module checks where a key may go (KeyRules).
extension CommandRouter {
    /// Words before the key name: "press tab", "hit the escape key".
    static let keyVerbs: Set<String> = ["press", "hit", "tap"]

    /// The key names. `bare` is false for a word that is also a command word or a menu title ("delete", "enter",
    /// "return", "up"): it is a key only after a key verb or with a count ("delete three times").
    static let keyNames: [(words: [String], key: SpokenKey, bare: Bool)] = [
        (["backspace"], .backspace, true), (["back", "space"], .backspace, true), (["delete"], .backspace, false),
        (["forward", "delete"], .forwardDelete, true),
        (["new", "line"], .newLine, true), (["newline"], .newLine, true), (["next", "line"], .newLine, true),
        (["return"], .newLine, false), (["enter"], .newLine, false),
        (["tab"], .tab, false), (["tab", "key"], .tab, true),
        (["escape"], .escape, true), (["esc"], .escape, false),
        (["left", "arrow"], .left, true), (["arrow", "left"], .left, true), (["left"], .left, false),
        (["right", "arrow"], .right, true), (["arrow", "right"], .right, true), (["right"], .right, false),
        (["up", "arrow"], .up, true), (["arrow", "up"], .up, true), (["up"], .up, false),
        (["down", "arrow"], .down, true), (["arrow", "down"], .down, true), (["down"], .down, false),
    ]

    /// Phrases that remove the last text that earshot typed. A bare "undo" stays the app's menu item Edit > Undo.
    static let undoPhrases: Set<String> = ["undo that", "undo it", "undo this", "undo the typing", "undo typing",
                                           "undo the last typing", "undo what you typed", "undo the text",
                                           "scratch that", "delete that", "remove that", "delete what you typed",
                                           "remove what you typed"]

    /// The key and the count of a spoken key command, or nil. The words are normalized, with the lead fillers removed.
    /// "press backspace three times", "new line", "hit the tab key", "left arrow 2 times", "delete twice".
    static func spokenKey(_ words: [String]) -> (key: SpokenKey, times: Int)? {
        var w = words
        let verb = w.first.map { keyVerbs.contains($0) } ?? false
        if verb { w.removeFirst() }
        if w.first == "the" { w.removeFirst() }
        // The longest key name first: "forward delete" before "delete", "tab key" before "tab".
        for name in keyNames.sorted(by: { $0.words.count > $1.words.count }) where w.starts(with: name.words) {
            var rest = Array(w.dropFirst(name.words.count))
            if rest.first == "key" || rest.first == "button" { rest.removeFirst() }
            guard let times = keyCount(rest) else { continue }
            // A bare word that is also a command needs a verb or a count.
            if !name.bare, !verb, rest.isEmpty { continue }
            return (name.key, times)
        }
        return nil
    }

    /// The count after a key name: nothing (1), "once", "twice", "three times", "3 times", "3". Nil for other words.
    static func keyCount(_ rest: [String]) -> Int? {
        switch rest {
        case []: return 1
        case ["once"]: return 1
        case ["twice"]: return 2
        case ["thrice"]: return 3
        default: break
        }
        var digits = TextKit.digitize(rest)
        if let l = digits.last, l == "times" || l == "time" { digits.removeLast() }
        guard digits.count == 1, TextKit.isNumber(digits[0]), let n = Int(digits[0]) else { return nil }
        return n
    }

    /// True for "undo that" and the other undo phrases.
    static func isUndo(_ words: [String]) -> Bool { undoPhrases.contains(words.joined(separator: " ")) }

    /// The rules answer for a spoken key or "undo that", or nil.
    static func keyDecision(_ words: [String]) -> RulesDecision? {
        if isUndo(words) {
            return RulesDecision(intent: .undoTyping(""), sure: true, exact: true, why: "undo words", options: [])
        }
        if let k = spokenKey(words) {
            return RulesDecision(intent: .pressKey(k.key, times: k.times), sure: true, exact: true, why: "key words",
                                 options: [])
        }
        return nil
    }
}
