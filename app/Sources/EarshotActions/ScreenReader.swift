import AppKit
import ApplicationServices
import EarshotCore

// Reads the clickable and typable elements of the front window, for voice clicks (R-CL-1, R-CL-2, R-CL-3).
// Ported from probe/Sources/EarshotProbe/WebPage.swift (E2). It reads only. It presses nothing.

/// One element of a screen read, with its AX handle. An OCR element has no handle.
struct ReadElement {
    var element: ScreenElement
    let kind: String
    let handle: AXUIElement?
    /// False for a control of the window outside the web page, for example a browser tab or the address field.
    var inPage: Bool = true
}

/// One screen read. earshot keeps the last one, so that "click e3" can find its element.
struct ScreenRead {
    let snapshot: ScreenSnapshot
    let pid: pid_t
    /// "hit test": the page is on screen. "search": the page can be a hidden tab, so earshot does not click on it.
    /// "window": a window with no web page.
    let areaPath: String
    let window: Frame
    let viewport: Frame
    let items: [String: ReadElement]
    let at: UInt64
    let ms: Double
    let method: String

    var web: Bool { areaPath != "window" }

    /// A page element scrolls inside the page area. A window control or a native element uses the window.
    func inPageViewport(_ item: ReadElement) -> Bool { web && item.inPage }
}

enum ScreenReader {
    // MARK: - The web page

