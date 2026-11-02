import AppKit

// e2-press: which way of pressing makes Chrome follow a link?
// In E2 live run 2, AXPress on 22 links in the visible tab returned success, but no page changed.
// This command opens one test page, picks one plain link to another page of the same site,
// and tries each way once. See docs/experiments/E2-web-and-speech.md, section 5.6.
//
// Safety: it presses one link only. It never presses Return, a button, a field or a risky label.
// It goes back after each page change. The real mouse click runs only with --mouse.
// Run it only after the owner agrees, and while nobody uses the Mac.

@MainActor
enum E2Press {
    struct Target {
        let element: AXUIElement
        let item: WebElement
    }

    struct Outcome {
        let way: String
        let result: String
        let changed: Bool
        let callMs: Double?
        let changeMs: Double?
    }

    /// Words of labels that lead to a sign-in or account page. The test link must not have them.
    static let accountWords = ["log in", "login", "sign in", "sign up", "create account", "register", "account"]

    static func host(_ u: String) -> String {
        let h = URL(string: u)?.host ?? ""
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// A plain link to another page of the same site, inside the visible part of the page.
    /// The first such link below the top 120 points of the page, in reading order.
    static func pick(_ read: LiveRead, area: Frame, start: String, label: String?) -> Int? {
        let startBare = E2.bare(start)
        let startPath = URL(string: start)?.path ?? ""
        for (i, e) in read.elements.enumerated() where e.kind == "link" {
            guard let u = e.url, let url = URL(string: u) else { continue }
            if let label {
                if Text.key(e.label) == Text.key(label) { return i }
                continue
            }
            let key = Text.key(e.label)
            guard host(u) == host(start), E2.bare(u) != startBare, url.path != startPath, url.query == nil,
                  !WebRouter.isRisky(e.label), !accountWords.contains(where: { key.contains($0) }),
                  e.label.count >= 3,
                  e.y >= area.y + 120, e.y + e.h <= area.maxY - 60, e.x >= area.x, e.x + e.w <= area.x + area.w
            else { continue }
            return i
        }
        return nil
    }

    /// Reads the page again and finds the same link (same label and address). Each way gets a fresh element.
    static func find(_ app: AXUIElement, _ item: WebElement) -> Target? {
        guard let read = WebPage.read(app, headings: false), read.areaPath == "hit test" else { return nil }
        guard let i = read.elements.firstIndex(where: { $0.label == item.label && $0.url == item.url }) else { return nil }
        return Target(element: read.handles[i], item: read.elements[i])
    }

    static func actions(_ el: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success, let list = names as? [String] else { return [] }
        return list
    }

    static func settable(_ el: AXUIElement, _ attribute: String) -> Bool {
        var ok: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(el, attribute as CFString, &ok) == .success && ok.boolValue
    }

    /// True if the element at the point is the link or a part of the link.
    static func hitsLink(_ app: AXUIElement, _ link: AXUIElement, at p: CGPoint) -> (Bool, String) {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(p.x), Float(p.y), &hit) == .success, var node = hit else {
            return (false, "no element")
        }
        let first = AX.role(node)
        for _ in 0..<6 {
            if CFEqual(node, link) { return (true, first) }
            guard let parent = AX.element(node, "AXParent") else { break }
            node = parent
        }
        return (false, first)
    }

