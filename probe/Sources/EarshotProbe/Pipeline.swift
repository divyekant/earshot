import AppKit
import ApplicationServices

/// The marker at the start of every text the probe types.
let testMarker = "[earshot test]"

final class Outcome {
    var ok = false
    var reason: String?
    var warm = false
    var openMethod = ""
    var focusMethod = "none"
    var nodes = 0
    var chatCheck = "unknown"
    /// True when a chat name on screen is exactly the person's name. Typing needs it.
    var chatExact = false
    var windowTitle = ""
    var header: [String] = []
    var typed = false
    var typedText: String?
    /// The message box that the probe typed into. The bench uses it to delete the test text.
    var typedBox: AXUIElement?
    var notes: [String] = []

    var dictionary: [String: Any] {
        var d: [String: Any] = [
            "ok": ok, "warm": warm, "open": openMethod, "focus": focusMethod, "nodes": nodes,
            "chat_check": chatCheck, "chat_exact": chatExact, "window_title": windowTitle, "header": Array(header.prefix(8)),
            "typed": typed, "notes": notes,
        ]
        if let reason { d["reason"] = reason }
        return d
    }
}

enum TypingMode { case off, selfOnly }

/// Runs one routed command: front app, open chat, focus box, type text.
/// It never presses Send (R-NV-5, R-ON-5).
@MainActor
final class Pipeline {
    let apps: [AppRow]
    /// The search field that the probe typed the name into, for the current command.
    private var searchField: AXUIElement?

    init(apps: [AppRow]) { self.apps = apps }

