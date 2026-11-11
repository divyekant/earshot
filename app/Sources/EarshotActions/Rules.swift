import CoreGraphics
import EarshotCore
import Foundation

// The decisions of the action module as pure functions, so that unit tests can check them without a screen.
// No rule here names an app (R-MT-1, R-MT-2).

/// Facts about the command that the intent does not hold. The safety rules need them (R-NV-5, R-ON-5).
/// EarshotApp fills them from the input trigger and the RouteResult.
public struct CommandInfo: Sendable, Equatable {
    public var mode: InputMode
    public var tier: RouterTier
    /// The words that the owner said for the target, for example "send" in "click send".
    public var spokenTarget: String

    /// True only for an always-on "send" alone, in the checked voice of the owner, within 5 s after earshot typed in
    /// the same front app (the owner's choice, D-12). Only CommandPipeline sets it.
    public var ownerSendAfterTyping: Bool

    public init(mode: InputMode, tier: RouterTier, spokenTarget: String = "", ownerSendAfterTyping: Bool = false) {
        self.mode = mode; self.tier = tier; self.spokenTarget = spokenTarget; self.ownerSendAfterTyping = ownerSendAfterTyping
    }

    /// The strictest facts. A command with these facts never presses a risky element and never sends.
    public static let unknown = CommandInfo(mode: .alwaysOn, tier: .none)
}

/// Options of the action module.
public struct ActionOptions: Sendable, Equatable {
    /// Type dictated text into chats of other people (EarshotSettings.typeIntoOthers).
    public var typeIntoOthers: Bool = true
    /// Read the window text with Apple Vision when the window has few labelled elements (R-CL-4).
    /// It needs the Screen Recording permission. earshot never asks for it from the command path.
    public var ocrFallback: Bool = true
    /// Below this number of labelled elements, the OCR fallback runs.
    public var ocrBelow: Int = 3
    /// The most elements that one screen read keeps.
    public var maxElements: Int = 400
    /// A screen read older than this is too old for a click.
    public var maxSnapshotAgeMs: Double = 60_000

    public init(settings: EarshotSettings? = nil) {
        if let settings { typeIntoOthers = settings.typeIntoOthers }
    }
}

enum ActionText {
    static func normalize(_ s: String) -> String { SafetyPolicy.normalize(s) }

    /// The normalized text with no spaces. "Whats App" and "WhatsApp" have the same key.
    static func key(_ s: String) -> String { normalize(s).replacingOccurrences(of: " ", with: "") }

    /// Removes invisible characters, turns no-break spaces into spaces, and joins runs of white space.
    static func squash(_ s: String) -> String {
        let invisible: Set<UInt32> = [0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0xFEFF, 0xFFFC]
        var view = String.UnicodeScalarView()
        for u in s.unicodeScalars where !invisible.contains(u.value) { view.append(u.value == 0xA0 ? " " : u) }
        return String(view).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Removes control characters, so typed text can never hold Return or Tab (R-NV-5).
    static func printable(_ s: String) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return String(view)
    }

    /// Removes e-mail addresses and a browser's memory note, and cuts long labels.
    /// A browser tab title can end with its hover note "- Memory usage - 547 MB" (live test, 2026-11-03).
    static func cleanLabel(_ s: String) -> String {
        let squashed = squash(s).replacingOccurrences(of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, with: "[email]",
                                                      options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s*[-–—]\s*memory usage\s*[-–—:]\s*[\d.,]+\s*[kmg]b\s*$"#, with: "",
                                  options: .regularExpression)
        return squashed.count > 100 ? String(squashed.prefix(100)) : squashed
    }
}

