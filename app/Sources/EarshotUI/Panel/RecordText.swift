import EarshotCore
import Foundation

// The words of one command in the panel and the Activity page (dk, 2026-11-15): what earshot did comes first, in
// plain words. What the owner said comes second, in quotes. No router details. Pure, so the tests can check it.

/// One command as two lines and a glyph.
public struct RecordLine: Equatable, Sendable {
    public enum Tone: Equatable, Sendable { case done, failed, asked, quiet }
    public var glyph: GlyphKind
    public var title: String
    public var detail: String
    public var tone: Tone
}

/// The old panel text functions. The panel and the tests still use them.
public enum PanelText {
    /// True if the panel shows the record: a turn with words, or a command with an intent. Rejected wakes, dropped
    /// turns and turns with no words stay in the Activity page only.
    public static func shows(_ r: ActivityRecord) -> Bool {
        guard !r.stages.isEmpty else { return false }
        return !r.heard.isEmpty || (r.intent != "none" && !r.intent.isEmpty)
    }

    /// The words that earshot heard, in quotes. A dictation keeps no words in the log, so it uses the intent.
    public static func title(_ r: ActivityRecord) -> String {
        if r.heard.isEmpty { return r.intent }
        if let n = wordCountOnly(r.heard) { return "Dictation · \(n) word\(n == 1 ? "" : "s")" }
        return "“\(r.heard)”"
    }

    /// The count of a heard text that is only "(N words)" or "(1 word)", else nil.
    static func wordCountOnly(_ heard: String) -> Int? {
        let t = heard.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("("), t.hasSuffix(")") else { return nil }
        let parts = t.dropFirst().dropLast().split(separator: " ")
        guard parts.count == 2, let n = Int(parts[0]), parts[1] == "words" || parts[1] == "word" else { return nil }
        return n
    }

    /// What earshot did, without the router details: the part of the note before "· route:".
    public static func did(_ r: ActivityRecord) -> String {
        var text = r.note
        if let cut = text.range(of: " · route:") { text = String(text[..<cut.lowerBound]) }
        text = RecordText.dropArrows(text).trimmingCharacters(in: .whitespaces)
        if text.isEmpty { text = r.intent }
        guard let first = text.first else { return r.ok ? "Done" : "Not done" }
        return first.uppercased() + text.dropFirst()
    }

    /// The last `count` records that the panel shows, newest first.
    public static func recent(_ records: [ActivityRecord], count: Int = 4) -> [ActivityRecord] {
        Array(records.filter(shows).sorted { $0.at > $1.at }.prefix(count))
    }
}

public enum RecordText {
    /// "→ → Slack" and "→ Slack" become "Slack".
    static func dropArrows(_ s: String) -> String {
        var t = Substring(s)
        while t.hasPrefix("→") { t = t.dropFirst().drop { $0 == " " } }
        return String(t)
    }

    /// The words in quotes, lower case and with no end mark, as the owner said them: "Open Slack." gives “open slack”.
    /// Nil for a dictation, which keeps only its word count.
    public static func said(_ heard: String) -> String? {
        var t = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, PanelText.wordCountOnly(t) == nil else { return nil }
        while let last = t.last, ".!?,".contains(last) { t.removeLast() }
        guard !t.isEmpty else { return nil }
        return "“\(t.lowercased())”"
    }

    /// The front app of the command, from "screen: <bundle id> …" in the note, by its name in the app list.
    public static func app(_ note: String, apps: [AppEntry]) -> String? {
        guard let r = note.range(of: "screen: ") else { return nil }
        let id = note[r.upperBound...].prefix { !$0.isWhitespace && $0 != "," }
        guard !id.isEmpty else { return nil }
        if let a = apps.first(where: { $0.bundleID == id }) { return a.name }
        return nil
    }

    /// The reason of a failed command in plain words: the first part of the note, with no router or screen details.
    public static func reason(_ note: String) -> String {
        var t = note
        for cut in [" · route:", " · screen:", " · speech:", ": ", " (", " · "] {
            if let r = t.range(of: cut) { t = String(t[..<r.lowerBound]) }
        }
        t = dropArrows(t).trimmingCharacters(in: .whitespaces)
        return t
    }

    /// "the search field" becomes "The search field".
    static func capital(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }

