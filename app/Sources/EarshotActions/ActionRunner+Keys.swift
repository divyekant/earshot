import ApplicationServices
import EarshotCore
import Foundation

// Spoken keys ("backspace three times", "new line") and "undo that" (I-34, D-13).
// The rules are pure functions, so that unit tests can check them without a screen. No rule names an app (R-MT-1).

/// Facts about the focused element, for a spoken key.
struct KeyFocus: Equatable {
    /// An editable text field that is not a password field.
    var editable: Bool
    /// A text area (more than one line). Return in a one-line field can submit a form.
    var multiLine: Bool
    /// A message box: Return there can send (R-NV-5).
    var messageBox: Bool
}

/// What "undo that" does with the focused field.
enum UndoPlan: Equatable {
    /// Press Backspace this many times.
    case backspaces(Int)
    case blocked(String)
}

enum KeyRules {
    /// The most presses of one spoken key command.
    static let maxTimes = 20

    /// The reason not to press the key, or nil.
    /// - Never on a sign-in, code or payment page.
    /// - Backspace and Forward Delete only in a text field: outside a field, they can delete a selected item.
    /// - Return ("new line") only in a text area that is not a message box. In a message box, Return can send, and
    ///   only "send" may press it there (R-NV-5). In a one-line field, Return can submit a form.
    /// - Tab, Escape and the arrows anywhere.
    static func block(_ key: SpokenKey, times: Int, focus: KeyFocus?, sensitive: String?) -> String? {
        if let sensitive { return "blocked: this looks like a sign-in, code or payment page (\(sensitive))" }
        guard (1...maxTimes).contains(times) else { return "say a number from 1 to \(maxTimes)" }
        switch key {
        case .backspace, .forwardDelete:
            guard focus?.editable == true else { return "the focus is not in a text field" }
        case .newLine:
            guard let focus, focus.editable else { return "the focus is not in a text field" }
            if focus.messageBox { return "blocked: Return in a message box can send. Say \"send\" to send" }
            if !focus.multiLine { return "blocked: Return in a one-line field can submit a form" }
        case .tab, .escape, .left, .right, .up, .down:
            break
        }
        return nil
    }

    /// The message-box rule for Return. A label that says message, reply, compose, write or send, or the shape of
    /// a message box (ActionRules.composerShape) that is also short: less than `boxHeight` of the window.
    /// A document body (Notes, TextEdit) is tall, so Return there makes a new line.
    static let boxHeight = 0.35

    static func messageBox(labelSaysComposer: Bool, field: Frame?, window: Frame?) -> Bool {
        if labelSaysComposer { return true }
        guard let f = field, let w = window else { return true }  // unknown shape: the strict rule
        return ActionRules.composerShape(field: f, window: w) && f.h < boxHeight * w.h
    }

    /// The plan for "undo that". earshot removes its own text only: the field must still end with the text that
    /// earshot typed, and the cursor must sit at its end. Else it does nothing. One Backspace for each character.
    /// - `value`: the text of the focused field. Nil if the app does not give it.
    /// - `caret`: the cursor position in UTF-16 units, if the app gives it. -1 if text is selected: Backspace would
    ///   remove the selection, so earshot does nothing.
    static func undoPlan(typed: String, value: String?, caret: Int?) -> UndoPlan {
        let text = ActionText.printable(typed)
        let want = ActionText.squash(text)
        guard !want.isEmpty else { return .blocked("earshot typed nothing to undo") }
        guard let value else { return .blocked("earshot cannot read the text of this field") }
        guard ActionText.squash(value).hasSuffix(want) else { return .blocked("the field changed after earshot typed") }
        // The typed text ends at the last character that is not white space.
        var end = value.endIndex
        while end > value.startIndex, value[value.index(before: end)].isWhitespace { end = value.index(before: end) }
        if let caret, caret != value[..<end].utf16.count { return .blocked("the cursor moved after earshot typed") }
        // Leading white space that earshot typed (" " before go-on text) goes too, if it is still in the field.
        let count = undoCount(text, value: String(value[..<end]))
        return count > 0 ? .backspaces(count) : .blocked("earshot typed nothing to undo")
    }