/// The time limits of the chat switcher. Each wait ends as soon as the screen shows the next state.
enum SwitcherTiming {
    /// The time between two AX reads in a wait.
    static let pollMs = 15
    /// From the switcher keys to a focused search field.
    static let fieldMs = 1200
    /// The time between two searches for a switcher field that has no focus.
    static let scanMs = 60
    /// For an app with no learned switcher behaviour: the time before the first search for a field without focus.
    /// The focused-element check alone finds a field that takes the focus by itself (Slack Cmd-K).
    static let scanDelayMs = 150
    /// From the opened chat to a focused message box, when earshot finds and focuses the box itself.
    static let boxMs = 700
    /// The longest extra wait for the chat name, after the box has the focus.
    static let nameMs = 400
    /// From the typed name to the name in the field.
    static let typedMs = 1000
    /// From the name in the field to a result that shows the name. It replaces the fixed 250 ms sleep of E0.
    static let resultMs = 800
    /// After Return in the switcher: the longest wait for the field to close before earshot presses the result row.
    static let returnMs = 250
}

/// The time limit for "scroll into view" before a click (E2, section 7).
enum ScrollTiming {
    static let limitMs = 300
}

/// What the switcher list shows after the name (see ActionRules.switcherResult).
enum SwitcherResult: Equatable {
    case none
    case chat
    case searchFirst
}

/// The result of the chat check.
enum ChatCheck: String, Equatable {
    /// A text on screen is the chat name and nothing more. Typing needs this.
    case exact
    /// A text on screen holds the chat name.
    case partial
    case none
}

enum ActionRules {
    // MARK: - Fields

    static func labelSaysSearch(_ words: String) -> Bool {
        ["search", "jump to", "find", "go to"].contains { words.contains($0) }
    }

    /// A field whose label says that it writes a message, for example "Message to #general" or "Reply to thread".
    static func labelSaysComposer(_ words: String) -> Bool {
        ["message", "reply", "compose", "write", "send"].contains { words.contains($0) }
    }

    /// The shape of a message box: at least 30 % of the window width, and its middle in the lower half (E0).
    static func composerShape(field f: Frame, window w: Frame) -> Bool {
        f.w >= 0.3 * w.w && f.midY >= w.y + 0.5 * w.h
    }

    // MARK: - Elements

    static let buttonRoles: Set<String> = ["AXButton", "AXMenuButton", "AXPopUpButton", "AXDisclosureTriangle"]
    static let fieldRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    /// The role of an element that the OCR fallback found. It has no accessibility element.
    static let ocrRole = "OCRText"

    /// The kind of a clickable or typable element: link, button, field, check, tab, choice or row. Nil for other roles.
    static func kind(role: String, subrole: String) -> String? {
        if role == "AXLink" { return "link" }
        if buttonRoles.contains(role) { return "button" }
        if fieldRoles.contains(role) { return "field" }
        if role == "AXCheckBox" || role == "AXSwitch" { return "check" }
        if role == "AXRadioButton" { return subrole == "AXTabButton" ? "tab" : "choice" }
        if role == "AXTab" { return "tab" }
        if role == "AXMenuItem" { return "choice" }
        if role == "AXRow" { return "row" }
        if role == ocrRole { return "text" }
        return nil
    }

    /// Reading order: rows of 8 points from the top, then left to right (E2).
    static func readingOrder(_ a: Frame, _ b: Frame) -> Bool {
        let ra = Int((a.y / 8).rounded(.down)), rb = Int((b.y / 8).rounded(.down))
        return ra != rb ? ra < rb : a.x < b.x
    }

    /// Visible: at least 2 points wide and high, and inside the viewport.
    /// An element with an empty or 1x1 frame, or a frame fully outside the viewport, has no point on screen
    /// (for example a web "skip link"). The click step cannot reach it, so the read drops it.
    static func visible(_ f: Frame, in vp: Frame) -> Bool {
        f.w >= 2 && f.h >= 2 && f.overlaps(vp)
    }

    /// True if the frame is fully inside the view, with a margin of 1 point.
    static func inside(_ f: Frame, _ v: Frame) -> Bool {
        f.w >= 2 && f.h >= 2 && f.x >= v.x - 1 && f.y >= v.y - 1 && f.maxX <= v.maxX + 1 && f.maxY <= v.maxY + 1
    }

    /// The reason not to press after a scroll, or nil: the page must still be on the same site.
    static func afterScrollBlock(before: String?, after: String?) -> String? {
        guard let before, let host = URL(string: before)?.host else { return nil }
        guard let after, SafetyPolicy.onHost(after, host) else { return "blocked: the page changed during the scroll" }
        return nil
    }

