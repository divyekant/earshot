import AppKit
import ApplicationServices

// E2, question 1: read the clickable parts of a web page through Accessibility (AX).
// See docs/experiments/E2-web-and-speech.md. The reader reads only. It presses nothing.

/// One link, button or field of a web page.
struct WebElement: Codable {
    let id: String
    let role: String
    let subrole: String
    /// link, button, field, check, tab or choice.
    let kind: String
    let label: String
    let url: String?
    /// True if the link is in a heading, or holds a heading (search results).
    let inHeading: Bool
    let x: Double, y: Double, w: Double, h: Double

    var words: Int { Text.normalize(label).split(separator: " ").count }
    var isSearchField: Bool { kind == "field" && (subrole == "AXSearchField" || Text.normalize(label).contains("search")) }
}

/// The saved read of one page.
struct WebSnapshot: Codable {
    let builtAt: String
    let site: String
    let url: String
    let title: String
    let method: String
    /// The time of each read, in ms: find the page, ask for the elements, read their labels.
    let readMs: [Double]
    let walkMs: Double?
    let walkCount: Int?
    let unlabelled: Int
    let elements: [WebElement]
}

struct WebSite: Codable {
    let id: String
    let url: String
}

struct WebSiteFile: Codable {
    let browser: String
    let sites: [WebSite]
}

/// One live read: the elements, and their AX handles in the same order.
struct LiveRead {
    let elements: [WebElement]
    let handles: [AXUIElement]
    let unlabelled: Int
    let method: String
    let ms: Double
    let findMs: Double
    let url: String
    /// "hit test": the page is on screen. "search": the page can be a hidden tab, so do not act on it.
    let areaPath: String
}

/// Not bound to the main actor: AX calls work on any thread.
enum WebPage {
    static var sitesURL: URL { Paths.probeDir.appendingPathComponent("e2-sites.json") }
    static func snapshotURL(_ site: String) -> URL { Paths.logs.appendingPathComponent("e2-page-\(site).json") }

    static func loadSites() throws -> WebSiteFile {
        guard let data = try? Data(contentsOf: sitesURL) else { throw ProbeError("probe/e2-sites.json does not exist") }
        return try JSONDecoder().decode(WebSiteFile.self, from: data)
    }

    static func save(_ s: WebSnapshot) throws {
        try FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(s).write(to: snapshotURL(s.site))
    }

    static func load(_ site: String) throws -> WebSnapshot {
        guard let data = try? Data(contentsOf: snapshotURL(site)) else {
            throw ProbeError("probe/logs/e2-page-\(site).json does not exist. Run: swift run earshot-probe e2-page")
        }
        return try JSONDecoder().decode(WebSnapshot.self, from: data)
    }

    // MARK: - The browser

