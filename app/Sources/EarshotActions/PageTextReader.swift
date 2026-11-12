import ApplicationServices
import EarshotCore
import Foundation

/// What one read of the page in front gives: the blocks, or the reason that there are none.
public struct PageTextResult: Sendable {
    public var blocks: [PageBlock] = []
    public var url: String?
    public var title: String?
    public var complete = true
    /// Why there is no text. Nil if the read worked.
    public var error: String?
    public var elements = 0
    public var ms: Double = 0

    public init(error: String? = nil) { self.error = error }
}

/// Reads the text of the web page in the front window, for the context key "pageText" (docs/PLUGINS.md 5.3).
///
/// The method is the tree walk of the W1 probes (PA phase 4): it was complete on all six probe pages in Chrome and
/// Safari, and gave no value of a one-line field.
///
/// Read only: the reader only copies values. It does not press, scroll, select, type or change the focus.
/// - It never takes the value of a one-line field, a combo box, a search field or a secure field.
/// - It gives no text on a sign-in, code or payment page (SafetyPolicy.sensitive).
/// - It reads only a web area. A native app gives "not a web page".
/// - It checks the front app, the window and the page address before and after the read.
/// It is not main-actor bound: the app runs it on a background queue, so that a command does not wait for it.
public enum PageTextReader {
    /// The zone of a landmark subrole. Other subroles give no zone.
    static let zones: [String: String] = [
        "AXLandmarkMain": "main", "AXDocumentArticle": "article", "AXLandmarkNavigation": "nav",
        "AXLandmarkBanner": "banner", "AXLandmarkContentInfo": "footer", "AXLandmarkComplementary": "aside",
        "AXLandmarkSearch": "search", "AXLandmarkForm": "form", "AXApplicationDialog": "dialog",
        "AXApplicationAlertDialog": "dialog",
    ]
    /// Fields whose value the read never takes.
    static let singleLineRoles: Set<String> = ["AXTextField", "AXComboBox", "AXSearchField", "AXSecureTextField"]
    static let fieldSubroles: Set<String> = ["AXSecureTextField", "AXSearchField"]
    /// Controls that the sign-in check needs (their labels only).
    static let controlRoles: Set<String> = ["AXButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton"]
    static var attrs: CFArray { ["AXRole", "AXSubrole", "AXValue", "AXTitle", "AXDescription", "AXChildren"] as CFArray }

    /// The front page now: the app, the window and the web area, with its address.
    struct Front {
        let pid: pid_t
        let window: AXUIElement
        let area: AXUIElement
        let url: String?
        let title: String?
    }

    static func front() -> Result<Front, PageTextFailure> {
        guard AX.trusted() else { return .failure(PageTextFailure("no Accessibility permission")) }
        guard let pid = AX.frontPid() else { return .failure(PageTextFailure("no front app")) }
        let app = AX.appElement(pid)
        guard let window = AX.window(app) else { return .failure(PageTextFailure("no front window")) }
        guard let area = ScreenReader.visibleWebArea(window) else { return .failure(PageTextFailure("not a web page")) }
        return .success(Front(pid: pid, window: window, area: area, url: ScreenReader.address(area),
                              title: AX.string(window, "AXTitle")))
    }

    struct PageTextFailure: Error {
        let reason: String
        init(_ reason: String) { self.reason = reason }
    }

    /// Reads the page in front. `expectURL` is the address of the page when the command went out: if the page in
    /// front now has another address, the read gives no text. If earshot had no address then (no web page, or a
    /// sign-in, code or payment page), the read gives no text.
    public static func read(expectURL: String?) -> PageTextResult {
        let t0 = Clock.nowNs()
        guard let expectURL, !expectURL.isEmpty else { return PageTextResult(error: "no web page at the time of the command") }
        let before: Front
        switch front() {
        case .success(let f): before = f
        case .failure(let f): return PageTextResult(error: f.reason)
        }
        if before.url != expectURL { return PageTextResult(error: "the page changed") }

        let w = Walk()
        walk(before.area, w: w, zone: nil, inMain: false, kind: "p", parentRole: "")
        var out = PageTextResult()
        out.elements = w.elements
        out.complete = !w.stopped
        out.url = before.url
        out.title = before.title
        out.ms = Clock.ms(since: t0)
        if SafetyPolicy.sensitive(url: before.url, elements: w.fields) != nil {
            return PageTextResult(error: "sign-in, code or payment page")
        }
        // The front app, the window and the address must be the same after the read.
        guard case .success(let after) = front(), after.pid == before.pid, CFEqual(after.window, before.window),
              after.url == before.url else {
            return PageTextResult(error: "the page changed")
        }
        out.blocks = w.blocks
        return out
    }

    // MARK: - The tree walk

    struct Node {
        var role = "", subrole = "", value: CFTypeRef?, title: String?, desc: String?, children: [AXUIElement] = []
    }

    static func node(_ el: AXUIElement) -> Node {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(el, attrs, [], &values) == .success,
              let array = values as? [AnyObject], array.count == 6 else {
            return Node(role: AX.role(el), subrole: AX.subrole(el), value: AX.copy(el, "AXValue"),
                        title: AX.string(el, "AXTitle"), desc: AX.string(el, "AXDescription"), children: AX.elements(el, "AXChildren"))
        }
        func ok(_ v: AnyObject) -> CFTypeRef? {
            CFGetTypeID(v) == AXValueGetTypeID() && AXValueGetType(v as! AXValue) == .axError ? nil : v
        }
        var n = Node()
        n.role = AX.text(ok(array[0])) ?? ""
        n.subrole = AX.text(ok(array[1])) ?? ""
        n.value = ok(array[2])
        n.title = AX.text(ok(array[3]))
        n.desc = AX.text(ok(array[4]))
        if let c = ok(array[5]), CFGetTypeID(c) == CFArrayGetTypeID(), let list = c as? [AnyObject] {
            n.children = list.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
        }
        return n
    }

