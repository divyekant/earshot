import AppKit
import ApplicationServices
import EarshotCore
@testable import EarshotActions

/// The two read methods of the PA phase 4 probes (W1, spec section 6). Only the bench uses this file.
/// The plugin thread makes the real page reader in earshot from the numbers of the bench.
///
/// Read only: this file has only calls that copy a value. It does not press, scroll, select, type or change
/// the focus. It reads no value of a single-line field, a search field or a combo box, and no secure field.
struct ProbeBlock: Codable {
    var t: String
    var k: String = "p"
    var level: Int?
    var zone: String?
    var inMain: Bool?
    var links: Double?
}

struct ProbeRead {
    var method: String
    var blocks: [ProbeBlock] = []
    var ms: Double = 0
    var elements = 0
    /// Nil, or why the read gives no text (a sign-in, code or payment page).
    var sensitive: String?
    var complete = true
    /// Count of each "role/subrole" pair that the tree walk met. Only for the probe report.
    var roles: [String: Int] = [:]
    var landmarks = 0
    var headings = 0
    var note = ""

    var text: String { blocks.map(\.t).joined(separator: "\n") }
}

enum PageProbeReader {
    static let maxElements = 20_000
    static let maxMs = 5_000.0
    static let maxChars = 200_000

    /// The zone of a landmark subrole. "AXLandmarkRegion" and others give no zone.
    static let zones: [String: String] = [
        "AXLandmarkMain": "main", "AXDocumentArticle": "article", "AXLandmarkNavigation": "nav",
        "AXLandmarkBanner": "banner", "AXLandmarkContentInfo": "footer", "AXLandmarkComplementary": "aside",
        "AXLandmarkSearch": "search", "AXLandmarkForm": "form", "AXApplicationDialog": "dialog",
        "AXApplicationAlertDialog": "dialog",
    ]
    /// Fields whose value the read never takes.
    static let singleLineRoles: Set<String> = ["AXTextField", "AXComboBox", "AXSearchField", "AXSecureTextField"]
    static let fieldSubroles: Set<String> = ["AXSecureTextField", "AXSearchField"]
    static let attrs = ["AXRole", "AXSubrole", "AXValue", "AXTitle", "AXDescription", "AXChildren"] as CFArray

    // MARK: - Method A: the tree walk

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
        func ok(_ v: AnyObject) -> CFTypeRef? { CFGetTypeID(v) == AXValueGetTypeID() && AXValueGetType(v as! AXValue) == .axError ? nil : v }
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
        var read = ProbeRead(method: "A")
        var fields: [ScreenElement] = []
        let t0 = Clock.nowNs()
        var chars = 0
        var stopped: Bool { read.elements >= PageProbeReader.maxElements || Clock.ms(since: t0) >= PageProbeReader.maxMs || chars >= PageProbeReader.maxChars }
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

    static func readA(area: AXUIElement, url: String?) -> ProbeRead {
        let w = Walk()
        walk(area, w: w, zone: nil, inMain: false, kind: "p", parentRole: "")
        w.read.ms = Clock.ms(since: w.t0)
        w.read.complete = !w.stopped
        if let s = SafetyPolicy.sensitive(url: url, elements: w.fields) {
            w.read.sensitive = s
            w.read.blocks = []
        }
        return w.read
    }