    /// The number of characters to remove: the typed text with no trailing white space, and its leading white space
    /// only if the field has the same characters before it.
    static func undoCount(_ text: String, value: String) -> Int {
        var body = text
        while let l = body.last, l.isWhitespace { body.removeLast() }
        let core = body.drop(while: { $0.isWhitespace })
        let lead = body.count - core.count
        guard value.hasSuffix(String(core)) else { return core.count }
        let before = value.dropLast(core.count)
        let leadInField = before.suffix(lead).allSatisfy { $0.isWhitespace } && before.count >= lead
        return core.count + (leadInField ? lead : 0)
    }
}

extension EarshotActionRunner {
    /// Presses a spoken key, `times` times, in the front app (I-34). See `KeyRules.block` for the rules.
    func pressKey(_ key: SpokenKey, times: Int, command: CommandInfo, watch: Stopwatch) async -> ActionOutcome {
        guard let pid = AX.frontPid() else { return fail("no front app") }
        let app = AX.appElement(pid)
        let focus = AX.focused(app).map { keyFocus($0, app: app) }
        if let block = KeyRules.block(key, times: times, focus: focus, sensitive: sensitiveNow(app: app, pid: pid)) {
            return fail(block)
        }
        await waitForKeysUp(watch)
        let combo = Keys.spoken(key)
        for i in 0..<times {
            if i > 0 { await sleepMs(Self.keyGapMs) }
            Keys.press(combo)
        }
        watch.mark("pressed")
        return ok(times > 1 ? "pressed \(times) times" : "pressed")
    }

    /// Removes the last text that earshot typed, with Backspace (I-34). The pipeline checks that the same app is in
    /// front. earshot does not use the app's menu Undo: its step differs between apps, and it can undo more than
    /// earshot typed.
    func undoTyping(_ typed: String, watch: Stopwatch) async -> ActionOutcome {
        guard let pid = AX.frontPid() else { return fail("no front app") }
        let app = AX.appElement(pid)
        guard let field = AX.focused(app), AX.isEditableText(field, allowSearch: true) else {
            return fail("the focus is not in a text field")
        }
        if let s = sensitiveNow(app: app, pid: pid) { return fail("blocked: this looks like a sign-in, code or payment page (\(s))") }
        let before = AX.value(field)
        switch KeyRules.undoPlan(typed: typed, value: before, caret: Self.caret(field)) {
        case .blocked(let why):
            return fail(why)
        case .backspaces(let n):
            await waitForKeysUp(watch)
            let backspace = Keys.spoken(.backspace)
            for i in 0..<n {
                if i > 0 { await sleepMs(Self.keyGapMs) }
                Keys.press(backspace)
            }
            watch.mark("pressed")
            let start = (before ?? "").count
            let gone = await waitUntil(timeoutMs: 1000) { (AX.value(field) ?? "").count <= start - n }
            return gone ? ok("removed \(n) characters") : fail("pressed Backspace \(n) times, but the text is still there")
        }
    }

    /// The wait between two presses of one key. Without it, some apps (Electron) drop presses.
    static let keyGapMs = 8

    func keyFocus(_ el: AXUIElement, app: AXUIElement) -> KeyFocus {
        let editable = AX.isEditableText(el, allowSearch: true)
        let window = AX.window(app).flatMap { AX.frame($0) }
        return KeyFocus(editable: editable, multiLine: AX.role(el) == "AXTextArea",
                        messageBox: KeyRules.messageBox(labelSaysComposer: AX.looksLikeComposer(el), field: AX.frame(el),
                                                        window: window))
    }

    /// The cursor position in UTF-16 units, if the field gives it. -1 if text is selected (see `KeyRules.undoPlan`).
    static func caret(_ field: AXUIElement) -> Int? {
        guard let v = AX.copy(field, "AXSelectedTextRange"), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(v as! AXValue, .cfRange, &range) else { return nil }
        return range.length == 0 ? range.location : -1
    }
}