    /// Roles that the walk for window controls does not go into: the web page, the menu bar, images and scroll bars.
    static let skipForControls: Set<String> = ["AXWebArea", "AXMenuBar", "AXImage", "AXScrollBar"]

    /// The page rules (a hidden tab, a sign-in page) apply to elements of the page. A window tab is not part of the
    /// page: a press on it only shows another tab. Other window controls, for example Reload, keep the page rules.
    static func pageRulesApply(kind: String, inPage: Bool) -> Bool { inPage || kind != "tab" }

    /// Links that the browser adds for screen readers. They are not part of the page.
    static let browserHints = ["To get missing image descriptions"]

    /// The element id for the number n on screen. "Click 3" is a click on "e3" (R-CL-3).
    static func elementID(number n: Int) -> String { "e\(n)" }

    // MARK: - Chats

    /// The handle for a chat link: the first alias that looks like a phone number or an address, else the name.
    static func handle(name: String, aliases: [String]) -> String {
        let phone = aliases.first { a in
            let digits = a.filter(\.isNumber).count
            return digits >= 6 && a.allSatisfy { $0.isNumber || "+-() ".contains($0) }
        }
        return phone ?? aliases.first(where: { $0.contains("@") }) ?? name
    }

    /// Fills "{handle}" of a link template from the catalogue. The handle is percent-encoded.
    static func linkURL(template: String, handle: String) -> URL? {
        guard template.contains("{handle}") else { return nil }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?#+"))
        let encoded = handle.addingPercentEncoding(withAllowedCharacters: allowed) ?? handle
        return URL(string: template.replacingOccurrences(of: "{handle}", with: encoded))
    }

    /// The name entry for a spoken target in an app: the same name, else the same alias.
    static func nameEntry(_ target: String, appID: String, names: [NameEntry]) -> NameEntry? {
        let key = ActionText.normalize(target)
        let inApp = names.filter { $0.appID == appID }
        return inApp.first { ActionText.normalize($0.name) == key }
            ?? inApp.first { $0.aliases.contains { ActionText.normalize($0) == key } }
    }

    /// Checks the texts on screen against the chat names. Window titles join parts with " - " or " | ":
    /// each part is tested. "exact" ignores the words "you" and "dm".
    static func chatCheck(texts: [String], names: [String]) -> ChatCheck {
        let exactKeys = Set(names.map(ActionText.normalize).filter { $0.count >= 2 })
        let keys = names.map(ActionText.key).filter { $0.count >= 2 }
        func exact(_ s: String) -> Bool {
            let parts = s.components(separatedBy: " - ").flatMap { $0.components(separatedBy: " | ") }
            return parts.contains { part in
                let tokens = ActionText.normalize(part).split(separator: " ").filter { $0 != "you" && $0 != "dm" }
                return exactKeys.contains(tokens.joined(separator: " "))
            }
        }
        if texts.contains(where: exact) { return .exact }
        if texts.contains(where: { t in let k = ActionText.key(t); return keys.contains { k.contains($0) } }) { return .partial }
        return .none
    }

    /// The key of a text at its place on screen: the same text in the sidebar and in the result list has two keys.
    static func placeKey(_ text: String, _ f: Frame) -> String {
        "\(ActionText.normalize(text))@\(Int(f.x.rounded())),\(Int(f.y.rounded()))"
    }

    /// The place keys of the texts that match the name.
    static func matchKeys(_ texts: [(String, Frame)], name: String) -> Set<String> {
        Set(texts.filter { chatCheck(texts: [$0.0], names: [name]) != .none }.map { placeKey($0.0, $0.1) })
    }

    /// True if a chat row that matches the name shows at a place where it was not before typing.
    static func resultShows(_ texts: [(String, Frame)], name: String, baseline: Set<String>) -> Bool {
        switcherResult(texts, name: name, baseline: baseline) == .chat
    }

    /// The start words of a row that runs the typed text as a query, not a chat. Slack (2026) shows
    /// "Search for: <name>", "Show results for: <name>" and "Ask Slackbot about <name>" in its Cmd-K list.
    /// Such a row holds the typed name, so the name alone does not make it a result.
    static let queryRowStarts = ["search for", "show results", "search in", "search all", "ask "]