    /// The inline text of a subtree: static texts and the texts of links, in order. Fields are skipped.
    static func inline(_ el: AXUIElement, _ n: Node, w: Walk, run: inout Run, link: Bool) {
        w.read.elements += 1
        w.read.roles["\(n.role)/\(n.subrole)", default: 0] += 1
        if singleLineRoles.contains(n.role) || fieldSubroles.contains(n.subrole) {
            w.fields.append(ScreenElement(id: "f\(w.fields.count)", role: n.role, subrole: n.subrole, label: label(el, n), risky: false))
            return
        }
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

    static func label(_ el: AXUIElement, _ n: Node) -> String {
        [AX.string(el, "AXPlaceholderValue"), n.desc, n.title].compactMap { $0 }.joined(separator: " ")
    }

    /// True if a child is a small inline group (a span or a code word) and not a block.
    static func isInlineGroup(_ n: Node) -> Bool {
        guard n.role == "AXGroup", zones[n.subrole] == nil, n.children.count <= 3 else { return false }
        return n.children.allSatisfy { ["AXStaticText", "AXLink"].contains(AX.role($0)) }
    }

    static func walk(_ el: AXUIElement, _ pre: Node? = nil, w: Walk, zone: String?, inMain: Bool, kind: String, parentRole: String) {
        guard !w.stopped else { return }
        let n = pre ?? node(el)
        w.read.elements += 1
        w.read.roles["\(n.role)/\(n.subrole)", default: 0] += 1
        var zone = zone, inMain = inMain
        if let z = zones[n.subrole] {
            zone = z
            if z == "main" || z == "article" { inMain = true }
            w.read.landmarks += 1
        }
        // Fields: no value of a one-line field, search field, combo box or secure field. A text area gives its lines.
        if singleLineRoles.contains(n.role) || fieldSubroles.contains(n.subrole) {
            w.fields.append(ScreenElement(id: "f\(w.fields.count)", role: n.role, subrole: n.subrole, label: label(el, n), risky: false))
            return
        }
        if n.role == "AXButton" || n.role == "AXPopUpButton" || n.role == "AXCheckBox" || n.role == "AXRadioButton" {
            w.fields.append(ScreenElement(id: "f\(w.fields.count)", role: n.role, subrole: n.subrole, label: label(el, n), risky: false))
        }
        if n.role == "AXTextArea" {
            let v = AX.text(n.value) ?? ""
            for line in v.components(separatedBy: .newlines) {
                let s = line.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { w.read.blocks.append(ProbeBlock(t: s, k: "p", zone: zone, inMain: inMain, links: 0)); w.chars += s.count }
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
        case "AXGroup" where n.subrole == "AXCodeStyleGroup": myKind = "pre"
        case "AXGroup" where n.subrole == "AXBlockquote" || n.subrole == "AXQuote": myKind = "q"
        default: break
        }
        if myKind == "h" {
            // A heading is one block with all its text.
            var run = Run()
            for c in n.children where !w.stopped { inline(c, node(c), w: w, run: &run, link: false) }
            if !run.text.isEmpty { w.read.blocks.append(block(run, k: "h", level: level, zone: zone, inMain: inMain)) }
            w.read.headings += 1
            return
        }
        var run = Run()
        func flush() {
            if !run.text.isEmpty { w.read.blocks.append(block(run, k: myKind, level: nil, zone: zone, inMain: inMain)) }
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

    static func block(_ run: Run, k: String, level: Int?, zone: String?, inMain: Bool) -> ProbeBlock {
        ProbeBlock(t: run.text, k: k, level: level, zone: zone, inMain: inMain,
                   links: run.chars == 0 ? 0 : (Double(run.linkChars) / Double(run.chars) * 100).rounded() / 100)
    }

    // MARK: - Method B: the text range

    static func search(_ root: AXUIElement, key: String, limit: Int = 200) -> [AXUIElement] {
        let params: [String: Any] = [
            "AXSearchKey": key, "AXResultsLimit": limit, "AXDirection": "AXDirectionNext",
            "AXImmediateDescendantsOnly": false, "AXVisibleOnly": false,
        ]
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(root, "AXUIElementsForSearchPredicate" as CFString,
                                                         params as CFDictionary, &value) == .success,
              let v = value, CFGetTypeID(v) == CFArrayGetTypeID(), let array = v as? [AnyObject] else { return [] }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    static func param(_ el: AXUIElement, _ name: String, _ arg: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(el, name as CFString, arg, &value) == .success ? value : nil
    }

    static func readB(area: AXUIElement, url: String?) -> ProbeRead {
        var r = ProbeRead(method: "B")
        let t0 = Clock.nowNs()
        let landmarks = search(area, key: "AXLandmarkSearchKey")
        r.landmarks = landmarks.count
        let main = landmarks.first { AX.subrole($0) == "AXLandmarkMain" }
        let root = main ?? area
        r.note = main == nil ? "no main landmark: full web area" : "main landmark"
        r.headings = search(area, key: "AXHeadingSearchKey", limit: 500).count
        // The sign-in check needs the fields: a search for secure fields and text fields.
        var fields: [ScreenElement] = []
        for el in search(area, key: "AXTextFieldSearchKey", limit: 100) {
            fields.append(ScreenElement(id: "f\(fields.count)", role: AX.role(el), subrole: AX.subrole(el),
                                        label: [AX.string(el, "AXPlaceholderValue"), AX.string(el, "AXDescription"), AX.string(el, "AXTitle")]
                                            .compactMap { $0 }.joined(separator: " "), risky: false))
        }
        if let s = SafetyPolicy.sensitive(url: url, elements: fields) {
            r.sensitive = s
            r.ms = Clock.ms(since: t0)
            return r
        }
        guard let range = param(root, "AXTextMarkerRangeForUIElement", root),
              let str = AX.text(param(area, "AXStringForTextMarkerRange", range)) else {
            r.note += "; the text marker calls gave nothing"
            r.ms = Clock.ms(since: t0)
            r.complete = false
            return r
        }
        var text = str
        if text.count > maxChars { text = String(text.prefix(maxChars)); r.complete = false }
        r.blocks = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { ProbeBlock(t: $0) }
        r.ms = Clock.ms(since: t0)
        return r
    }
}