    /// The AX element of the browser. Chrome builds its web tree only when an assistive app asks for it.
    static func browser(_ bundleID: String) -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let el = AX.appElement(app.processIdentifier)
        AX.set(el, "AXManualAccessibility", kCFBooleanTrue)
        return el
    }

    /// Opens the address in the browser as a new tab. With `activate` false, the browser stays behind the front app.
    static func open(_ url: URL, bundleID: String, activate: Bool) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = activate
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config, completionHandler: nil)
    }

    /// The page of the visible tab. Chrome keeps the pages of other tabs in the tree too, with the same size,
    /// and it ignores a press on them (E2 live run 1). A hit test in the window finds the page that is on screen.
    /// The hit test is limited to the windows of the browser, so it works when another app is in front.
    static func visibleWebArea(_ window: AXUIElement) -> AXUIElement? {
        guard let app = AX.element(window, "AXParent"), let w = AX.frame(window) else { return nil }
        for (fx, fy) in [(0.5, 0.6), (0.3, 0.75), (0.7, 0.4)] {
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(app, Float(w.x + fx * w.w), Float(w.y + fy * w.h), &hit) == .success,
                  var node = hit else { continue }
            // Go up to the outermost web area. A frame inside the page is a web area too.
            var area: AXUIElement?
            var otherWindow = false
            for _ in 0..<80 {
                let r = AX.role(node)
                if r == "AXWebArea" { area = node }
                if r == "AXWindow" { otherWindow = !CFEqual(node, window); break }
                guard let parent = AX.element(node, "AXParent") else { break }
                node = parent
            }
            // The hit test on the app element gives the top Chrome element at the point. That can be in another
            // Chrome window on top, for example a sign-in window (E2 live run 3). Such a page is not this window's page.
            if let area, let w = AX.element(area, "AXWindow"), !CFEqual(w, window) { otherWindow = true }
            if otherWindow { continue }
            if let area, let f = AX.frame(area), f.w > 50, f.h > 50 { return area }
        }
        return nil
    }

    /// The page of the visible tab: the hit test first, else the largest web area of the window.
    static func webArea(in window: AXUIElement) -> AXUIElement? { findWebArea(in: window)?.0 }

    /// The page and the way the probe found it: "hit test" (on screen) or "search" (can be a hidden tab).
    /// The search does not go into a web area.
    static func findWebArea(in window: AXUIElement, maxNodes: Int = 3000) -> (AXUIElement, String)? {
        if let visible = visibleWebArea(window) { return (visible, "hit test") }
        var queue: [AXUIElement] = [window]
        var index = 0
        var best: (AXUIElement, Double)?
        while index < queue.count, index < maxNodes {
            let el = queue[index]
            index += 1
            if AX.role(el) == "AXWebArea" {
                if let f = AX.frame(el), f.w > 50, f.h > 50, best == nil || f.w * f.h > best!.1 { best = (el, f.w * f.h) }
                continue
            }
            queue.append(contentsOf: AX.elements(el, "AXChildren"))
        }
        return best.map { ($0.0, "search") }
    }

    static func address(_ el: AXUIElement) -> String? {
        guard let v = AX.copy(el, "AXURL") else { return nil }
        if let u = v as? URL { return u.absoluteString }
        return v as? String
    }

    static func currentURL(_ app: AXUIElement) -> String? {
        guard let w = AX.window(app), let area = webArea(in: w) else { return nil }
        return address(area)
    }

    /// The Back button in the browser toolbar. The search skips the page.
    static func backButton(in window: AXUIElement, maxNodes: Int = 2500) -> AXUIElement? {
        var queue: [AXUIElement] = [window]
        var index = 0
        while index < queue.count, index < maxNodes {
            let el = queue[index]
            index += 1
            let r = AX.role(el)
            if r == "AXWebArea" { continue }
            if r == "AXButton" {
                let name = Text.normalize((AX.string(el, "AXTitle") ?? "") + " " + (AX.string(el, "AXDescription") ?? ""))
                if name == "back" { return el }
            }
            queue.append(contentsOf: AX.elements(el, "AXChildren"))
        }
        return nil
    }

    // MARK: - Pages that earshot must not act on

    /// True if the address is on the host or on a part of it ("en.wikipedia.org" for "wikipedia.org").
    static func onHost(_ url: String, _ host: String) -> Bool {
        let want = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard var h = URL(string: url)?.host else { return false }
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
        return h == want || h.hasSuffix("." + want)
    }

    /// Words in the path of an address that mark a sign-in, code check or payment page.
    static let sensitivePathWords = ["signin", "sign-in", "sign_in", "login", "log-in", "logon", "password", "twofactor",
                                     "two-factor", "2fa", "mfa", "otp", "verify", "checkout", "payment", "billing"]
    /// Words in the label of a field or a button that mark such a page. Links are not checked:
    /// a story title on Hacker News can have the word "password".
    static let sensitiveLabelWords = ["password", "verification code", "two-step", "two-factor", "one-time code",
                                      "security code", "card number", "cvv", "cvc"]

    /// The reason, if the page looks like a sign-in, code check or payment page. Earshot does not act on such a page.
    static func sensitive(url: String, elements: [WebElement]) -> String? {
        let path = (URL(string: url)?.path ?? url).lowercased()
        if let w = sensitivePathWords.first(where: { path.contains($0) }) { return "the address has \"\(w)\"" }
        if elements.contains(where: { $0.subrole == "AXSecureTextField" }) { return "a password field" }
        for e in elements where e.kind != "link" {
            let l = e.label.lowercased()
            if sensitiveLabelWords.contains(where: { l.contains($0) }) { return "the label \"\(e.label)\"" }
        }
        return nil
    }

    /// Why earshot must not act on this page, or nil. The page must be on the expected host, if one is given.
    static func refuse(_ read: LiveRead, host: String?) -> String? {
        if let host, !onHost(read.url, host) {
            return "the page on screen is \(URL(string: read.url)?.host ?? "unknown"), not \(host)"
        }
        if let why = sensitive(url: read.url, elements: read.elements) {
            return "this looks like a sign-in, code or payment page (\(why))"
        }
        return nil
    }

    // MARK: - Press

    /// The actions that the element offers.
    static func actions(_ el: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success, let list = names as? [String] else { return [] }
        return list
    }

    /// True if `node` is `target`, or the same link: same role, same address and same frame.
    static func same(_ node: AXUIElement, _ target: AXUIElement) -> Bool {
        if CFEqual(node, target) { return true }
        let r = AX.role(node)
        guard r == AX.role(target), r == "AXLink", let a = address(node), a == address(target),
              let f = AX.frame(node), let g = AX.frame(target) else { return false }
        return abs(f.x - g.x) < 1 && abs(f.y - g.y) < 1 && abs(f.w - g.w) < 1 && abs(f.h - g.h) < 1
    }

    /// A point where the top element on screen, over all apps, is the target or a part of it.
    /// The hit test gives the deepest element (for a link, often its text or a group), so it goes up the parents.
    static func safePoint(_ target: AXUIElement, _ f: Frame) -> CGPoint? {
        let system = AXUIElementCreateSystemWide()
        let candidates = [
            CGPoint(x: f.x + min(f.w, 40) / 2, y: f.y + min(f.h, 24) / 2),
            CGPoint(x: f.midX, y: f.midY),
            CGPoint(x: f.x + f.w - min(f.w, 40) / 2, y: f.y + f.h - min(f.h, 24) / 2),
        ]
        for p in candidates {
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &hit) == .success, var node = hit else { continue }
            for _ in 0..<8 {
                if same(node, target) { return p }
                guard let parent = AX.element(node, "AXParent") else { break }
                node = parent
            }
        }
        return nil
    }

    /// Presses a web element. Chrome links do not offer AXPress: the call returns success and does nothing
    /// (E2 press test). So: AXPress if the element offers it. Else a mouse click at a safe point, with the
    /// browser in front, and then the pointer goes back. The caller checks the label for risky words first.
    static func press(_ el: AXUIElement, frame f: Frame, browserPid: pid_t) -> (way: String, done: Bool) {
        if actions(el).contains(kAXPressAction as String) {
            return ("AXPress", AXUIElementPerformAction(el, kAXPressAction as CFString) == .success)
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == browserPid else { return ("browser not in front", false) }
        guard let p = safePoint(el, f) else { return ("no point on screen is this element", false) }
        let back = CGEvent(source: nil)?.location
        Mouse.click(p)
        if let back {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: back, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        return ("click", true)
    }

    // MARK: - Elements

    static let buttonRoles: Set<String> = ["AXButton", "AXMenuButton", "AXPopUpButton", "AXDisclosureTriangle"]
    static let fieldRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    static func kind(role: String, subrole: String) -> String? {
        if role == "AXLink" { return "link" }
        if buttonRoles.contains(role) { return "button" }
        if fieldRoles.contains(role) { return "field" }
        if role == "AXCheckBox" || role == "AXSwitch" { return "check" }
        if role == "AXRadioButton" { return subrole == "AXTabButton" ? "tab" : "choice" }
        if role == "AXTab" { return "tab" }
        if role == "AXMenuItem" { return "choice" }
        return nil
    }

    /// One call for many elements: VoiceOver asks the page the same way.
    static func predicate(_ root: AXUIElement, key: String, limit: Int = 800) -> [AXUIElement]? {
        let params: [String: Any] = [
            "AXSearchKey": key,
            "AXResultsLimit": limit,
            "AXDirection": "AXDirectionNext",
            "AXImmediateDescendantsOnly": false,
            "AXVisibleOnly": true,
        ]
        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(root, "AXUIElementsForSearchPredicate" as CFString,
                                                               params as CFDictionary, &value)
        guard error == .success, let v = value, CFGetTypeID(v) == CFArrayGetTypeID(), let array = v as? [AnyObject] else {
            return nil
        }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    static let searchKeys = ["AXLinkSearchKey", "AXControlSearchKey"]

    /// The slow way: a walk of the page tree. It skips parts outside the window.
    static func walk(_ area: AXUIElement, viewport vp: Frame, maxNodes: Int = 8000, budgetMs: Double = 1500) -> ([AXUIElement], Int) {
        var queue: [AXUIElement] = [area]
        var index = 0
        var out: [AXUIElement] = []
        let t0 = Clock.nowNs()
        while index < queue.count, index < maxNodes, Clock.ms(since: t0) < budgetMs {
            let el = queue[index]
            index += 1
            let r = AX.role(el)
            if kind(role: r, subrole: r == "AXRadioButton" ? AX.subrole(el) : "") != nil {
                out.append(el)
                continue
            }
            if let f = AX.frame(el), f.w > 0, f.h > 0, f.y > vp.y + vp.h || f.y + f.h < vp.y { continue }
            queue.append(contentsOf: AX.elements(el, "AXChildren"))
        }
        return (out, index)
    }

    /// Reads many attributes in one call. Missing attributes are left out.
    static func multi(_ el: AXUIElement, _ names: [String]) -> [String: CFTypeRef] {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(el, names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
              let array = values as? [AnyObject] else { return [:] }
        var out: [String: CFTypeRef] = [:]
        for (i, v) in array.enumerated() where i < names.count {
            if CFGetTypeID(v) == AXValueGetTypeID(), AXValueGetType(v as! AXValue) == .axError { continue }
            out[names[i]] = v
        }
        return out
    }

    static func text(_ v: CFTypeRef?) -> String? {
        guard let v else { return nil }
        if let s = v as? String { return s }
        if let a = v as? NSAttributedString { return a.string }
        return nil
    }

    /// The text inside an element, for a link or a button that has no title.
    static func innerText(_ el: AXUIElement, depth: Int = 0) -> String {
        guard depth < 3 else { return "" }
        var parts: [String] = []
        for child in AX.elements(el, "AXChildren") {
            let r = AX.role(child)
            if r == "AXStaticText" {
                if let s = AX.value(child), !s.isEmpty { parts.append(s) }
            } else if r != "AXImage" {
                let s = innerText(child, depth: depth + 1)
                if !s.isEmpty { parts.append(s) }
            }
            if parts.joined(separator: " ").count > 100 { break }
        }
        return parts.joined(separator: " ")
    }

    /// Links that the browser adds to the page for screen readers. They are not part of the page.
    static let browserHints = ["To get missing image descriptions"]

    static let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#

    /// Removes invisible characters and e-mail addresses, and cuts long labels.
    static func clean(_ s: String) -> String {
        let squashed = Text.squash(s).replacingOccurrences(of: emailPattern, with: "[email]", options: .regularExpression)
        return squashed.count > 100 ? String(squashed.prefix(100)) : squashed
    }

    /// True if the link is in a heading (two levels up at most) or holds a heading.
    static func inHeading(_ el: AXUIElement) -> Bool {
        var node: AXUIElement? = AX.element(el, "AXParent")
        for _ in 0..<2 {
            guard let n = node else { break }
            if AX.role(n) == "AXHeading" { return true }
            node = AX.element(n, "AXParent")
        }
        for child in AX.elements(el, "AXChildren") {
            if AX.role(child) == "AXHeading" { return true }
            if AX.elements(child, "AXChildren").contains(where: { AX.role($0) == "AXHeading" }) { return true }
        }
        return false
    }

    static let attributes = ["AXRole", "AXSubrole", "AXTitle", "AXDescription", "AXValue", "AXPlaceholderValue",
                             "AXPosition", "AXSize", "AXURL"]

    struct Draft {
        let role: String, subrole: String, kind: String, label: String, url: String?
        let frame: Frame
    }

    static func describe(_ el: AXUIElement, viewport vp: Frame) -> Draft? {
        let a = multi(el, attributes)
        let role = text(a["AXRole"]) ?? ""
        let subrole = text(a["AXSubrole"]) ?? ""
        guard let kind = kind(role: role, subrole: subrole) else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard let p = a["AXPosition"], let s = a["AXSize"], CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID()
        else { return nil }
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        let f = Frame(x: point.x, y: point.y, w: size.width, h: size.height)
        // Visible: at least 2 points wide and high, and inside the page area of the window.
        guard f.w >= 2, f.h >= 2, f.x < vp.x + vp.w, f.x + f.w > vp.x, f.y < vp.y + vp.h, f.y + f.h > vp.y else { return nil }
        var label = ""
        if kind == "field" {
            label = [text(a["AXPlaceholderValue"]), text(a["AXDescription"]), text(a["AXTitle"])]
                .compactMap { $0 }.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        } else {
            label = [text(a["AXTitle"]), text(a["AXDescription"])]
                .compactMap { $0 }.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
            if label.isEmpty { label = innerText(el) }
            // A link can give its address as its value, so only a button uses the value.
            if label.isEmpty, kind == "button" { label = text(a["AXValue"]) ?? "" }
        }
        var url: String?
        if let u = a["AXURL"] { url = (u as? URL)?.absoluteString ?? text(u) }
        return Draft(role: role, subrole: subrole, kind: kind, label: clean(label), url: url, frame: f)
    }

    /// Reads the visible elements of the front tab. `walkOnly` uses the tree walk in place of the one-call search.
    /// `headings` finds the links in headings. It costs more AX calls, and only an ordinal command needs it.
    static func read(_ app: AXUIElement, walkOnly: Bool = false, headings: Bool = true) -> LiveRead? {
        let t0 = Clock.nowNs()
        guard let window = AX.window(app), let found = findWebArea(in: window), let vp = AX.frame(found.0) else { return nil }
        let area = found.0
        let areaPath = found.1
        let findMs = Clock.ms(since: t0)
        var method = "predicate"
        var raw: [AXUIElement] = []
        if !walkOnly {
            for key in searchKeys { raw += predicate(area, key: key) ?? [] }
        }
        if raw.isEmpty {
            method = "walk"
            raw = walk(area, viewport: vp).0
        }
        // The link search and the control search can give the same element.
        var buckets: [CFHashCode: [AXUIElement]] = [:]
        var unique: [AXUIElement] = []
        for el in raw {
            let h = CFHash(el)
            if buckets[h, default: []].contains(where: { CFEqual($0, el) }) { continue }
            buckets[h, default: []].append(el)
            unique.append(el)
        }
        var items: [(Draft, AXUIElement)] = []
        var unlabelled = 0
        for el in unique {
            guard let d = describe(el, viewport: vp) else { continue }
            if d.label.isEmpty && d.kind != "field" {
                unlabelled += 1
                continue
            }
            if browserHints.contains(where: { d.label.hasPrefix($0) }) { continue }
            items.append((d, el))
        }
        // Reading order: rows of 8 points from the top, then left to right.
        items.sort { a, b in
            let ra = Int((a.0.frame.y / 8).rounded(.down)), rb = Int((b.0.frame.y / 8).rounded(.down))
            return ra != rb ? ra < rb : a.0.frame.x < b.0.frame.x
        }
        var elements: [WebElement] = []
        for (i, item) in items.enumerated() {
            let d = item.0
            elements.append(WebElement(id: "e\(i + 1)", role: d.role, subrole: d.subrole, kind: d.kind, label: d.label,
                                       url: d.url, inHeading: headings && d.kind == "link" ? inHeading(item.1) : false,
                                       x: d.frame.x, y: d.frame.y, w: d.frame.w, h: d.frame.h))
        }
        return LiveRead(elements: elements, handles: items.map(\.1), unlabelled: unlabelled, method: method,
                        ms: Clock.ms(since: t0), findMs: findMs, url: address(area) ?? "", areaPath: areaPath)
    }

    /// Waits until the tab shows the page of `host` and the number of links stops changing.
    static func waitForPage(_ app: AXUIElement, host: String, timeoutMs: Int = 10000) async -> Bool {
        let wanted = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        var last = -1
        var stable = 0
        let t0 = Clock.nowNs()
        while Clock.ms(since: t0) < Double(timeoutMs) {
            if let w = AX.window(app), let area = webArea(in: w), let u = address(area),
               let h = URL(string: u)?.host, h.hasSuffix(wanted) {
                let loaded = AX.bool(area, "AXLoaded") ?? true
                let n = (predicate(area, key: "AXLinkSearchKey") ?? []).count
                if loaded, n > 0, n == last { stable += 1 } else { stable = 0 }
                if stable >= 2 { return true }
                last = n
            }
            await sleepMs(300)
        }
        return false
    }
}