    /// True if one text of the row starts with a query word.
    static func isQueryRow(_ texts: [String]) -> Bool {
        texts.contains { t in
            let s = t.lowercased().trimmingCharacters(in: .whitespaces)
            return queryRowStarts.contains { s.hasPrefix($0) }
        }
    }

    /// Groups the texts of a result list into rows, from top to bottom. A text joins the row above it
    /// if it starts before that row ends. A section label whose frame covers two or more rows
    /// (Slack "Suggestions") is left out, so that it does not join the rows into one.
    static func rows(_ texts: [(String, Frame)]) -> [[(String, Frame)]] {
        let starts = Set(texts.map { Int($0.1.y.rounded()) })
        func isSection(_ f: Frame) -> Bool {
            starts.filter { Double($0) > f.y + 2 && Double($0) < f.maxY - 2 }.count >= 2
        }
        var out: [[(String, Frame)]] = []
        var rowEnd = -Double.infinity
        for t in texts.filter({ !isSection($0.1) }).sorted(by: { $0.1.y < $1.1.y }) {
            if !out.isEmpty, t.1.y < rowEnd - 2 {
                out[out.count - 1].append(t)
                rowEnd = max(rowEnd, t.1.maxY)
            } else {
                out.append([t])
                rowEnd = t.1.maxY
            }
        }
        return out
    }

    /// What Return in the switcher would open. `.chat`: the first result row is a new row that matches the name.
    /// `.searchFirst`: a query row stays above that row, so Return would run a search. `.none`: no such row yet.
    static func switcherResult(_ texts: [(String, Frame)], name: String, baseline: Set<String>) -> SwitcherResult {
        var queryAbove = false
        for row in rows(texts) {
            if isQueryRow(row.map(\.0)) { queryAbove = true; continue }
            if !matchKeys(row, name: name).subtracting(baseline).isEmpty { return queryAbove ? .searchFirst : .chat }
        }
        return .none
    }

    /// The result row to press when Return does not open the chat (WhatsApp): the top row that is new,
    /// matches the name, is not a query row and has no risky word. Returns its index in `rows`, or nil.
    static func pickResultRow(_ rows: [(label: String, frame: Frame)], name: String, baseline: Set<String>) -> Int? {
        let order = rows.indices.sorted { rows[$0].frame.y < rows[$1].frame.y }
        for i in order {
            let (label, f) = rows[i]
            if isQueryRow([label]) || SafetyPolicy.isRisky(label) { continue }
            if baseline.contains(placeKey(label, f)) { continue }
            if chatCheck(texts: [label], names: [name]) != .none { return i }
        }
        return nil
    }

    /// The reason not to type the dictated text into the chat, or nil (R-NV-4).
    static func typeBlock(isSelf: Bool, typeIntoOthers: Bool, check: ChatCheck, boxText: String) -> String? {
        if !isSelf && !typeIntoOthers { return "focus only: typing into other chats is off" }
        if check != .exact { return "no typing: the chat name is not on screen" }
        if !ActionText.squash(boxText).isEmpty { return "no typing: the box holds a draft" }
        return nil
    }

    /// The switcher keys from the catalogue must name one key and must not name Return.
    /// Empty keys mean: focus the app's own search field through accessibility.
    static func switcherKeysValid(_ keys: String) -> Bool { keys.isEmpty || Keys.parse(keys) != nil }

    /// Return in the chat switcher is safe only in these places (E0):
    /// the search field that earshot typed the name into, while it holds exactly the name; or a row of a result list.
    /// Never in a message box, another text field or on a button.
    static func switcherReturnSafe(focusedIsComposer: Bool, focusedIsTypedField: Bool, focusedIsSwitcherField: Bool,
                                   focusedValue: String?, wanted: String, focusedRole: String) -> Bool {
        if focusedIsComposer { return false }
        if focusedIsTypedField {
            return focusedIsSwitcherField
                && focusedValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted.lowercased()
        }
        if AX.textRoles.contains(focusedRole) || fieldRoles.contains(focusedRole) { return false }
        return AX.listRoles.contains(focusedRole)
    }

