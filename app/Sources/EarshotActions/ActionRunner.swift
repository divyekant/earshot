// T3 owns this module. See docs/BUILD-PLAN.md.
import AppKit
import ApplicationServices
import EarshotCore

/// Runs one intent in the user interface of the Mac (R-MD-6). It obeys SafetyPolicy (R-NV-5, R-ON-5).
///
/// Rules that every action obeys:
/// - Only approved and enabled catalogue rows (R-MT-2). No code names an app (R-MT-1).
/// - Never press Return in a message box, except for "send" from a held-key command that the rules decided.
/// - Never press a risky label, except when the owner said that exact label with the hold key (SafetyPolicy.mayPress).
/// - Never click, type or send on a sign-in, code or payment page.
/// - Click only on the page of the visible tab, and only at a point where the top element on screen is the target.
@MainActor
public final class EarshotActionRunner: ActionRunner {
    public var options: ActionOptions
    private let store: Store?
    /// The focus method that worked last time for each app id: "app", "set" or "click" (E0).
    private var learnedFocus: [String: String]
    /// The last screen read. "Click e3" finds its element here.
    private var last: ScreenRead?
    private let overlay = NumberOverlay()
    /// The field that earshot typed the chat name into, for the current command.
    private var searchField: AXUIElement?
    private var focusMethod = "none"

    static let learnedFile = "focus-methods.json"

    /// `store` keeps the learned focus methods. Pass nil to keep them in memory only (tests).
    public init(options: ActionOptions = ActionOptions(), store: Store? = Store()) {
        self.options = options
        self.store = store
        learnedFocus = store?.load([String: String].self, Self.learnedFile) ?? [:]
    }

    // MARK: - ActionRunner

    /// Runs the intent with the strictest command facts: no risky press and no send (CommandInfo.unknown).
    public func run(_ intent: Intent, context: RouteContext) async -> ActionOutcome {
        await run(intent, context: context, command: .unknown)
    }

    /// Runs the intent. `command` gives the input mode, the router tier and the spoken target for the safety rules.
    public func run(_ intent: Intent, context: RouteContext, command: CommandInfo) async -> ActionOutcome {
        let watch = Stopwatch()
        guard AX.trusted() else { return fail("the Accessibility permission is off") }
        var out: ActionOutcome
        switch intent {
        case .none: out = ok("nothing to do")
        case .openApp(let appID): out = await openApp(appID, context: context, watch: watch)
        case let .openChat(appID, target, text): out = await openChat(appID, target: target, text: text, context: context, watch: watch)
        case .click(let id): out = await click(id, command: command, watch: watch)
        case let .typeInto(id, text): out = await typeInto(id, text: text, watch: watch)
        case .typeText(let text): out = await typeText(text, watch: watch)
        case .scroll(let direction): out = await scroll(direction, watch: watch)
        case .back: out = await back(watch: watch)
        case .showNumbers: out = await showNumbers(watch: watch)
        case .hideNumbers:
            overlay.hide()
            out = ok("numbers hidden")
        case .send: out = await send(command: command, watch: watch)
        }
        watch.mark("total")
        out.stages = watch.stages.merging(out.stages) { a, _ in a }
        return out
    }

    /// The front window and its elements. While numbers are on screen, it gives the numbered read.
    public func screen() async -> ScreenSnapshot? { await screen(ocr: false) }

    /// The front window and its elements. With `ocr`, the OCR fallback also runs when the window has many labels,
    /// for example when the router found no label for the command (R-CL-4).
    public func screen(ocr: Bool) async -> ScreenSnapshot? {
        if overlay.shown, let last, AX.frontPid() == last.pid, windowFrame(last.pid) == last.window { return last.snapshot }
        overlay.hide()
        return await freshRead(forceOCR: ocr)?.snapshot
    }

    // MARK: - Apps and chats

    private struct Fronted {
        let app: AXUIElement
        let pid: pid_t
    }

    private func approvedEntry(_ appID: String, _ context: RouteContext) -> (AppEntry?, String?) {
        guard let e = context.apps.first(where: { $0.id == appID }) else { return (nil, "no app \"\(appID)\" in the catalogue") }
        guard e.approved else { return (nil, "\(e.name) is not approved in the Apps tab") }
        guard e.enabled else { return (nil, "\(e.name) is off in the Apps tab") }
        return (e, nil)
    }

