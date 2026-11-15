import AppKit
import EarshotCore
import SwiftUI

// The system page (design canvas "Window: System"): the macOS access, a typed command, and the version.
// It takes the place of "Advanced". The typed command shows its answer in the words of the panel and the note.

/// The words of the System page, as pure functions for the tests.
public enum SystemWords {
    /// True on macOS 26 and later. There the Apple engine is SpeechTranscriber, which runs without the Speech
    /// recognition permission (dk's Mac, 2026-11-15: the permission was never asked, and the Apple engine typed).
    /// On older macOS, the Apple engine is SFSpeechRecognizer, which needs it.
    public static let speechNeedsNoPermission = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))

    /// One short line about each permission.
    public static func why(_ p: Permission, newSpeech: Bool = speechNeedsNoPermission) -> String {
        switch p {
        case .accessibility: return "Read the screen, type and click"
        case .microphone: return "Hear commands. Audio stays on this Mac."
        case .speech: return newSpeech ? "Optional. The speech engines of macOS 26 run without it." : "The Apple speech engine, on this Mac"
        case .inputMonitoring: return "Read the hold key in other apps"
        case .screenRecording: return "Optional. Read text in apps with poor labels."
        }
    }

    /// True if earshot works without the permission: Screen Recording, and Speech recognition on macOS 26.
    public static func optional(_ p: Permission, newSpeech: Bool = speechNeedsNoPermission) -> Bool {
        p == .screenRecording || (p == .speech && newSpeech)
    }

    /// "4 of 5 allowed · the fifth is optional", "All 5 allowed", "3 of 5 allowed".
    public static func accessLine(_ states: [Permission: PermissionState], newSpeech: Bool = speechNeedsNoPermission) -> String {
        let all = Permission.allCases
        let on = all.filter { states[$0] == .granted }
        if on.count == all.count { return "All \(all.count) allowed" }
        let missing = all.filter { states[$0] != .granted }
        if missing.allSatisfy({ optional($0, newSpeech: newSpeech) }) {
            return "\(on.count) of \(all.count) allowed · " + (missing.count == 1 ? "the fifth is optional" : "the others are optional")
        }
        return "\(on.count) of \(all.count) allowed"
    }

    /// What earshot would do, in a few words: "open Slack", "click “Reply”".
    public static func phrase(_ intent: Intent, apps: [AppEntry]) -> String {
        func app(_ id: String) -> String { apps.first { $0.id == id }?.name ?? id }
        switch intent {
        case .none: return "do nothing"
        case .openApp(let id): return "open \(app(id))"
        case .openURL(let address): return "open \(URL(string: address)?.host ?? address)"
        case let .openChat(id, target, text):
            return "open the chat with \(target) in \(app(id))" + ((text ?? "").isEmpty ? "" : ", then type the text")
        case .click(let id):
            if let path = MenuElements.path(id) { return "choose " + path.joined(separator: " › ") }
            return "click a button on the screen"
        case .typeInto: return "type in a field on the screen"
        case .typeText: return "type the text"
        case .scroll(let d): return "scroll \(d.rawValue)"
        case .back: return "go back"
        case .showNumbers: return "show the numbers"
        case .hideNumbers: return "hide the numbers"
        case .send: return "press Send"
        case let .pressKey(key, times): return "press \(IntentText.KeyText.name(key))" + (times > 1 ? " \(times) times" : "")
        case .undoTyping: return "take back the last typing"
        case let .handOff(id, lead, _): return "give the words after “\(lead)” to the plugin \(id)"
        case let .openTarget(_, name, _): return "open \(name)"
        }
    }

    /// The answer to a typed command, as a title and one line.
    public static func answer(_ r: TestReport, apps: [AppEntry]) -> (glyph: GlyphKind, tone: Tone, title: String, detail: String) {
        let what = phrase(r.route.intent, apps: apps)
        if let o = r.outcome {
            if o.ok { return (.sent, .done, "Done: " + what, o.note.isEmpty ? "" : o.note) }
            return (.failed, .failed, "Did not work: " + what, o.note)
        }
        if case .none = r.route.intent {
            return (.notDone, .quiet, "earshot would do nothing", r.route.why.isEmpty ? "No app, button or command matches." : r.route.why)
        }
        if IntentText.belowLine(r.route) {
            let other = r.route.alternatives.first.map { phrase($0, apps: apps) }
            let title = other.map { "earshot would ask: \(what) or \($0)?" } ?? "earshot would ask: \(what)?"
            return (.notSure, .asked, title, "It is below the line to act alone, so earshot asks you first.")
        }
        return (.click, .done, "earshot would " + what, r.route.why)
    }

    public enum Tone: Sendable { case done, failed, asked, quiet }

    /// The tier in plain words.
    public static func tier(_ t: RouterTier) -> String {
        switch t {
        case .rules: return "exact rule"
        case .fuzzy: return "close match"
        case .jev: return "Jev, cloud"
        case .model: return "model"
        case .none: return "no match"
        }
    }
}

struct SystemPage: View {
    let store: Store
    let hooks: ManageHooks
    let speech: EngineChoice
    @State private var states: [Permission: PermissionState] = [:]
    @State private var text = ""
    @State private var act = false
    @State private var busy = false
    @State private var report: TestReport?
    @State private var apps: [AppEntry] = []