    static func run(_ args: [String]) async throws -> Int32 {
        guard AX.trusted(prompt: false) else { throw ProbeError("Accessibility is off. Run: swift run earshot-probe check") }
        let file = try WebPage.loadSites()
        let bundle = file.browser
        let siteID = E2.names(args).first ?? "wikipedia"
        guard let site = file.sites.first(where: { $0.id == siteID }), let startURL = URL(string: site.url),
              let startHost = startURL.host else { throw ProbeError("no site \(siteID) in e2-sites.json") }
        var label: String?
        if let i = args.firstIndex(of: "--label"), i + 1 < args.count { label = args[i + 1] }
        let useMouse = args.contains("--mouse")
        let before = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let pointer = CGEvent(source: nil)?.location
        guard let app = WebPage.browser(bundle) else { throw ProbeError("\(bundle) does not run. Open it first.") }
        let enhancedBefore = AX.bool(app, "AXEnhancedUserInterface")
        let log = try RunLog(kind: "press", experiment: "e2")
        print("E2 press test in \(bundle). One link, several ways. No Return, no button, no risky label.")
        print("Do not touch the keyboard or the mouse. Log: \(log.url.path)\n")

        // Put things back at the end, also after an error.
        defer {
            AX.set(app, "AXEnhancedUserInterface", (enhancedBefore ?? false) ? kCFBooleanTrue : kCFBooleanFalse)
        }

        func openStart() async -> String? {
            WebPage.open(startURL, bundleID: bundle, activate: true)
            guard await WebPage.waitForPage(app, host: startHost) else { return nil }
            await sleepMs(1000)
            return WebPage.currentURL(app)
        }
        func title() -> String { AX.window(app).flatMap { AX.string($0, "AXTitle") } ?? "" }

        guard var start = await openStart() else { throw ProbeError("\(site.url) did not load in 10 s") }
        guard let w = AX.window(app), let found = WebPage.findWebArea(in: w), found.1 == "hit test",
              let area = AX.frame(found.0), let read = WebPage.read(app, headings: false), read.areaPath == "hit test"
        else { throw ProbeError("the page is not on screen. Nothing was pressed.") }
        guard let index = pick(read, area: area, start: start, label: label) else {
            throw ProbeError("no plain link to test on this page. Nothing was pressed.")
        }
        let item = read.elements[index]
        let link = read.handles[index]
        if WebRouter.isRisky(item.label) || item.kind != "link" { throw ProbeError("the link \"\(item.label)\" is not safe to press") }

        // Facts about the link and Chrome, before any press.
        let center = CGPoint(x: item.x + min(item.w, 40) / 2, y: item.y + item.h / 2)
        let hit = hitsLink(app, link, at: center)
        let facts: [String: Any] = [
            "event": "facts", "site": site.id, "label": item.label, "url": item.url ?? "", "role": item.role,
            "subrole": item.subrole, "actions": actions(link), "focus_settable": settable(link, "AXFocused"),
            "enabled": AX.bool(link, "AXEnabled") ?? true, "children": AX.elements(link, "AXChildren").map(AX.role),
            "hit_test_center": hit.0, "hit_role": hit.1, "enhanced_ui_before": enhancedBefore.map { $0 ? "true" : "false" } ?? "not set",
            "manual_accessibility": AX.bool(app, "AXManualAccessibility").map { $0 ? "true" : "false" } ?? "not readable",
        ]
        log.write(facts)
        print("Link: \"\(item.label)\" → \(item.url ?? "?")")
        print("  role \(item.role) \(item.subrole), actions \(actions(link)), focus settable \(settable(link, "AXFocused"))")
        print("  children \(AX.elements(link, "AXChildren").map(AX.role)), hit test at the link: \(hit.0 ? "the link" : "not the link (\(hit.1))")")
        print("  AXEnhancedUserInterface before: \(facts["enhanced_ui_before"]!), AXManualAccessibility: \(facts["manual_accessibility"]!)\n")

        var ways = ["press", "focus, then press", "press the text inside", "enhanced UI, then press", "open the address"]
        if useMouse { ways.append("mouse click") }
        var outcomes: [Outcome] = []
        let linkBare = E2.bare(item.url ?? "")

        for way in ways {
            // Each way starts on the start page, in the visible tab.
            if E2.bare(WebPage.currentURL(app) ?? "") != E2.bare(start) {
                guard let again = await openStart() else { print("  the start page did not come back. The test stops."); break }
                start = again
            }
            if way == "mouse click" {
                _ = await E2.bringToFront(bundle)
                await sleepMs(300)
            }
            if way == "enhanced UI, then press" {
                AX.set(app, "AXEnhancedUserInterface", kCFBooleanTrue)
                await sleepMs(500)
            }
            guard let t = find(app, item) else {
                outcomes.append(Outcome(way: way, result: "link not found on screen", changed: false, callMs: nil, changeMs: nil))
                print("  \(E2.pad(way, 26)) link not found on screen")
                continue
            }
            let startTitle = title()
            var result = ""
            let t0 = Clock.nowNs()
            switch way {
            case "press":
                result = "\(AXUIElementPerformAction(t.element, kAXPressAction as CFString).rawValue)"
            case "focus, then press":
                let focusSet = AX.set(t.element, "AXFocused", kCFBooleanTrue)
                _ = await waitUntil(timeoutMs: 300) { AX.same(AX.focused(app), t.element) }
                let focused = AX.same(AX.focused(app), t.element)
                result = "focus set \(focusSet), focused \(focused), press \(AXUIElementPerformAction(t.element, kAXPressAction as CFString).rawValue)"
            case "press the text inside":
                guard let child = AX.elements(t.element, "AXChildren").first else { result = "no child"; break }
                result = "\(AX.role(child)) press \(AXUIElementPerformAction(child, kAXPressAction as CFString).rawValue)"
            case "enhanced UI, then press":
                result = "enhanced \(AX.bool(app, "AXEnhancedUserInterface") == true), press \(AXUIElementPerformAction(t.element, kAXPressAction as CFString).rawValue)"
            case "open the address":
                guard let u = t.item.url, let url = URL(string: u) else { result = "no address"; break }
                WebPage.open(url, bundleID: bundle, activate: true)
                result = "opened as a new tab"
            case "mouse click":
                let p = CGPoint(x: t.item.x + min(t.item.w, 40) / 2, y: t.item.y + t.item.h / 2)
                let check = hitsLink(app, t.element, at: p)
                guard check.0 else { result = "not clicked: the point is not on the link (\(check.1))"; break }
                Mouse.click(p)
                result = "clicked"
            default:
                break
            }
            let callMs = Clock.ms(since: t0)
            let tc = Clock.nowNs()
            let changed = await waitUntil(timeoutMs: way == "open the address" ? 6000 : 3000, intervalMs: 50) {
                let now = E2.bare(WebPage.currentURL(app) ?? "")
                return (!now.isEmpty && now != E2.bare(start)) || title() != startTitle
            }
            let changeMs = changed ? Clock.ms(since: tc) : nil
            let now = WebPage.currentURL(app) ?? ""
            let reached = changed ? (E2.bare(now) == linkBare ? "the link page" : "other page: \(now)") : "no page change in 3 s"
            if way == "enhanced UI, then press" {
                AX.set(app, "AXEnhancedUserInterface", (enhancedBefore ?? false) ? kCFBooleanTrue : kCFBooleanFalse)
            }
            outcomes.append(Outcome(way: way, result: result, changed: changed, callMs: callMs, changeMs: changeMs))
            log.write(["event": "way", "way": way, "result": result, "changed": changed, "reached": reached,
                       "call_ms": callMs, "change_ms": changeMs ?? -1, "url_after": now])
            print("  \(E2.pad(way, 26)) \(changed ? "✓" : "✗") \(reached) · \(result) · call \(String(format: "%.1f", callMs)) ms"
                  + (changeMs.map { " · page change after \(Int($0.rounded())) ms" } ?? ""))
            if changed {
                if way == "open the address" { continue } // The next way opens the start page again.
                let back = await E2.goBack(app, to: start, bundle: bundle)
                if back == "failed" { print("  could not get back to the start page. The test stops."); break }
            }
            await sleepMs(400)
        }

        if let pointer {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: pointer, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        if let id = before { _ = await E2.bringToFront(id) }
        let works = outcomes.filter(\.changed).map(\.way)
        print("\nWays that changed the page: \(works.isEmpty ? "none" : works.joined(separator: ", ")).")
        print("Nothing was submitted. No Return was pressed. The test tabs stay open.")
        return 0
    }
}