    private func running(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// Held modifier keys, for example the hold key, would change the keys and clicks that earshot sends.
    private func waitForKeysUp(_ watch: Stopwatch) async {
        guard Keys.modifiersDown() else { return }
        _ = await waitUntil(timeoutMs: 1500) { !Keys.modifiersDown() }
        watch.mark("keys_up")
    }

    /// Brings the app to the front. With `link`, the app opens the link and comes to the front with it.
    private func bringToFront(_ e: AppEntry, link: URL?, watch: Stopwatch) async -> (Fronted?, String?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: e.bundleID) else { return (nil, "\(e.name) is not installed") }
        let warm = running(e.bundleID) != nil
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let link {
            NSWorkspace.shared.open([link], withApplicationAt: url, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
        let front = await waitUntil(timeoutMs: warm ? 3000 : 10000) {
            guard let pid = self.running(e.bundleID)?.processIdentifier else { return false }
            return AX.frontPid() == pid
        }
        guard front, let pid = running(e.bundleID)?.processIdentifier else { return (nil, "\(e.name) did not come to the front") }
        watch.mark("front")
        let app = AX.appElement(pid)
        if e.electron { AX.set(app, "AXManualAccessibility", kCFBooleanTrue) }
        return (Fronted(app: app, pid: pid), nil)
    }

    private func openApp(_ appID: String, context: RouteContext, watch: Stopwatch) async -> ActionOutcome {
        let (found, why) = approvedEntry(appID, context)
        guard let e = found else { return fail(why ?? "no app") }
        await waitForKeysUp(watch)
        let (fronted, error) = await bringToFront(e, link: nil, watch: watch)
        return fronted == nil ? fail(error ?? "no front") : ok("→ \(e.name)")
    }

    private func openChat(_ appID: String, target: String, text: String?, context: RouteContext, watch: Stopwatch) async -> ActionOutcome {
        let (found, why) = approvedEntry(appID, context)
        guard let e = found else { return fail(why ?? "no app") }
        let entry = ActionRules.nameEntry(target, appID: appID, names: context.names)
        let shown = entry?.name ?? target
        searchField = nil
        focusMethod = "none"

        var link: URL?
        switch e.openChat {
        case .none:
            return fail("\(e.name) has no way to open a chat in the catalogue")
        case .link(let template):
            link = ActionRules.linkURL(template: template, handle: ActionRules.handle(name: shown, aliases: entry?.aliases ?? []))
            if link == nil { return fail("the chat link of \(e.name) has no {handle}") }
        case .switcher(let keys):
            guard ActionRules.switcherKeysValid(keys) else { return fail("the switcher keys of \(e.name) are not valid: \(keys)") }
        }

        await waitForKeysUp(watch)
        let (fronted, error) = await bringToFront(e, link: link, watch: watch)
        guard let f = fronted else { return fail(error ?? "no front") }

        // 1. Open the chat through the app's own search.
        if case .switcher(let keys) = e.openChat {
            if let failure = await openWithSwitcher(app: f.app, keys: keys, name: shown, watch: watch) { return fail(failure) }
            watch.mark("chat")
        }
        // 2. Focus the message box.
        guard let box = await focusComposer(app: f.app, appID: e.id, waitForAppMs: link != nil ? 900 : 500) else {
            return fail("no message box found in \(e.name)")
        }
        watch.mark("focus")
        // 3. Check that the chat on screen has the name.
        let check = checkChat(app: f.app, names: [shown, target] + (entry?.aliases ?? []))
        watch.mark("checked")
        let head = "→ \(e.name) · \(shown)"
        guard check != .none else { return fail("\(head): the chat name is not on screen") }

        // 4. Type the text, if the command has text. Typing is not Send: earshot never presses Return here.
        guard let text, !ActionText.squash(ActionText.printable(text)).isEmpty else { return ok(head) }
        if let block = ActionRules.typeBlock(isSelf: entry?.isSelf ?? false, typeIntoOthers: options.typeIntoOthers,
                                             check: check, boxText: AX.value(box) ?? "") {
            // Focus only, as the settings say, is a success. A missing name or a draft is not.
            return ActionOutcome(ok: !options.typeIntoOthers && !(entry?.isSelf ?? false), note: "\(head): \(block)")
        }
        guard AX.same(AX.focused(f.app), box) else { return fail("\(head): no typing: the focus moved") }
        let typed = await typeAndCheck(text, into: box)
        if typed { watch.mark("typed") }
        return typed ? ok("\(head): typed") : fail("\(head): the text did not show in the box")
    }

    /// Opens the chat through the app's own search. Returns nil on success, else the reason for the failure.
    private func openWithSwitcher(app: AXUIElement, keys: String, name: String, watch: Stopwatch) async -> String? {
        // The search keys must move the focus. If the focus stays where it was, for example in a reply box,
        // earshot stops, so that it never types the name into a message box.
        let before = AX.focused(app)
        // The switcher-shaped fields that exist before the keys. A field that shows after the keys is the switcher.
        let oldFields = AX.window(app).map { AX.switcherFields(in: $0) } ?? []
        if keys.isEmpty {
            guard focusSearchField(app) else { return "no search field found" }
        } else {
            guard let combo = Keys.parse(keys) else { return "bad switcher keys: \(keys)" }
            Keys.press(combo)
        }
        // Wait until the switcher field has focus. If it shows without focus (Messages "To:"), set the focus through AX.
        let (found, failure) = await waitForSwitcherField(
            focused: { () -> (AXUIElement?, Bool, Bool) in
                guard let el = AX.focused(app), let win = AX.window(app) else { return (nil, false, false) }
                let isNew = keys.isEmpty || !AX.same(el, before)
                return (el, isNew && AX.isSwitcherField(el, in: win), AX.isComposer(el, in: win) || AX.looksLikeComposer(el))
            },
            newField: { () -> AXUIElement? in
                guard let win = AX.window(app) else { return nil }
                return AX.switcherFields(in: win).first { f in !oldFields.contains { CFEqual($0, f) } }
            },
            setFocus: { AX.set($0, "AXFocused", kCFBooleanTrue) })
        guard let field = found else { return "\(failure ?? "no search field") (\(AX.describeFocus(app)))" }
        // Never type the name while the focus is in a message box.
        guard let now = AX.focused(app), AX.same(now, field), let win = AX.window(app),
              !AX.isComposer(now, in: win), !AX.looksLikeComposer(now) else { return "the focus left the search field: nothing typed" }
        watch.mark("switcher")
        // The texts that match the name before typing, for example the chat in the sidebar. They do not count as results.
        let fieldFrame = AX.frame(field)
        let baseline = fieldFrame.map { ActionRules.matchKeys(AX.textsBelow($0, app: app, skip: field), name: name) } ?? []
        // A search field can keep the last search. Select it, so that the name replaces it.
        if !(AX.value(field) ?? "").isEmpty { Keys.press(Keys.selectAll) }
        Keys.type(name)
        let wanted = name.lowercased()
        // Some apps move the focus into an inner field when typing starts. Accept the same field,
        // or another search field that holds exactly the name.
        var typedInto: AXUIElement?
        let typed = await waitUntil(timeoutMs: SwitcherTiming.typedMs, intervalMs: SwitcherTiming.pollMs) {
            guard let el = AX.focused(app), let win = AX.window(app),
                  AX.value(el)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted,
                  AX.same(el, field) || AX.isSwitcherField(el, in: win) else { return false }
            typedInto = el
            return true
        }
        guard typed, let target = typedInto else {
            Keys.press(Keys.escape)
            return "the search field did not show the name (\(AX.describeFocus(app)))"
        }
        searchField = target
        watch.mark("name")
        // Wait until the result list shows a new text that matches the name, in place of a fixed sleep.
        let shown = await waitForResult(name: name, baseline: baseline) {
            guard let f = AX.frame(target) ?? fieldFrame else { return [] }
            return AX.textsBelow(f, app: app, skip: target)
        }
        guard shown else {
            Keys.press(Keys.escape)
            return "the search results did not show \"\(name)\" in \(SwitcherTiming.resultMs) ms"
        }
        watch.mark("result")
        // SAFETY (R-NV-5): Return in a message box sends the message.
        guard returnIsSafe(app, wanted: wanted, field: target) else {
            let focus = AX.describeFocus(app)
            Keys.press(Keys.escape)
            return "the safety check stopped the Return key (\(focus))"
        }
        Keys.press(Keys.returnKey)
        return nil
    }

    /// Waits until the focus is in a new switcher field. `focused` gives the focused element, whether it is a new
    /// switcher field, and whether it is a message box. If a new switcher field shows without focus, `setFocus` focuses it.
    /// It returns the field, or the reason for the time-out. The caller types nothing on a time-out.
    func waitForSwitcherField<T>(timeoutMs: Int = SwitcherTiming.fieldMs, focused: () -> (T?, Bool, Bool),
                                 newField: () -> T?, setFocus: (T) -> Void) async -> (T?, String?) {
        let t0 = Clock.nowNs()
        var lastScan = -Double(SwitcherTiming.scanMs)
        var inBox = false
        var sawField = false
        while true {
            let (el, isSwitcher, isComposer) = focused()
            if isSwitcher, let el { return (el, nil) }
            inBox = isComposer
            let now = Clock.ms(since: t0)
            if now - lastScan >= Double(SwitcherTiming.scanMs) {
                lastScan = now
                if let f = newField() {
                    sawField = true
                    setFocus(f)
                    continue
                }
            }
            if now >= Double(timeoutMs) { break }
            await sleepMs(SwitcherTiming.pollMs)
        }
        if sawField { return (nil, "the search field showed, but did not take the focus in \(timeoutMs) ms: nothing typed") }
        if inBox { return (nil, "the focus stayed in the message box for \(timeoutMs) ms: nothing typed") }
        return (nil, "the search field did not show in \(timeoutMs) ms: nothing typed")
    }

    /// Polls `read` until a text that matches the name and is not in `baseline` shows on screen.
    func waitForResult(name: String, baseline: Set<String>, timeoutMs: Int = SwitcherTiming.resultMs,
                       read: () -> [(String, Frame)]) async -> Bool {
        await waitUntil(timeoutMs: timeoutMs, intervalMs: SwitcherTiming.pollMs) {
            ActionRules.resultShows(read(), name: name, baseline: baseline)
        }
    }

    /// For an app with no search keys: focus the search field through accessibility, else click it.
    private func focusSearchField(_ app: AXUIElement) -> Bool {
        guard let win = AX.window(app), let field = AX.findSearchField(in: win) else { return false }
        if AX.set(field, "AXFocused", kCFBooleanTrue), AX.same(AX.focused(app), field) { return true }
        guard let f = AX.frame(field), let p = safePoint(field, f) else { return false }
        Mouse.click(p)
        return true
    }

    private func returnIsSafe(_ app: AXUIElement, wanted: String, field: AXUIElement) -> Bool {
        guard let el = AX.focused(app), let win = AX.window(app) else { return false }
        let composer = AX.isComposer(el, in: win) || AX.looksLikeComposer(el)
        guard SafetyPolicy.mayPressReturn(for: .openChat(appID: "", target: wanted, text: nil), inMessageBox: composer) else { return false }
        return ActionRules.switcherReturnSafe(focusedIsComposer: composer, focusedIsTypedField: AX.same(el, field),
                                              focusedIsSwitcherField: AX.isSwitcherField(el, in: win), focusedValue: AX.value(el),
                                              wanted: wanted, focusedRole: AX.role(el))
    }

    /// Focuses the message box. earshot remembers, for each app, which method worked last time:
    /// "app" (the app focuses the box by itself), "set" (accessibility) or "click" (E0).
    private func focusComposer(app: AXUIElement, appID: String, waitForAppMs: Int) async -> AXUIElement? {
        func focusedBox() -> AXUIElement? {
            guard let el = AX.focused(app), let win = AX.window(app), AX.isComposer(el, in: win) else { return nil }
            return el
        }
        let learned = learnedFocus[appID]
        let wait = (learned == nil || learned == "app") ? waitForAppMs : 60
        if await waitUntil(timeoutMs: wait, { focusedBox() != nil }), let box = focusedBox() {
            learn(appID, "app")
            return box
        }
        guard let win = AX.window(app) else { return nil }
        // The new chat can take a moment to show its box.
        var found: AXUIElement?
        _ = await waitUntil(timeoutMs: 500, intervalMs: 30) {
            found = AX.findComposer(in: win, budgetMs: 150).0
            return found != nil
        }
        guard let box = found else { return nil }
        if learned != "click" {
            AX.set(box, "AXFocused", kCFBooleanTrue)
            if await waitUntil(timeoutMs: 150, { focusedBox() != nil }), let b = focusedBox() {
                learn(appID, "set")
                return b
            }
        }
        if let f = AX.frame(box), let p = safePoint(box, f) {
            Mouse.click(p)
            if await waitUntil(timeoutMs: 300, { focusedBox() != nil }), let b = focusedBox() {
                learn(appID, "click")
                return b
            }
        }
        return nil
    }

    private func learn(_ appID: String, _ method: String) {
        focusMethod = method
        guard learnedFocus[appID] != method else { return }
        learnedFocus[appID] = method
        try? store?.save(learnedFocus, Self.learnedFile)
    }

    /// Looks for the chat name in the window title, then in the texts above the message box.
    private func checkChat(app: AXUIElement, names: [String]) -> ChatCheck {
        guard let win = AX.window(app) else { return .none }
        let title = AX.string(win, "AXTitle") ?? ""
        if ActionRules.chatCheck(texts: [title], names: names) == .exact { return .exact }
        // The chat name sits above the message box, so read only that column.
        // Leave out the field that holds the typed name: it shows the name in any chat.
        let column = AX.focused(app).flatMap { AX.frame($0) }
        var header = AX.headerHits(app: app, window: win, column: column, skip: searchField)
        if ActionRules.chatCheck(texts: header, names: names) != .exact {
            for s in AX.headerTexts(in: win, column: column, skip: searchField) where !header.contains(s) { header.append(s) }
        }
        return ActionRules.chatCheck(texts: [title] + header, names: names)
    }

    /// Types the text as key events and waits until the field shows its start.
    private func typeAndCheck(_ text: String, into field: AXUIElement) async -> Bool {
        let clean = ActionText.printable(text)
        let probe = String(ActionText.squash(clean).prefix(12))
        Keys.type(clean)
        return await waitUntil(timeoutMs: 1000) { ActionText.squash(AX.value(field) ?? "").contains(probe) }
    }

    // MARK: - Typing into the front app

    private func typeText(_ text: String, watch: Stopwatch) async -> ActionOutcome {
        guard let pid = AX.frontPid() else { return fail("no front app") }
        let app = AX.appElement(pid)
        guard let el = AX.focused(app), AX.isEditableText(el, allowSearch: true) else { return fail("the focus is not in a text field") }
        if let s = sensitiveNow(app: app, pid: pid) { return fail("blocked: this looks like a sign-in, code or payment page (\(s))") }
        await waitForKeysUp(watch)
        let typed = await typeAndCheck(text, into: el)
        if typed { watch.mark("typed") }
        return typed ? ok("typed") : fail("the text did not show in the field")
    }

    private func typeInto(_ id: String, text: String, watch: Stopwatch) async -> ActionOutcome {
        let (found, why) = await target(id)
        guard let pair = found else { return fail(why ?? "no element") }
        let (read, item) = pair
        guard let h = item.handle else { return fail("\(id) is not a text field") }
        let sensitive = SafetyPolicy.sensitive(url: read.snapshot.url, elements: read.snapshot.elements)
        if let block = ActionRules.typeIntoBlock(role: item.element.role, subrole: item.element.subrole, sensitive: sensitive) { return fail(block) }
        if read.web, read.areaPath != "hit test" { return fail("not typed: the page can be a hidden tab") }
        await waitForKeysUp(watch)
        let app = AX.appElement(read.pid)
        func inField() -> Bool { AX.same(AX.focused(app), h) || AX.elements(h, "AXChildren").contains { AX.same(AX.focused(app), $0) } }
        // Set the focus and check it. Setting the value of a Chrome web field fails. Key events work (E2, section 7).
        AX.set(h, "AXFocused", kCFBooleanTrue)
        var focused = await waitUntil(timeoutMs: 400) { inField() }
        if !focused, let f = AX.frame(h), let p = safePoint(h, f) {
            Mouse.click(p)
            focused = await waitUntil(timeoutMs: 400) { inField() }
        }
        guard focused, let field = AX.focused(app) else { return fail("could not focus the field \"\(item.element.label)\"") }
        watch.mark("focus")
        if !(AX.value(field) ?? "").isEmpty { Keys.press(Keys.selectAll) }
        let typed = await typeAndCheck(text, into: field)
        guard typed else { return fail("the text did not show in the field") }
        watch.mark("typed")
        // Return runs a search. earshot presses it only in a search field, never in a message box or a form field.
        let isSearch = item.element.subrole == "AXSearchField" || ActionRules.labelSaysSearch(item.element.label.lowercased())
        let inBox = (AX.window(app).map { AX.isComposer(field, in: $0) } ?? true) || AX.looksLikeComposer(field)
        if isSearch, !inBox, SafetyPolicy.mayPressReturn(for: .typeInto(elementID: id, text: text), inMessageBox: inBox) {
            Keys.press(Keys.returnKey)
            watch.mark("search")
            return ok("searched for \"\(ActionText.printable(text))\"")
        }
        return ok("typed into \"\(item.element.label)\"")
    }

    // MARK: - Clicks

    /// The element of the last screen read, if the front window is still the same.
    private func target(_ id: String) async -> ((ScreenRead, ReadElement)?, String?) {
        guard let read = last else { return (nil, "no screen read: say the command again") }
        guard let item = read.items[id] else { return (nil, "no element \(id) on the screen") }
        guard Clock.ms(since: read.at) <= options.maxSnapshotAgeMs else { return (nil, "the screen read is too old: say the command again") }
        guard AX.frontPid() == read.pid else { return (nil, "the front window changed: say the command again") }
        // The numbers must not cover the hit test.
        if overlay.shown {
            overlay.hide()
            await sleepMs(30)
        }
        return ((read, item), nil)
    }

    private func click(_ id: String, command: CommandInfo, watch: Stopwatch) async -> ActionOutcome {
        let (found, why) = await target(id)
        guard let pair = found else { return fail(why ?? "no element") }
        let (read, item) = pair
        let label = item.element.label
        let sensitive = SafetyPolicy.sensitive(url: read.snapshot.url, elements: read.snapshot.elements)
        if let block = ActionRules.pressBlock(label: label, role: item.element.role, command: command, sensitive: sensitive) { return fail(block) }
        // Chrome keeps hidden tabs in the tree and ignores a press on them (E2 live run 1).
        if read.web, read.areaPath != "hit test" { return fail("not clicked: the page can be a hidden tab") }
        await waitForKeysUp(watch)

        // An OCR text has no accessibility element: click its middle, if the top element there is this app's.
        guard let h = item.handle else {
            guard windowFrame(read.pid) == read.window else { return fail("the window moved: say the command again") }
            let p = CGPoint(x: item.element.x + item.element.w / 2, y: item.element.y + item.element.h / 2)
            guard let top = AX.hit(p), AX.pid(top) == read.pid, frontmost(read.pid) else { return fail("\"\(label)\" is covered") }
            Mouse.click(p)
            watch.mark("pressed")
            return ok("clicked \"\(label)\" (text on screen)")
        }

        // Read back: the live element must still show the same label.
        let everywhere = Frame(x: -1e6, y: -1e6, w: 2e6, h: 2e6)
        guard let live = ScreenReader.describe(h, viewport: everywhere), live.label == label else {
            return fail("\"\(label)\" changed on screen: say the command again")
        }
        watch.mark("checked")

        if item.kind == "field" {
            AX.set(h, "AXFocused", kCFBooleanTrue)
            var focused = await waitUntil(timeoutMs: 300) { AX.same(AX.focused(AX.appElement(read.pid)), h) }
            if !focused, let p = safePoint(h, live.frame), frontmost(read.pid) {
                Mouse.click(p)
                focused = await waitUntil(timeoutMs: 300) { AX.same(AX.focused(AX.appElement(read.pid)), h) }
            }
            watch.mark("pressed")
            return focused ? ok("focused \"\(label)\"") : fail("could not focus \"\(label)\"")
        }

        // AXPress if the element offers it. A Chrome link does not: AXPress returns success and does nothing (E2, 5.6).
        if AX.actions(h).contains(kAXPressAction as String) {
            let done = AX.perform(h, kAXPressAction as String)
            watch.mark("pressed")
            return done ? ok("clicked \"\(label)\"") : fail("the press on \"\(label)\" failed")
        }
        // Else a click at a point where the top element on screen is the element. If there is none,
        // scroll the element into view and try again (E2, section 7).
        var point = safePoint(h, live.frame)
        if point == nil {
            AX.perform(h, "AXScrollToVisible")
            await sleepMs(150)
            if let f = AX.frame(h) { point = safePoint(h, f) }
        }
        guard let p = point else { return fail("\"\(label)\" is not visible on screen") }
        guard frontmost(read.pid) else { return fail("the app is not in front") }
        Mouse.click(p)
        watch.mark("pressed")
        return ok("clicked \"\(label)\"")
    }

    private func frontmost(_ pid: pid_t) -> Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }

    /// True if `node` is `target`, or the same link: same role, same address and same frame.
    private func sameElement(_ node: AXUIElement, _ target: AXUIElement) -> Bool {
        if CFEqual(node, target) { return true }
        let r = AX.role(node)
        guard r == AX.role(target), r == "AXLink", let a = ScreenReader.address(node), a == ScreenReader.address(target),
              let f = AX.frame(node), let g = AX.frame(target) else { return false }
        return abs(f.x - g.x) < 1 && abs(f.y - g.y) < 1 && abs(f.w - g.w) < 1 && abs(f.h - g.h) < 1
    }

    /// A point where the top element on screen, over all apps, is the target or a part of it.
    /// The hit test gives the deepest element, so it goes up the parents.
    private func safePoint(_ target: AXUIElement, _ f: Frame) -> CGPoint? {
        for p in ActionRules.clickPoints(f) {
            guard var node = AX.hit(p) else { continue }
            for _ in 0..<8 {
                if sameElement(node, target) { return p }
                guard let parent = AX.element(node, "AXParent") else { break }
                node = parent
            }
        }
        return nil
    }

    // MARK: - Scroll and back

    private func scroll(_ direction: ScrollDirection, watch: Stopwatch) async -> ActionOutcome {
        guard let pid = AX.frontPid() else { return fail("no front app") }
        let app = AX.appElement(pid)
        guard let win = AX.window(app), let wf = AX.frame(win) else { return fail("no front window") }
        await waitForKeysUp(watch)
        var area = ScreenReader.visibleWebArea(win)
        // Keys in a text field move the cursor, not the page. Move the focus to the page first.
        if let a = area, let f = AX.focused(app), AX.textRoles.contains(AX.role(f)) {
            AX.set(a, "AXFocused", kCFBooleanTrue)
            let moved = await waitUntil(timeoutMs: 150, { !(AX.focused(app).map { AX.textRoles.contains(AX.role($0)) } ?? false) })
            if !moved { area = nil }
        }
        switch ActionRules.scrollPlan(direction, web: area != nil) {
        case .key(let combo):
            Keys.press(combo)
        case let .wheel(lines, times):
            let box = area.flatMap { AX.frame($0) } ?? wf
            let p = CGPoint(x: box.midX, y: box.midY)
            guard let top = AX.hit(p), AX.pid(top) == pid else { return fail("the window is covered") }
            Mouse.scroll(at: p, lines: lines, times: times)
        }
        watch.mark("scrolled")
        return ok("scrolled \(direction.rawValue)")
    }

    private func back(watch: Stopwatch) async -> ActionOutcome {
        guard let pid = AX.frontPid() else { return fail("no front app") }
        let app = AX.appElement(pid)
        await waitForKeysUp(watch)
        // The app's own Back command in its menu bar, for example History > Back or Go > Back.
        for title in ["Back", "Go Back"] {
            if let item = AX.menuItem(app, titled: title), AX.perform(item, kAXPressAction as String) {
                watch.mark("back")
                return ok("back")
            }
        }
        // Else the Back button of the toolbar.
        if let win = AX.window(app), let b = ScreenReader.backButton(in: win) {
            if AX.actions(b).contains(kAXPressAction as String), AX.perform(b, kAXPressAction as String) {
                watch.mark("back")
                return ok("back")
            }
            if let f = AX.frame(b), let p = safePoint(b, f), frontmost(pid) {
                Mouse.click(p)
                watch.mark("back")
                return ok("back")
            }
        }
        return fail("this app has no Back command")
    }

    // MARK: - Numbers and send

    private func showNumbers(watch: Stopwatch) async -> ActionOutcome {
        overlay.hide()
        guard let read = await freshRead(forceOCR: false) else { return fail("earshot cannot read the front window") }
        watch.mark("read")
        guard !read.snapshot.elements.isEmpty else { return fail("no clickable elements in the front window") }
        overlay.show(read.snapshot.elements)
        watch.mark("shown")
        return ok("\(read.snapshot.elements.count) numbers")
    }

    private func send(command: CommandInfo, watch: Stopwatch) async -> ActionOutcome {
        guard let pid = AX.frontPid() else { return fail("no front app") }
        let app = AX.appElement(pid)
        let el = AX.focused(app)
        var inBox = false
        if let el, let win = AX.window(app) {
            inBox = AX.isComposer(el, in: win) || (AX.isEditableText(el) && AX.looksLikeComposer(el))
        }
        let boxText = el.flatMap { AX.value($0) } ?? ""
        if let block = ActionRules.sendBlock(command: command, inMessageBox: inBox, boxText: boxText,
                                             sensitive: sensitiveNow(app: app, pid: pid)) { return fail(block) }
        guard let box = el else { return fail("no focus") }
        await waitForKeysUp(watch)
        Keys.press(Keys.returnKey)
        watch.mark("sent")
        let cleared = await waitUntil(timeoutMs: 1500) { ActionText.squash(AX.value(box) ?? "").isEmpty }
        return cleared ? ok("sent") : fail("Return pressed, but the box still holds text")
    }

    // MARK: - Screen reads

    private func windowFrame(_ pid: pid_t) -> Frame? { AX.window(AX.appElement(pid)).flatMap { AX.frame($0) } }

    private func freshRead(forceOCR: Bool) async -> ScreenRead? {
        guard AX.trusted(), let pid = AX.frontPid(), pid != getpid() else { return nil }
        guard var read = ScreenReader.read(pid: pid, maxElements: options.maxElements) else { return nil }
        let labelled = read.snapshot.elements.filter { !$0.label.isEmpty }.count
        if options.ocrFallback, forceOCR || labelled < options.ocrBelow, OCR.allowed() {
            read = ScreenReader.adding(ocr: await OCR.read(pid: pid, window: read.window), to: read)
        }
        last = read
        return read
    }

    /// The reason, if the front app shows a sign-in, code or payment page. It uses the last read of the same app,
    /// the page address, and the focused field.
    private func sensitiveNow(app: AXUIElement, pid: pid_t) -> String? {
        if let f = AX.focused(app), AX.subrole(f) == "AXSecureTextField" { return "a password field" }
        var url: String?
        var elements: [ScreenElement] = []
        if let last, last.pid == pid, Clock.ms(since: last.at) < 10_000 {
            url = last.snapshot.url
            elements = last.snapshot.elements
        }
        if url == nil, let win = AX.window(app), let area = ScreenReader.visibleWebArea(win) { url = ScreenReader.address(area) }
        return SafetyPolicy.sensitive(url: url, elements: elements)
    }

    private func ok(_ note: String) -> ActionOutcome { ActionOutcome(ok: true, note: note) }
    private func fail(_ note: String) -> ActionOutcome { ActionOutcome(ok: false, note: note) }
}