    // MARK: - Safety gates

    /// The reason not to press this element, or nil (R-NV-5, R-ON-5, E2 safety rules).
    static func pressBlock(label: String, role: String? = nil, subrole: String? = nil, command: CommandInfo,
                           sensitive: String?) -> String? {
        if let sensitive { return "blocked: this looks like a sign-in, code or payment page (\(sensitive))" }
        if !SafetyPolicy.mayPress(label: label, role: role, subrole: subrole, spokenTarget: command.spokenTarget, tier: command.tier,
                                  mode: command.mode) {
            return "blocked: risky label \"\(label)\""
        }
        return nil
    }

    /// The reason not to press Return for "send", or nil. Only a held-key command that the rules decided can send,
    /// and only from a message box that holds text (R-NV-5, R-ON-5).
    static func sendBlock(command: CommandInfo, inMessageBox: Bool, boxText: String, sensitive: String?) -> String? {
        if let sensitive { return "blocked: this looks like a sign-in, code or payment page (\(sensitive))" }
        if command.mode != .hold, !command.ownerSendAfterTyping { return "blocked: send needs the hold key" }
        if command.tier != .rules { return "blocked: send needs the spoken word \"send\"" }
        if !inMessageBox { return "blocked: the focus is not in a message box" }
        if ActionText.squash(boxText).isEmpty { return "nothing to send: the box is empty" }
        if !SafetyPolicy.mayPressReturn(for: .send, inMessageBox: true) { return "blocked: Return" }
        return nil
    }

    /// The reason not to type into a field, or nil.
    static func typeIntoBlock(role: String, subrole: String, sensitive: String?) -> String? {
        if let sensitive { return "blocked: this looks like a sign-in, code or payment page (\(sensitive))" }
        if subrole == "AXSecureTextField" { return "blocked: a password field" }
        if !fieldRoles.contains(role) { return "not a text field" }
        return nil
    }

    // MARK: - Geometry

    /// The point to click for an element: near the start of the text, where a link has its words (E2).
    static func clickPoints(_ f: Frame) -> [CGPoint] {
        [CGPoint(x: f.x + min(f.w, 40) / 2, y: f.y + min(f.h, 24) / 2),
         CGPoint(x: f.midX, y: f.midY),
         CGPoint(x: f.x + f.w - min(f.w, 40) / 2, y: f.y + f.h - min(f.h, 24) / 2)]
    }

    /// The origin of a number badge in the local coordinates of an overlay window on one screen.
    /// AX points start at the top left of the main screen. AppKit points start at its bottom left.
    static func badgeOrigin(element f: Frame, badge: CGSize, mainScreenHeight: Double, screenOrigin: CGPoint) -> CGPoint {
        let cocoaY = mainScreenHeight - f.y - Double(badge.height)
        return CGPoint(x: f.x - screenOrigin.x, y: cocoaY - screenOrigin.y)
    }

    /// The screen frame of a text that Vision found. Vision boxes are 0...1, with the origin at the bottom left.
    static func ocrFrame(box: CGRect, window w: Frame) -> Frame {
        Frame(x: w.x + box.minX * w.w, y: w.y + (1 - box.maxY) * w.h, w: box.width * w.w, h: box.height * w.h)
    }

    /// Scroll plan: keys for a web page, else wheel lines and repeats (positive lines scroll up).
    enum ScrollPlan: Equatable {
        case key(Keys.Combo)
        case wheel(lines: Int32, times: Int)
    }

    static func scrollPlan(_ d: ScrollDirection, web: Bool) -> ScrollPlan {
        if web {
            switch d {
            case .down: return .key(Keys.pageDown)
            case .up: return .key(Keys.pageUp)
            case .top: return .key(Keys.home)
            case .bottom: return .key(Keys.end)
            }
        }
        switch d {
        case .down: return .wheel(lines: -12, times: 1)
        case .up: return .wheel(lines: 12, times: 1)
        case .top: return .wheel(lines: 100, times: 40)
        case .bottom: return .wheel(lines: -100, times: 40)
        }
    }
}