    final class Walk {
        var blocks: [PageBlock] = []
        var fields: [ScreenElement] = []
        var elements = 0
        var chars = 0
        let t0 = Clock.nowNs()
        var stopped: Bool {
            elements >= PageText.maxElements || chars >= PageText.maxCharacters || Clock.ms(since: t0) >= PageText.maxSeconds * 1000
        }
    }

    /// One run of inline text: the parts and the count of characters in links.
    struct Run {
        var parts: [String] = []
        var linkChars = 0
        var chars = 0
        mutating func add(_ s: String, link: Bool) {
            guard !s.isEmpty else { return }
            parts.append(s)
            chars += s.count
            if link { linkChars += s.count }
        }
        var text: String {
            var out = ""
            for p in parts {
                if let last = out.last, let first = p.first, !last.isWhitespace, !first.isWhitespace,
                   !",.;:!?)".contains(first), last != "(" { out += " " }
                out += p
            }
            return out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func isField(_ n: Node) -> Bool { singleLineRoles.contains(n.role) || fieldSubroles.contains(n.subrole) }

    static func keepField(_ el: AXUIElement, _ n: Node, w: Walk) {
        let label = [AX.string(el, "AXPlaceholderValue"), n.desc, n.title].compactMap { $0 }.joined(separator: " ")
        w.fields.append(ScreenElement(id: "f\(w.fields.count)", role: n.role, subrole: n.subrole, label: label, risky: false))
    }

    /// The inline text of a subtree: static texts and the texts of links, in order. Fields are skipped.
    static func inline(_ el: AXUIElement, _ n: Node, w: Walk, run: inout Run, link: Bool) {
        w.elements += 1
        if isField(n) { keepField(el, n, w: w); return }
        if n.role == "AXStaticText" {
            let s = AX.text(n.value) ?? n.title ?? ""
            run.add(s, link: link)
            w.chars += s.count
            return
        }
        if n.role == "AXImage" { return }
        let inLink = link || n.role == "AXLink"
        for c in n.children where !w.stopped { inline(c, node(c), w: w, run: &run, link: inLink) }
    }

    /// True if a child is a small inline group (a span or a code word) and not a block.
    static func isInlineGroup(_ n: Node) -> Bool {
        guard n.role == "AXGroup", zones[n.subrole] == nil, n.children.count <= 3 else { return false }
        return n.children.allSatisfy { ["AXStaticText", "AXLink"].contains(AX.role($0)) }
    }

    static func walk(_ el: AXUIElement, _ pre: Node? = nil, w: Walk, zone: String?, inMain: Bool, kind: String, parentRole: String) {
        guard !w.stopped else { return }
        let n = pre ?? node(el)
        w.elements += 1
        var zone = zone, inMain = inMain
        if let z = zones[n.subrole] {
            zone = z
            if z == "main" || z == "article" { inMain = true }
        }
        // No value of a one-line field, a search field, a combo box or a secure field. A text area gives its lines.
        if isField(n) { keepField(el, n, w: w); return }
        if controlRoles.contains(n.role) { keepField(el, n, w: w) }
        if n.role == "AXTextArea" {
            for line in (AX.text(n.value) ?? "").components(separatedBy: .newlines) {
                let s = line.trimmingCharacters(in: .whitespaces)
                guard !s.isEmpty else { continue }
                w.blocks.append(PageBlock(t: s, k: "p", zone: zone, inMain: inMain, links: 0))
                w.chars += s.count
            }
            return
        }
        var myKind = kind
        var level: Int?
        switch n.role {
        case "AXHeading":
            myKind = "h"
            level = (n.value as? NSNumber)?.intValue
        case "AXCell": myKind = "cell"
        case "AXListItem": myKind = "li"
        case "AXGroup" where parentRole == "AXList": myKind = "li"
        case "AXGroup" where n.subrole == "AXCodeStyleGroup" || n.subrole == "AXPreformattedStyleGroup": myKind = "pre"
        case "AXGroup" where n.subrole == "AXBlockquote" || n.subrole == "AXQuote": myKind = "q"
        default: break
        }
        if myKind == "h" {
            // A heading is one block with all its text.
            var run = Run()
            for c in n.children where !w.stopped { inline(c, node(c), w: w, run: &run, link: false) }
            if !run.text.isEmpty { w.blocks.append(block(run, k: "h", level: level, zone: zone, inMain: inMain)) }
            return
        }
        var run = Run()
        func flush() {
            if !run.text.isEmpty { w.blocks.append(block(run, k: myKind, level: nil, zone: zone, inMain: inMain)) }
            run = Run()
        }
        for c in n.children {
            guard !w.stopped else { break }
            let cn = node(c)
            if cn.role == "AXStaticText" || cn.role == "AXLink" || (isInlineGroup(cn) && !run.parts.isEmpty) {
                inline(c, cn, w: w, run: &run, link: false)
            } else {
                flush()
                let childKind = ["li", "cell", "pre", "q"].contains(myKind) ? myKind : "p"
                walk(c, cn, w: w, zone: zone, inMain: inMain, kind: childKind, parentRole: n.role)
            }
        }
        flush()
    }

    static func block(_ run: Run, k: String, level: Int?, zone: String?, inMain: Bool) -> PageBlock {
        PageBlock(t: run.text, k: k, level: level, zone: zone, inMain: inMain,
                  links: run.chars == 0 ? 0 : (Double(run.linkChars) / Double(run.chars) * 100).rounded() / 100)
    }
}