    /// The number N in "(N words)" or "N words" in a text, else nil.
    static func wordCount(_ s: String) -> Int? {
        guard let r = s.range(of: #"(\d+) words?"#, options: .regularExpression) else { return nil }
        return Int(s[r].split(separator: " ")[0])
    }

    /// The text between the first pair of quotes: Click "Reply all" gives Reply all.
    static func quoted(_ s: String) -> String? {
        guard let a = s.firstIndex(of: "\""), let b = s[s.index(after: a)...].firstIndex(of: "\"") else { return nil }
        return String(s[s.index(after: a)..<b])
    }

    /// The choices of a "not sure" note: "1: A · 2: B" gives [A, B], and "say "yes" for: A" gives [A].
    public static func choices(_ note: String) -> [String] {
        let parts = note.components(separatedBy: " · ")
        var out: [String] = []
        for p in parts {
            if let r = p.range(of: #"^\d+: "#, options: .regularExpression) { out.append(dropArrows(String(p[r.upperBound...]))) }
        }
        if out.isEmpty, let r = note.range(of: "say \"yes\" for: ") {
            let rest = note[r.upperBound...]
            let end = rest.range(of: ", or \"no\"")?.lowerBound ?? rest.endIndex
            out.append(dropArrows(String(rest[..<end])))
        }
        return out
    }

    /// The two lines of a command.
    public static func line(_ r: ActivityRecord, apps: [AppEntry] = []) -> RecordLine {
        let intent = dropArrows(r.intent.trimmingCharacters(in: .whitespaces))
        let said = said(r.heard)
        let app = app(r.note, apps: apps)
        let jev = r.tier == .jev ? "Jev picked it" : nil

        func join(_ parts: String?...) -> String { parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
        func done(_ glyph: GlyphKind, _ title: String, _ failTitle: String? = nil, detail: String? = nil) -> RecordLine {
            if r.ok { return RecordLine(glyph: glyph, title: title, detail: detail ?? join(said, app, jev), tone: .done) }
            return RecordLine(glyph: .failed, title: failTitle ?? "Did not do it: \(title)",
                              detail: join(said, reason(r.note), app), tone: .failed)
        }

        // Asked the owner: "not sure: … · 1: A · 2: B".
        if r.note.hasPrefix("not sure") {
            let options = choices(r.note)
            let title = options.isEmpty ? "Not sure what to do" : "Asked you: " + options.joined(separator: " or ") + "?"
            return RecordLine(glyph: .notSure, title: title, detail: join(said, app), tone: .asked)
        }
        // A dictation: "Type "(14 words)"" or "Type 14 words".
        if intent.hasPrefix("Type"), let n = wordCount(intent) ?? PanelText.wordCountOnly(r.heard) {
            let words = "\(n) word\(n == 1 ? "" : "s")"
            return done(.typed, "Typed \(words)", "Did not type \(words)", detail: join(app.map { "in \($0)" }, jev))
        }
        if intent.hasPrefix("Click menu ") {
            let path = String(intent.dropFirst("Click menu ".count))
            return done(.click, "Chose \(path)", "Did not choose \(path)")
        }
        if intent.hasPrefix("Click"), let label = quoted(intent) {
            let picked = intent.hasSuffix("(screen)") ? "Jev picked it" : nil
            if r.ok { return RecordLine(glyph: .click, title: "Clicked “\(label)”", detail: join(said, app, picked ?? jev), tone: .done) }
            return done(.click, "", "Did not find “\(label)”")
        }
        if intent == "Send" { return done(.sent, "Sent", "Did not send") }
        if r.note.hasPrefix("sent to ") || (intent.contains(" · ") && r.note.hasPrefix("sent to")) {
            let name = String(r.note.dropFirst("sent to ".count))
            return done(.plugin, "Handed to \(name)", "Did not reach \(name)")
        }
        if intent.hasPrefix("Open "), intent.hasSuffix(")"), let r2 = intent.range(of: " (plugin ") {
            let name = String(intent[intent.index(intent.startIndex, offsetBy: 5)..<r2.lowerBound])
            return done(.open, "Opened \(name)", "Did not open \(name)")
        }
        if intent.hasPrefix("Open ") {
            let what = String(intent.dropFirst(5))
            return done(.open, "Opened \(what)", "Did not open \(what)")
        }
        if intent.hasPrefix("Scroll ") { return done(.check, "Scrolled " + intent.dropFirst(7), "Did not scroll") }
        if intent == "Back" { return done(.back, "Went back", "Did not go back") }
        if intent.hasPrefix("Press ") { return done(.check, "Pressed " + intent.dropFirst(6), "Did not press " + intent.dropFirst(6)) }
        if intent.hasPrefix("Undo the last typing") { return done(.typed, "Took back the last typing", "Did not take back the typing") }
        if intent == "Show numbers" || intent == "Hide numbers" {
            return done(.check, intent == "Show numbers" ? "Showed the numbers" : "Hid the numbers", "Did not do it")
        }
        if intent.hasPrefix("type: waiting") { return RecordLine(glyph: .text, title: "Waited for the text", detail: join(said, app), tone: .done) }
        if intent.contains(" · then ") {
            let steps = intent.components(separatedBy: " · then ").map(dropArrows)
            return done(.open, "\(steps.count) steps: " + steps.joined(separator: ", then "), "Stopped after some steps")
        }
        if intent == "none" || intent.isEmpty {
            if r.note.hasPrefix("OK, nothing done") { return RecordLine(glyph: .check, title: "Did nothing, as you said", detail: join(said), tone: .done) }
            if r.note.contains("voice did not match") {
                return RecordLine(glyph: .failed, title: "Not your voice", detail: join(said, "earshot did nothing"), tone: .failed)
            }
            if r.note == "not a command" {
                return RecordLine(glyph: .failed, title: "Not a command", detail: join(said, app), tone: .failed)
            }
            if r.heard.isEmpty && r.stages.isEmpty {
                return RecordLine(glyph: .wake, title: capital(reason(r.note)), detail: "", tone: .quiet)
            }
            return RecordLine(glyph: r.ok ? .check : .failed, title: capital(reason(r.note).isEmpty ? (r.ok ? "Done" : "Not done") : reason(r.note)),
                              detail: join(said, app), tone: r.ok ? .done : .failed)
        }
        // An app, or a chat in an app: "Slack · Ravi".
        let parts = intent.components(separatedBy: " · ")
        if parts.count == 2, !intent.contains("\"") {
            return done(.open, "Opened \(parts[0]) · \(parts[1])", "Did not open \(parts[0]) · \(parts[1])")
        }
        if parts.count == 1, !intent.contains(" ") || apps.contains(where: { $0.name == intent }) {
            return done(.open, "Opened \(intent)", "Did not open \(intent)")
        }
        return done(.check, capital(intent), "Did not do it: \(intent)")
    }
}