    func running(_ row: AppRow) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: row.bundleID).first
    }

    func appURL(_ row: AppRow) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: row.bundleID)
    }

    func handle(_ row: AppRow, _ person: Person) -> String? { person.handle(for: row) }

    func link(_ row: AppRow, _ person: Person) -> URL? {
        guard let template = row.openChat.template, let h = handle(row, person) else { return nil }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?#"))
        let encoded = h.addingPercentEncoding(withAllowedCharacters: allowed) ?? h
        return URL(string: template.replacingOccurrences(of: "{handle}", with: encoded))
    }

    /// Electron apps build their accessibility tree only when asked.
    /// Ask early, so that the first command does not pay for it.
    func prime() {
        for row in apps where row.electron == true {
            if let app = running(row) { AX.set(AX.appElement(app.processIdentifier), "AXManualAccessibility", kCFBooleanTrue) }
        }
    }

    func bringToFront(bundleID: String) async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        return await waitUntil(timeoutMs: 3000) {
            guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
            else { return false }
            return AX.frontPid() == pid
        }
    }

    func execute(_ cmd: Command, watch: Stopwatch, typing: TypingMode) async -> Outcome {
        let out = Outcome()
        let row = cmd.app
        searchField = nil
        guard let url = appURL(row) else {
            out.reason = "\(row.name) is not installed"
            return out
        }

        // Held modifier keys would change the keys that the probe sends.
        if Keys.modifiersDown() {
            _ = await waitUntil(timeoutMs: 1500) { !Keys.modifiersDown() }
            watch.mark("keys_up")
        }
        out.warm = running(row) != nil

        // 1. Bring the app to the front, through the chat link if the row has one.
        var usedLink = false
        if let person = cmd.person, row.openChat.kind == "link", let target = link(row, person) {
            usedLink = NSWorkspace.shared.open(target)
            out.openMethod = usedLink ? "link" : "link-failed"
        }
        if !usedLink {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
            if out.openMethod.isEmpty { out.openMethod = "app" }
        }
        let front = await waitUntil(timeoutMs: out.warm ? 3000 : 10000) {
            guard let pid = self.running(row)?.processIdentifier else { return false }
            return AX.frontPid() == pid
        }
        guard front, let pid = running(row)?.processIdentifier else {
            out.reason = "\(row.name) did not come to the front"
            return out
        }
        watch.mark("front")
        let app = AX.appElement(pid)
        if row.electron == true { AX.set(app, "AXManualAccessibility", kCFBooleanTrue) }

        guard let person = cmd.person else {
            // App only, or a name that matched nobody: open the app and stop.
            out.ok = cmd.unmatchedName == nil
            if let heard = cmd.unmatchedName { out.reason = "no test contact matches \"\(heard)\"" }
            return out
        }

        // 2. Open the chat with the switcher, if the row says so.
        if row.openChat.kind == "switcher" {
            guard let h = handle(row, person) else {
                out.reason = "people.json skips \(row.id) for \(person.name)"
                return out
            }
            if let failure = await openWithSwitcher(app: app, row: row, name: h) {
                out.reason = failure
                return out
            }
            out.openMethod = "switcher"
            watch.mark("chat")
        } else if !usedLink {
            out.reason = "\(person.name) has no \(row.id) handle in people.json"
            return out
        }

        // 3. Focus the message box.
        let focused = await focusComposer(app: app, out: out, waitForAppMs: usedLink ? 900 : 700)
        guard focused else {
            out.reason = "no message box found"
            return out
        }
        watch.mark("focus")

        // 4. Check that the chat on screen belongs to this person.
        checkChat(app: app, row: row, person: person, out: out)
        watch.mark("checked")
        // Reach needs the chat name on screen. A box in an unknown chat is not a pass.
        out.ok = out.chatCheck == "title" || out.chatCheck == "header"
        if !out.ok { out.reason = "the chat name is not on screen" }

        // 5. Type the text. Only into your own chat, only into an empty box.
        if let text = cmd.text {
            await typeText(text, app: app, row: row, person: person, mode: typing, out: out)
            if out.typed { watch.mark("typed") }
        }
        return out
    }

    // MARK: - Steps

    /// Opens the chat through the app's own search. Returns nil on success, else the reason for the failure.
    private func openWithSwitcher(app: AXUIElement, row: AppRow, name: String) async -> String? {
        let pick = row.openChat.pick ?? ["return"]
        guard pick.allSatisfy({ ["down", "up", "return"].contains($0) }),
              pick.filter({ $0 == "return" }).count <= 1,
              pick.firstIndex(of: "return").map({ $0 == pick.count - 1 }) ?? true
        else { return "bad pick keys in apps.json: only down, up and one return at the end" }

        // The search keys must move the focus. If the focus stays where it was, for example
        // in a reply box, the probe stops, so that it never types the name into a message box.
        let before = AX.focused(app)
        if let keys = row.openChat.keys {
            guard let combo = Keys.parse(keys) else { return "bad switcher keys in apps.json" }
            Keys.press(combo)
        } else if !focusSearchField(app) {
            return "no search field found"
        }
        var found: AXUIElement?
        let opened = await waitUntil(timeoutMs: 1200) {
            guard let el = AX.focused(app), let win = AX.window(app), AX.isSwitcherField(el, in: win) else { return false }
            if row.openChat.keys != nil, AX.same(el, before) { return false }
            found = el
            return true
        }
        guard opened, let field = found else { return "the search field did not get focus (\(describeFocus(app)))" }
        // A search field can keep the last search. Select it, so that the name replaces it.
        if !(AX.value(field) ?? "").isEmpty { Keys.press(Keys.selectAll) }

        Keys.type(name)
        let wanted = name.lowercased()
        // Some apps move the focus into an inner text field when typing starts. Accept the
        // focused element if it is the same field, or another search field that holds exactly the name.
        var typedInto: AXUIElement?
        let typed = await waitUntil(timeoutMs: 1000) {
            guard let el = AX.focused(app), let win = AX.window(app),
                  self.focusedValue(app)?.lowercased() == wanted,
                  AX.same(el, field) || AX.isSwitcherField(el, in: win) else { return false }
            typedInto = el
            return true
        }
        guard typed, let target = typedInto else {
            Keys.press(Keys.escape)
            return "the search field did not show the name (\(describeFocus(app)))"
        }
        searchField = target
        await sleepMs(row.openChat.settleMs ?? 250)

        for key in pick {
            if key == "return" {
                // SAFETY (R-NV-5): a Return in a message box sends the message.
                guard returnIsSafe(app, wanted: wanted, field: target) else {
                    let focus = describeFocus(app)
                    Keys.press(Keys.escape)
                    return "safety guard stopped the Return key (\(focus))"
                }
                Keys.press(Keys.returnKey)
            } else if let arrow = Keys.parse(key) {
                Keys.press(arrow)
                await sleepMs(60)
            }
        }
        return nil
    }

    /// For an app with no search shortcut: focus the search field through accessibility, else click it.
    private func focusSearchField(_ app: AXUIElement) -> Bool {
        guard let win = AX.window(app), let field = AX.findSearchField(in: win) else { return false }
        if AX.set(field, "AXFocused", kCFBooleanTrue), AX.same(AX.focused(app), field) { return true }
        guard let f = AX.frame(field) else { return false }
        Mouse.click(CGPoint(x: f.midX, y: f.midY))
        return true
    }

    /// The probe presses Return only in one of these two places:
    /// - the search field that the probe typed the name into, when it still holds exactly the name
    /// - a row of a result list, which is not a text field
    /// It never presses Return in a message box or on a button.
    private func returnIsSafe(_ app: AXUIElement, wanted: String, field: AXUIElement) -> Bool {
        guard let el = AX.focused(app), let win = AX.window(app) else { return false }
        if AX.isComposer(el, in: win) || AX.looksLikeComposer(el) { return false }
        if AX.same(el, field) {
            return AX.isSwitcherField(el, in: win)
                && AX.value(el)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted
        }
        // Any other text field: no Return.
        if AX.textRoles.contains(AX.role(el)) { return false }
        return AX.listRoles.contains(AX.role(el))
    }

    /// A short description of the focused element for the log. It holds no field text.
    private func describeFocus(_ app: AXUIElement) -> String {
        guard let el = AX.focused(app) else { return "no focus" }
        let sub = AX.subrole(el)
        let label = AX.label(el).prefix(40)
        return "focus: \(AX.role(el))\(sub.isEmpty ? "" : "/" + sub) \"\(label)\""
    }

    private func switcherFocused(_ app: AXUIElement) -> Bool {
        guard let el = AX.focused(app), let win = AX.window(app) else { return false }
        return AX.isSwitcherField(el, in: win)
    }

    private func focusedValue(_ app: AXUIElement) -> String? {
        guard let el = AX.focused(app) else { return nil }
        return AX.value(el)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func composerFocused(_ app: AXUIElement) -> Bool {
        guard let el = AX.focused(app), let win = AX.window(app) else { return false }
        return AX.isComposer(el, in: win)
    }

    private func focusComposer(app: AXUIElement, out: Outcome, waitForAppMs: Int) async -> Bool {
        // Most apps focus the message box by themselves after a chat opens.
        if await waitUntil(timeoutMs: waitForAppMs, { self.composerFocused(app) }) {
            out.focusMethod = "app"
            return true
        }
        guard let win = AX.window(app) else { return false }
        let (found, nodes) = AX.findComposer(in: win)
        out.nodes = nodes
        guard let box = found else { return false }
        AX.set(box, "AXFocused", kCFBooleanTrue)
        if await waitUntil(timeoutMs: 300, { self.composerFocused(app) }) {
            out.focusMethod = "set"
            return true
        }
        if let f = AX.frame(box) {
            Mouse.click(CGPoint(x: f.midX, y: f.midY))
            if await waitUntil(timeoutMs: 300, { self.composerFocused(app) }) {
                out.focusMethod = "click"
                return true
            }
        }
        return false
    }

    /// Looks for the person's name in the window title, or in the texts above the message box.
    /// "exact" needs a text that is the name and nothing more, apart from the words "you" and "dm".
    private func checkChat(app: AXUIElement, row: AppRow, person: Person, out: Outcome) {
        guard let win = AX.window(app) else { return }
        out.windowTitle = AX.string(win, "AXTitle") ?? ""
        var names = [person.name]
        if let h = person.handle(for: row) { names.append(h) }
        let exactKeys = Set(names.map { Text.normalize($0) }.filter { $0.count >= 2 })
        var words = names + (person.display ?? [])
        if !person.me { words += person.aliases ?? [] }
        let keys = words.map { Text.key($0) }.filter { $0.count >= 2 }
        func matches(_ s: String) -> Bool {
            let k = Text.key(s)
            return keys.contains { k.contains($0) }
        }
        func exact(_ s: String) -> Bool {
            // Window titles join parts with " - " or " | ". Test each part.
            let parts = s.components(separatedBy: " - ").flatMap { $0.components(separatedBy: " | ") }
            return parts.contains { part in
                let tokens = Text.normalize(part).split(separator: " ").filter { $0 != "you" && $0 != "dm" }
                return exactKeys.contains(tokens.joined(separator: " "))
            }
        }
        if exact(out.windowTitle) {
            out.chatExact = true
            out.chatCheck = "title"
            return
        }
        // The chat name sits above the message box, so read only that column.
        // Leave out the field that holds the typed name: it shows the name in any chat.
        let column = AX.focused(app).flatMap { AX.frame($0) }
        out.header = AX.headerTexts(in: win, column: column, skip: searchField)
        out.chatExact = out.header.contains(where: exact)
        if matches(out.windowTitle) {
            out.chatCheck = "title"
        } else if out.header.contains(where: matches) {
            out.chatCheck = "header"
        }
    }

    private func typeText(_ text: String, app: AXUIElement, row: AppRow, person: Person, mode: TypingMode, out: Outcome) async {
        guard mode == .selfOnly else { return }
        guard person.me else {
            out.notes.append("focus only: not your own chat")
            return
        }
        guard out.chatExact else {
            out.notes.append("no typing: no exact chat name on screen")
            return
        }
        guard let box = AX.focused(app), let win = AX.window(app), AX.isComposer(box, in: win) else {
            out.notes.append("no typing: focus moved")
            return
        }
        let current = AX.value(box)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let allowed = current.isEmpty || current.hasPrefix(testMarker) || row.typeIntoPrefilled == true
        guard allowed else {
            out.notes.append("no typing: the box holds a draft")
            return
        }
        let full = "\(testMarker) \(Text.printable(text))"
        let probe = String(Text.printable(text).prefix(12))
        Keys.type(current.isEmpty ? full : " " + full)
        out.typed = await waitUntil(timeoutMs: 1000) { (AX.value(box) ?? "").contains(probe) }
        if out.typed {
            out.typedText = full
            out.typedBox = box
        }
    }

    /// Deletes the probe's test text. It acts only when the box holds test text and nothing else:
    /// one or more copies of `expected`, apart from white space and invisible characters.
    /// It returns true on success, and a note for the log. The note holds no text from the box.
    func clearTyped(app pid: pid_t, box given: AXUIElement?, expected: String) async -> (Bool, String) {
        let app = AX.appElement(pid)
        guard let box = given ?? AX.focused(app) else { return (false, "no box") }
        guard let win = AX.window(app), AX.isComposer(box, in: win) else { return (false, "not the message box now") }
        let value = Text.squash(AX.value(box) ?? "")
        let test = Text.squash(expected)
        let rest = value.replacingOccurrences(of: test, with: "").trimmingCharacters(in: .whitespaces)
        guard value.contains(test), rest.isEmpty else {
            return (false, "box holds other text: \(value.count) characters, test text \(test.count)")
        }
        if !AX.same(AX.focused(app), box) {
            AX.set(box, "AXFocused", kCFBooleanTrue)
            guard await waitUntil(timeoutMs: 300, { AX.same(AX.focused(app), box) }) else {
                return (false, "could not focus the box")
            }
        }
        Keys.press(Keys.selectAll)
        Keys.press(Keys.deleteKey)
        let empty = await waitUntil(timeoutMs: 800) { Text.squash(AX.value(box) ?? "").isEmpty }
        return (empty, empty ? "cleared" : "text still there after delete")
    }
}