    var body: some View {
        PageFrame(top: 30) {
            PageTitle(title: "System")
            HStack(alignment: .firstTextBaseline) {
                Text("Access").textStyle(.section, Palette.ink)
                Spacer()
                Text(SystemWords.accessLine(states)).textStyle(.small, Palette.ink3)
            }
            .padding(.top, 30).padding(.bottom, 4)
            ForEach(Array(Permission.allCases.enumerated()), id: \.element) { i, p in
                accessRow(p, last: i == Permission.allCases.count - 1)
            }
            Text("macOS keeps each permission only while the code signature of earshot stays the same. After a new build, macOS can ask again.")
                .textStyle(.small, Palette.ink3).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            HStack(alignment: .firstTextBaseline) {
                Text("Try a command").textStyle(.section, Palette.ink)
                Spacer()
                Text("Type it the way you would say it").textStyle(.small, Palette.ink3)
            }
            .padding(.top, 36).padding(.bottom, 10)
            tryBox
            Rule().padding(.top, 30)
            foot.padding(.top, 14)
        }
        .onAppear { apps = store.apps }
        .task {
            while !Task.isCancelled {
                read()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: Access

    private func accessRow(_ p: Permission, last: Bool) -> some View {
        let state = states[p] ?? .notAsked
        return HStack(spacing: 12) {
            Text(p.title).textStyle(.bodyStrong, Palette.ink)
            Text(SystemWords.why(p)).textStyle(.detail, Palette.ink3).lineLimit(1)
            Spacer(minLength: 12)
            if state == .granted {
                HStack(spacing: 6) {
                    Glyph(.check, size: 13).foregroundStyle(Palette.ink2)
                    Text("Allowed").textStyle(.call, Palette.ink2)
                }
            } else {
                Button("Allow") {
                    if state == .notAsked && Permissions.canAsk(p) { Permissions.ask(p) } else { NSWorkspace.shared.open(p.settingsURL) }
                    read()
                }
                .buttonStyle(KeyStyle(SystemWords.optional(p) ? .line : .ink, small: true))
                .help(state == .notAsked ? "macOS asks you." : "Opens Privacy & Security in System Settings.")
            }
        }
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) { if !last { Rule() } }
    }

    private func read() {
        var new: [Permission: PermissionState] = [:]
        for p in Permission.allCases { new[p] = Permissions.state(p) }
        if new != states { states = new }
    }

    // MARK: Try a command

    private var tryBox: some View {
        RowGroup {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Field(text: $text, prompt: "open notes", commitOnBlur: false, onCommit: run)
                    Button(busy ? "…" : "Try", action: run)
                        .buttonStyle(KeyStyle(.ink, small: true))
                        .disabled(hooks.test == nil || busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 14)
                HStack(spacing: 8) {
                    Toggle("", isOn: $act).toggleStyle(SwitchStyle()).labelsHidden()
                    Text("Also do it").textStyle(.call, Palette.ink)
                    Text(act ? "· on: earshot acts in the app in front of this window" : "· off: earshot only shows what it would do")
                        .textStyle(.call, Palette.ink3)
                }
                .padding(.top, 12).padding(.bottom, report == nil ? 14 : 0)
                if hooks.test == nil { NotConnected(what: "The router").padding(.bottom, 14) }
                if let report {
                    Rule().padding(.top, 14)
                    result(report).padding(.vertical, 14)
                }
            }
        }
    }

    private func result(_ r: TestReport) -> some View {
        let a = SystemWords.answer(r, apps: apps)
        let color: Color = switch a.tone {
        case .done: Palette.ink2
        case .failed: Palette.coral
        case .asked: Palette.amber
        case .quiet: Palette.ink3
        }
        return HStack(alignment: .top, spacing: 10) {
            Glyph(a.glyph, size: 15).foregroundStyle(color).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(a.title).textStyle(TextStyle(14, 20, 600), Palette.ink).fixedSize(horizontal: false, vertical: true)
                if !a.detail.isEmpty {
                    Text(a.detail).textStyle(.detail, Palette.ink2).fixedSize(horizontal: false, vertical: true)
                }
                Text("Heard “\(r.heard)”").textStyle(.detail, Palette.ink3).padding(.top, 2)
                HStack(spacing: 6) {
                    Chip(SystemWords.tier(r.route.tier))
                    Chip(String(format: "%.2f sure", r.route.confidence))
                    Chip("\(Int(r.route.ms.rounded())) ms")
                    if let o = r.outcome, let total = o.stages.values.max() { Chip("acted in \(Int(total.rounded())) ms") }
                }
                .padding(.top, 8)
            }
            .textSelection(.enabled)
        }
    }

    private func run() {
        guard let test = hooks.test, !busy else { return }
        let command = text.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }
        busy = true
        let doIt = act
        Task { @MainActor in
            let r = await test(command, doIt)
            withAnimation(Motion.control) { report = r }
            busy = false
        }
    }

    // MARK: Foot

    private var foot: some View {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = (info["EarshotCommit"] as? String).map { String($0.prefix(7)) } ?? "local"
        let engine = switch speech {
        case .auto: "Automatic"
        case .apple: "Apple"
        case .parakeet: "Parakeet"
        }
        return HStack(spacing: 22) {
            fact("earshot", version)
            fact("build", build)
            fact("speech", engine)
            Spacer()
            Button("Open the data folder") { NSWorkspace.shared.open(store.folder) }.buttonStyle(QuietStyle())
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).textStyle(.call, Palette.ink3)
            Text(value).textStyle(TextStyle(12.5, 18, mono: true), Palette.ink2).textSelection(.enabled)
        }
    }
}
