import AppKit
import ApplicationServices
import EarshotCore

/// The answer of the screenshot fallback (D-10).
public struct VisionTarget: Sendable, Equatable {
    /// The element to click with `Intent.click`, or nil if earshot must do nothing.
    public var elementID: String?
    /// The label of the element, for the note and the log.
    public var label: String
    /// Why: "mark 5", "box", or the reason for nothing.
    public var note: String
    /// Stage times in ms: "shot", "jev", "check".
    public var stages: [String: Double]

    public init(elementID: String?, label: String, note: String, stages: [String: Double]) {
        self.elementID = elementID; self.label = label; self.note = note; self.stages = stages
    }
}

extension EarshotActionRunner {
    /// The screenshot fallback for a click that the rules could not place (D-10, DESIGN 3.5 step 7).
    ///
    /// The caller runs it only when the owner switched on "Jev sees the screen". It does one picker call at most.
    /// Rules:
    /// - Only for a hold-key command (R-ON-5). Never on a sign-in, code or payment page. Never on a hidden tab.
    /// - The picture is the front window only, with numbers on the elements that are not risky.
    /// - A number from Jev must be one that earshot drew. A box from Jev becomes one point. The top element at the
    ///   point must belong to the front app, have a label, and not be risky, and no risky text may be under the point.
    /// - It clicks nothing itself. The caller runs `Intent.click` with the returned id and the tier `.jev`,
    ///   so the click path checks the label again (read-back) and blocks every risky label (SafetyPolicy.mayPress).
    public func visionTarget(_ command: String, mode: InputMode, picker: ScreenPicker, budgetMs: Int) async -> VisionTarget {
        var stages: [String: Double] = [:]
        func none(_ why: String) -> VisionTarget { VisionTarget(elementID: nil, label: "", note: why, stages: stages) }
        guard mode == .hold else { return none("the screenshot fallback needs the hold key") }
        guard AX.trusted() else { return none("the Accessibility permission is off") }
        guard WindowShot.allowed() else { return none("the Screen Recording permission is off") }

        var t = Clock.nowNs()
        var read = last
        if read == nil || read!.pid != AX.frontPid() || Clock.ms(since: read!.at) > options.maxSnapshotAgeMs
            || windowFrame(read!.pid) != read!.window {
            read = await freshRead(forceOCR: false)
        }
        guard let read else { return none("earshot cannot read the front window") }
        if let why = SafetyPolicy.sensitive(url: read.snapshot.url, elements: pageElements(read))
            ?? sensitiveNow(app: AX.appElement(read.pid), pid: read.pid) {
            return none("no screenshot: this looks like a sign-in, code or payment page (\(why))")
        }
        // A page that a plugin wrote holds the owner's private data. It never goes to Jev (R-MD-1, D-10).
        if SafetyPolicy.pluginPage(url: read.snapshot.url) { return none("no screenshot: a plugin page") }
        if read.web, read.areaPath != "hit test" { return none("no screenshot: the page can be a hidden tab") }
        if overlay.shown { overlay.hide() }

        guard let capture = await WindowShot.capture(pid: read.pid, window: read.window),
              // On a web page, only the page gets numbers. E3 step 2: Jev picked the address field for "the shopping bag".
              let shot = WindowShot.marked(capture.0, window: capture.1, elements: read.web ? pageElements(read) : read.snapshot.elements) else {
            return none("earshot could not take the picture of the window")
        }
        let shotWindow = capture.1
        stages["shot"] = Clock.ms(since: t)

        t = Clock.nowNs()
        let pick = await picker.pick(command, shot: shot, budgetMs: budgetMs)
        stages["jev"] = Clock.ms(since: t)

        t = Clock.nowNs()
        // The window must be the same as in the picture.
        guard AX.frontPid() == read.pid, frontmost(read.pid), windowFrame(read.pid) == read.window else {
            return none("the front window changed")
        }
        switch pick {
        case .none:
            return none("Jev found no target on the screen")
        case .mark(let n):
            let id = ActionRules.elementID(number: n)
            guard let item = read.items[id], shot.marks.contains(n) else { return none("Jev picked a number that earshot did not draw") }
            stages["check"] = Clock.ms(since: t)
            if SafetyPolicy.isRisky(item.element) { return none("blocked: risky label \"\(item.element.label)\"") }
            return VisionTarget(elementID: id, label: item.element.label, note: "mark \(n)", stages: stages)
        case let .box(top, left, bottom, right):
            guard shot.marks.count < VisionRules.boxBelowMarks else { return none("Jev found no numbered target") }
            let w = (x: shotWindow.x, y: shotWindow.y, w: shotWindow.w, h: shotWindow.h)
            guard let p = VisionRules.point(top: top, left: left, bottom: bottom, right: right, window: w) else {
                return none("Jev's box does not mark one element")
            }
            let out = adopt(CGPoint(x: p.x, y: p.y), read: read)
            stages["check"] = Clock.ms(since: t)
            switch out {
            case .failure(let why): return none(why.text)
            case .success(let (id, label)): return VisionTarget(elementID: id, label: label, note: "box", stages: stages)
            }
        }
    }