    /// The page of the visible tab. Chrome keeps the pages of other tabs in the tree too, with the same size,
    /// and it ignores a press on them (E2 live run 1). A hit test in the window finds the page that is on screen.
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
            // The hit test can reach another window of the same app on top, for example a sign-in window (E2 live run 3).
            if let area, let aw = AX.element(area, "AXWindow"), !CFEqual(aw, window) { otherWindow = true }
            if otherWindow { continue }
            if let area, let f = AX.frame(area), f.w > 50, f.h > 50 { return area }
        }
        return nil
    }

    /// The page and how earshot found it: "hit test" (on screen) or "search" (can be a hidden tab).
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

    /// The Back button of a browser toolbar. The search skips the page.
    static func backButton(in window: AXUIElement, maxNodes: Int = 2500) -> AXUIElement? {
        var queue: [AXUIElement] = [window]
        var index = 0
        while index < queue.count, index < maxNodes {
            let el = queue[index]
            index += 1
            let r = AX.role(el)
            if r == "AXWebArea" { continue }
            if r == "AXButton" {
                let name = ActionText.normalize((AX.string(el, "AXTitle") ?? "") + " " + (AX.string(el, "AXDescription") ?? ""))
                if name == "back" { return el }
            }
            queue.append(contentsOf: AX.elements(el, "AXChildren"))
        }
        return nil
    }

    // MARK: - Elements

    /// One call for many elements: VoiceOver asks a web page the same way (12 ms in E2).
    static func predicate(_ root: AXUIElement, key: String, limit: Int) -> [AXUIElement]? {
        let params: [String: Any] = [
            "AXSearchKey": key, "AXResultsLimit": limit, "AXDirection": "AXDirectionNext",
            "AXImmediateDescendantsOnly": false, "AXVisibleOnly": true,
        ]
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(root, "AXUIElementsForSearchPredicate" as CFString,
                                                         params as CFDictionary, &value) == .success,
              let v = value, CFGetTypeID(v) == CFArrayGetTypeID(), let array = v as? [AnyObject] else { return nil }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    /// The slow way: a walk of the tree. It skips parts outside the viewport, and the menu bar.
    /// A row is kept, and the walk also goes into it, because a row can hold buttons.
    static func walk(_ root: AXUIElement, viewport vp: Frame, maxNodes: Int = 5000, budgetMs: Double = 300) -> [AXUIElement] {
        var queue: [AXUIElement] = [root]
        var index = 0
        var out: [AXUIElement] = []
        let t0 = Clock.nowNs()
        while index < queue.count, index < maxNodes, Clock.ms(since: t0) < budgetMs {
            let el = queue[index]
            index += 1
            let r = AX.role(el)
            if r == "AXMenuBar" || r == "AXScrollBar" || r == "AXImage" { continue }
            if let kind = ActionRules.kind(role: r, subrole: r == "AXRadioButton" ? AX.subrole(el) : "") {
                out.append(el)
                if kind != "row" { continue }
            }
            if let f = AX.frame(el), f.w > 0, f.h > 0, !f.overlaps(vp) { continue }
            queue.append(contentsOf: AX.elements(el, "AXChildren"))
        }
        return out
    }

    /// The window's own controls outside the web page: tab buttons, toolbar buttons and the address field.
    /// The walk does not go into a web area. It is small: the page is most of the tree.
    static func windowControls(_ window: AXUIElement, maxNodes: Int = 1500, budgetMs: Double = 25) -> [AXUIElement] {
        controlWalk(window, maxNodes: maxNodes, budgetMs: budgetMs, role: { AX.role($0) }, subrole: { AX.subrole($0) },
                    children: { AX.elements($0, "AXChildren") })
    }

    /// The walk of `windowControls` over any tree, so that tests can give a fake tree.
    static func controlWalk<T>(_ root: T, maxNodes: Int = 1500, budgetMs: Double = 25, role: (T) -> String,
                               subrole: (T) -> String, children: (T) -> [T]) -> [T] {
        var queue: [T] = [root]
        var index = 0
        var out: [T] = []
        let t0 = Clock.nowNs()
        while index < queue.count, index < maxNodes, Clock.ms(since: t0) < budgetMs {
            let el = queue[index]
            index += 1
            let r = role(el)
            if ActionRules.skipForControls.contains(r) { continue }
            if ActionRules.kind(role: r, subrole: r == "AXRadioButton" ? subrole(el) : "") != nil {
                out.append(el)
                continue
            }
            queue.append(contentsOf: children(el))
        }
        return out
    }

    /// The text inside an element, for a link, a button or a row that has no title.
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

    /// True if the link is in a heading (two levels up at most) or holds a heading: a search result (E2).
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
                             "AXPosition", "AXSize", "AXURL", "AXHelp"]

    struct Draft: Equatable {
        let role: String, subrole: String, kind: String, label: String, url: String?
        let frame: Frame
    }

    /// The role, kind, label and frame of one element, or nil if it is not visible in the viewport.
    static func describe(_ el: AXUIElement, viewport vp: Frame) -> Draft? {
        let a = AX.multi(el, attributes)
        let role = AX.text(a["AXRole"]) ?? ""
        let subrole = AX.text(a["AXSubrole"]) ?? ""
        guard let kind = ActionRules.kind(role: role, subrole: subrole),
              let p = a["AXPosition"], let s = a["AXSize"], let f = AX.frame(position: p, size: s),
              ActionRules.visible(f, in: vp) else { return nil }
        var label = ""
        if kind == "field" {
            label = [AX.text(a["AXPlaceholderValue"]), AX.text(a["AXDescription"]), AX.text(a["AXTitle"])]
                .compactMap { $0 }.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        } else {
            label = [AX.text(a["AXTitle"]), AX.text(a["AXDescription"])]
                .compactMap { $0 }.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
            if label.isEmpty { label = innerText(el) }
            // An icon-only link or button can have its name only in its help text (a collapsed side bar).
            if label.isEmpty { label = AX.text(a["AXHelp"])?.trimmingCharacters(in: .whitespaces) ?? "" }
            // A link can give its address as its value, so only a button uses the value.
            if label.isEmpty, kind == "button" { label = AX.text(a["AXValue"]) ?? "" }
        }
        var url: String?
        if let u = a["AXURL"] { url = (u as? URL)?.absoluteString ?? AX.text(u) }
        return Draft(role: role, subrole: subrole, kind: kind, label: ActionText.cleanLabel(label), url: url, frame: f)
    }

    /// Reads the visible elements of the front window of the app with this pid.
    static func read(pid: pid_t, maxElements: Int) -> ScreenRead? {
        let t0 = Clock.nowNs()
        let app = AX.appElement(pid)
        // Chromium and Electron build their tree only when an assistive app asks. Other apps ignore the attribute.
        AX.set(app, "AXManualAccessibility", kCFBooleanTrue)
        guard let window = AX.window(app), let wf = AX.frame(window) else { return nil }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        let title = AX.string(window, "AXTitle") ?? ""

        var root = window
        var areaPath = "window"
        var url: String?
        if let found = findWebArea(in: window) {
            root = found.0
            areaPath = found.1
            url = address(found.0)
        }
        let vp = (areaPath == "window" ? wf : AX.frame(root)) ?? wf

        var method = "predicate"
        var raw: [AXUIElement] = []
        if areaPath != "window" {
            for key in ["AXLinkSearchKey", "AXControlSearchKey"] { raw += predicate(root, key: key, limit: maxElements * 2) ?? [] }
        }
        if raw.isEmpty {
            method = "walk"
            raw = walk(root, viewport: vp)
        }
        // The link search and the control search can give the same element.
        var buckets: [CFHashCode: [AXUIElement]] = [:]
        var drafts: [(Draft, AXUIElement)] = []
        for el in raw {
            let h = CFHash(el)
            if buckets[h, default: []].contains(where: { CFEqual($0, el) }) { continue }
            buckets[h, default: []].append(el)
            guard let d = describe(el, viewport: vp) else { continue }
            if d.label.isEmpty && d.kind != "field" { continue }
            if ActionRules.browserHints.contains(where: { d.label.hasPrefix($0) }) { continue }
            drafts.append((d, el))
        }
        drafts.sort { ActionRules.readingOrder($0.0.frame, $1.0.frame) }
        if drafts.count > maxElements { drafts = Array(drafts.prefix(maxElements)) }

        // With a web page, also read the window's own controls (tabs, toolbar, address field). They come after
        // the page elements, so that the numbers of the page stay the same.
        var controls: [(Draft, AXUIElement)] = []
        if areaPath != "window" {
            for el in windowControls(window) {
                guard let d = describe(el, viewport: wf), !(d.label.isEmpty && d.kind != "field") else { continue }
                controls.append((d, el))
            }
            controls.sort { ActionRules.readingOrder($0.0.frame, $1.0.frame) }
        }

        var elements: [ScreenElement] = []
        var items: [String: ReadElement] = [:]
        for (i, (d, el)) in (drafts + controls).enumerated() {
            let id = ActionRules.elementID(number: i + 1)
            let page = i < drafts.count
            let e = ScreenElement(id: id, role: d.role, subrole: d.subrole, label: d.label, url: d.url,
                                  inHeading: page && d.kind == "link" && areaPath != "window" ? inHeading(el) : false,
                                  risky: SafetyPolicy.isRisky(d.label, role: d.role),
                                  x: d.frame.x, y: d.frame.y, w: d.frame.w, h: d.frame.h)
            elements.append(e)
            items[id] = ReadElement(element: e, kind: d.kind, handle: el, inPage: page || areaPath == "window")
        }
        let snapshot = ScreenSnapshot(bundleID: bundleID, windowTitle: title, url: url, elements: elements)
        return ScreenRead(snapshot: snapshot, pid: pid, areaPath: areaPath, window: wf, viewport: vp, items: items,
                          at: Clock.nowNs(), ms: Clock.ms(since: t0), method: method)
    }

    /// Adds the texts that OCR found to a read, with the next numbers.
    static func adding(ocr texts: [(String, Frame)], to read: ScreenRead) -> ScreenRead {
        var elements = read.snapshot.elements
        var items = read.items
        for (text, f) in texts {
            let label = ActionText.cleanLabel(text)
            guard !label.isEmpty, ActionRules.visible(f, in: read.viewport) else { continue }
            let id = ActionRules.elementID(number: elements.count + 1)
            let e = ScreenElement(id: id, role: ActionRules.ocrRole, label: label, risky: SafetyPolicy.isRisky(label, role: ActionRules.ocrRole),
                                  x: f.x, y: f.y, w: f.w, h: f.h)
            elements.append(e)
            items[id] = ReadElement(element: e, kind: "text", handle: nil)
        }
        var snapshot = read.snapshot
        snapshot.elements = elements
        return ScreenRead(snapshot: snapshot, pid: read.pid, areaPath: read.areaPath, window: read.window, viewport: read.viewport,
                          items: items, at: read.at, ms: read.ms, method: read.method + "+ocr")
    }
}