    struct Refusal: Error { let text: String }

    /// The element at a screen point, added to the last read with the next number, if earshot may click it.
    /// It goes up from the deepest element at the point to the first element with a kind and a label.
    /// Every element on that way must not be risky: a text "Send" inside a plain group blocks the point too.
    func adopt(_ p: CGPoint, read: ScreenRead) -> Result<(String, String), Refusal> {
        guard read.window.contains(p) else { return .failure(Refusal(text: "Jev's point is outside the window")) }
        guard var node = AX.hit(p), AX.pid(node) == read.pid else { return .failure(Refusal(text: "another window covers Jev's point")) }
        let everywhere = Frame(x: -1e6, y: -1e6, w: 2e6, h: 2e6)
        var found: (AXUIElement, ScreenReader.Draft)?
        for _ in 0..<8 {
            if AX.subrole(node) == "AXSecureTextField" { return .failure(Refusal(text: "blocked: a password field")) }
            let title = [AX.string(node, "AXTitle"), AX.string(node, "AXDescription"), AX.string(node, "AXValue")]
                .compactMap { $0 }.joined(separator: " ")
            if !title.isEmpty, SafetyPolicy.isRisky(title, role: AX.role(node)) {
                return .failure(Refusal(text: "blocked: risky label at Jev's point"))
            }
            if let d = ScreenReader.describe(node, viewport: everywhere), !d.label.isEmpty {
                found = (node, d)
                break
            }
            guard let parent = AX.element(node, "AXParent") else { break }
            node = parent
        }
        guard let el = found?.0, let d = found?.1 else { return .failure(Refusal(text: "no clickable element at Jev's point")) }
        if SafetyPolicy.isRisky(d.label, role: d.role) { return .failure(Refusal(text: "blocked: risky label \"\(d.label)\"")) }
        // OCR text under the point (an app with poor labels): it must not be risky either.
        for e in read.snapshot.elements where e.role == ActionRules.ocrRole {
            let f = Frame(x: e.x, y: e.y, w: e.w, h: e.h)
            if f.contains(p), SafetyPolicy.isRisky(e.label) { return .failure(Refusal(text: "blocked: risky text \"\(e.label)\" at Jev's point")) }
        }
        // The same element can already have a number.
        if let known = read.items.first(where: { $0.value.handle.map { CFEqual($0, el) } ?? false }) {
            return .success((known.key, known.value.element.label))
        }
        let id = ActionRules.elementID(number: read.snapshot.elements.count + 1)
        let e = ScreenElement(id: id, role: d.role, subrole: d.subrole, label: d.label, url: d.url, risky: false,
                              x: d.frame.x, y: d.frame.y, w: d.frame.w, h: d.frame.h)
        var snapshot = read.snapshot
        snapshot.elements.append(e)
        var items = read.items
        // On a web page, an element outside the page area is browser chrome (a tab, the address field).
        items[id] = ReadElement(element: e, kind: d.kind, handle: el, inPage: !read.web || read.viewport.contains(p))
        last = ScreenRead(snapshot: snapshot, pid: read.pid, areaPath: read.areaPath, window: read.window, viewport: read.viewport,
                          items: items, at: read.at, ms: read.ms, method: read.method + "+jev")
        return .success((id, d.label))
    }
}
