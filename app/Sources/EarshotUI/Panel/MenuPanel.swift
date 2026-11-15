import AppKit
import EarshotCore
import SwiftUI

// The menu bar panel (dk, 2026-11-15, design canvas "Panel A" and "Panel B"): 360 pt wide. The header always says
// what earshot does now. A problem never replaces the header: it shows as a banner with one key. The lists of a
// plugin (its board) sit above the last commands, drawn by earshot.

/// A page of the window, for a link from the panel.
public enum WindowPage: Hashable, Sendable {
    case plugin(String), activity, settings, apps, plugins, system
}

/// Asks the window to show a page. The panel sets it, the window reads it.
@MainActor
public final class WindowNav: ObservableObject {
    public static let shared = WindowNav()
    @Published public var request: WindowPage?
    public func show(_ page: WindowPage) { request = page }
}

/// The values and actions that the panel needs. EarshotApp gives them.
public struct PanelModel {
    public var live: LiveState
    public var mode: Binding<InputMode>
    public var startsAtLogin: Binding<Bool>
    /// The level of the open turn, for the voice bars.
    public var level: VoiceLevel?
    /// The things that need the owner now. The panel reads them each time it opens.
    public var notices: () -> [Notice]
    /// The key of a notice.
    public var act: (Notice) -> Void
    public var pause: () -> Void
    public var resume: () -> Void
    /// Opens the window at a page.
    public var open: (WindowPage) -> Void
    public var quit: () -> Void

    public init(live: LiveState, mode: Binding<InputMode>, startsAtLogin: Binding<Bool>, level: VoiceLevel? = nil,
                notices: @escaping () -> [Notice] = { [] }, act: @escaping (Notice) -> Void = { _ in },
                pause: @escaping () -> Void, resume: @escaping () -> Void, open: @escaping (WindowPage) -> Void,
                quit: @escaping () -> Void) {
        self.live = live; self.mode = mode; self.startsAtLogin = startsAtLogin; self.level = level
        self.notices = notices; self.act = act; self.pause = pause; self.resume = resume; self.open = open; self.quit = quit
    }
}

/// The panel under the menu bar icon.
public struct MenuPanel: View {
    let model: PanelModel
    let store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var records: [ActivityRecord] = []
    @State private var apps: [AppEntry] = []
    @State private var boards: [(pages: PluginPages, list: Board.PanelList)] = []
    @State private var notices: [Notice] = []
    /// Set by the snapshots: the panel shows these values and reads nothing.
    var fixed: PanelData?

    public init(model: PanelModel, store: Store) {
        self.model = model
        self.store = store
    }

    init(model: PanelModel, store: Store, fixed: PanelData) {
        self.model = model; self.store = store; self.fixed = fixed
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 0) {
                Segmented(selection: model.mode, options: [(InputMode.hold, "Hold key"), (InputMode.alwaysOn, "Always on")], full: true)
                if !shownNotices.isEmpty {
                    VStack(spacing: 6) { ForEach(shownNotices) { NoticeBanner(notice: $0, act: model.act) } }
                        .padding(.top, 10)
                }
                Group {
                    if shownRecords.isEmpty && shownBoards.isEmpty {
                        FirstCommand(live: model.live)
                    }
                    ForEach(shownBoards, id: \.pages.id) { b in boardSection(b.pages, b.list) }
                    if !shownRecords.isEmpty { recentSection }
                }
                .opacity(model.live.listen == .listening ? 0.45 : 1)
                .animation(Motion.ease(0.3), value: model.live.listen)
            }
            .padding(.horizontal, 16)
            footer
        }
        .frame(width: 360)
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
        // Escape closes the panel (Mac check 2026-11-15: the window style does not close on Escape by itself).
        .background(Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
            .accessibilityHidden(true))
    }

    private var shownRecords: [ActivityRecord] {
        let all = fixed?.records ?? records
        return PanelText.recent(all, count: shownBoards.isEmpty ? 5 : 4)
    }
    private var shownBoards: [(pages: PluginPages, list: Board.PanelList)] { fixed?.boards ?? boards }
    private var shownNotices: [Notice] { fixed?.notices ?? notices }
    private var shownApps: [AppEntry] { fixed?.apps ?? apps }

    // MARK: Header

    private var header: some View {
        let h = model.live.header
        return HStack(spacing: 12) {
            Orb(model.live.orb, level: model.level)
            VStack(alignment: .leading, spacing: 2) {
                Text(h.title).textStyle(.head, Palette.ink).lineLimit(1)
                HStack(spacing: 5) {
                    if !h.before.isEmpty { Text(h.before) }
                    if let key = h.key { Keycap(key, size: .mini) }
                    if !h.after.isEmpty { Text(h.after) }
                }
                .textStyle(.detail, Palette.ink2)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if model.live.listen == .paused {
                Button("Resume", action: model.resume).buttonStyle(KeyStyle(.ink, small: true))
                    .help("Listen again now")
            } else {
                Button("Pause", action: model.pause).buttonStyle(KeyStyle(.line, small: true))
                    .help("Stop the mic and the keys for 1 hour")
            }
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
    }

    // MARK: Lists

    private func boardSection(_ pages: PluginPages, _ list: Board.PanelList) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHead(title: list.title, link: pages.name) { go(.plugin(pages.id)) }
            if list.rows.isEmpty, let empty = list.empty {
                Text(empty).textStyle(.row, Palette.ink3).padding(.vertical, 8)
            }
            ForEach(Array(list.rows.enumerated()), id: \.offset) { _, row in
                PanelRowView(mark: Self.mark(row), title: row.text, aside: row.detail, detail: nil,
                             when: row.when ?? "", whenTone: row.isLate ? Palette.coral : Palette.ink3) {
                    if let open = row.open { BoardOpen.open(open, pages: pages) } else { go(.plugin(pages.id)) }
                }
            }
        }
        .padding(.top, 14).padding(.bottom, 6)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHead(title: "Recent", link: "Activity") { go(.activity) }
            ForEach(shownRecords) { r in
                let line = RecordText.line(r, apps: shownApps)
                let fresh = Date().timeIntervalSince(r.at) < 60
                PanelRowView(mark: .glyph(line.glyph, tone(line.tone)), title: line.title, aside: nil, detail: line.detail,
                             when: fresh ? "now" : Self.time(r.at), whenTone: fresh ? Palette.ink : Palette.ink3) { go(.activity) }
            }
        }
        .padding(.top, 14).padding(.bottom, 6)
    }

    private func tone(_ t: RecordLine.Tone) -> Color {
        switch t {
        case .failed: return Palette.coral
        case .asked: return Palette.amber
        default: return Palette.ink2
        }
    }

    /// The mark of a board row, as on the plugin page: a circle for a to-do, a glyph for a document, a flag or a note.
    static func mark(_ row: Board.Row) -> PanelRowView.Mark {
        switch row.mark {
        case "doc": return .glyph(.window, Palette.ink3)
        case "flag": return .glyph(.failed, Palette.amber)
        case "note": return .glyph(.typed, Palette.ink3)
        default: return .todo(late: row.isLate)
        }
    }

    /// The time of a command today, the day of the week in the last 6 days, else the date.
    static func time(_ d: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(d, inSameDayAs: now) { return d.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()) }
        if now.timeIntervalSince(d) < 6 * 86_400 { return d.formatted(.dateTime.weekday(.abbreviated)) }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                if model.live.cloudOn {
                    Dot(.amber)
                    Text("Jev cloud is on").textStyle(.small, Palette.amber)
                } else {
                    Glyph(.onMac, size: 14).foregroundStyle(Palette.ink3)
                    Text("On this Mac").textStyle(.small, Palette.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(model.live.cloudOn ? "A Jev setting is on: earshot can send command words to Jev, never audio."
                                     : "All audio and all decisions stay on this Mac.")
            Button("Open earshot") { go(model.live.needsYou ? .system : .activity) }.buttonStyle(QuietStyle())
            MoreMenu(model: model, go: go)
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 12, trailing: 16))
        .overlay(alignment: .top) { Rule() }
        .padding(.top, 8)
    }

    private func go(_ page: WindowPage) {
        dismiss()
        model.open(page)
    }

    private func load() {
        guard fixed == nil else { return }
        records = PanelText.recent(ActivityLog(store: store).last(60), count: 5)
        apps = store.apps
        boards = PluginPages.find(store: store).compactMap { p in p.board?.panel.map { (p, $0) } }
            .filter { !$0.1.rows.isEmpty || $0.1.empty != nil }
        notices = model.notices()
    }
}

/// The values that a snapshot of the panel shows.
struct PanelData {
    var records: [ActivityRecord]
    var apps: [AppEntry]
    var boards: [(pages: PluginPages, list: Board.PanelList)]
    var notices: [Notice]
}

/// The heading of a part of the panel, with a link to its page.
struct SectionHead: View {
    let title: String
    let link: String
    let action: () -> Void
    var body: some View {
        HStack {
            Text(title).textStyle(.label, Palette.ink2)
            Spacer()
            Button(action: action) {
                HStack(spacing: 3) { Text(link); Glyph(.chevronRight, size: 12) }
            }
            .buttonStyle(QuietStyle(TextStyle(12, 16)))
        }
        .padding(.bottom, 2)
    }
}

/// One row of the panel: a mark, one or two lines, and a time.
struct PanelRowView: View {
    enum Mark { case glyph(GlyphKind, Color), todo(late: Bool) }
    let mark: Mark
    let title: String
    let aside: String?
    let detail: String?
    let when: String
    var whenTone: Color = Palette.ink3
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                switch mark {
                case let .glyph(kind, color): Glyph(kind).foregroundStyle(color).padding(.top, 2)
                case let .todo(late): Circle().strokeBorder(late ? Palette.coral : Palette.ink3, lineWidth: 1.5).frame(width: 12, height: 12).padding(.top, 3.5)
                }
            }
            // One column for all marks, so that the texts start at one line.
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                (Text(title).foregroundColor(Palette.ink) + Text(aside.map { " · \($0)" } ?? "").foregroundColor(Palette.ink3))
                    .textStyle(.row).lineLimit(1).truncationMode(.tail)
                if let detail, !detail.isEmpty {
                    Text(detail).textStyle(.small, Palette.ink3).lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(when).textStyle(TextStyle(11.5, 19, mono: true), whenTone).lineLimit(1)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? Palette.raise : .clear))
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.hover) { hover = h } }
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A notice as a banner, with its one key.
struct NoticeBanner: View {
    let notice: Notice
    let act: (Notice) -> Void
    var body: some View {
        let amber = notice.kind == .needsYou
        HStack(alignment: .top, spacing: 10) {
            Glyph(notice.glyph).foregroundStyle(amber ? Palette.amber : Palette.ink2).padding(.top, 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(notice.title).textStyle(.detail, Palette.ink)
                if !notice.detail.isEmpty { Text(notice.detail).textStyle(.detail, Palette.ink2) }
                if let p = notice.progress {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.fill)
                            Capsule().fill(Palette.ink).frame(width: g.size.width * min(1, max(0, p)))
                        }
                    }
                    .frame(height: 3).padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            if let action = notice.action {
                Button(action) { act(notice) }.buttonStyle(KeyStyle(notice.main ? .ink : .line, small: true))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(amber ? Palette.amberWash : Palette.raise))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(amber ? Palette.amber.opacity(0.28) : Palette.rule, lineWidth: 1))
    }
}

/// The first run: the panel teaches the first command with the real key.
struct FirstCommand: View {
    let live: LiveState
    var body: some View {
        VStack(spacing: 14) {
            Keycap(LiveState.capOnly(live.holdKey), size: .big)
            let strong = Typeface.font(TextStyle(13, 18, 600))
            Group {
                if live.mode == .alwaysOn {
                    Text("Say “\(live.wakePhrase), open Notes”.").font(strong).foregroundColor(Palette.ink)
                        + Text(" Or hold the key and say it. Your commands show here.").foregroundColor(Palette.ink2)
                } else {
                    Text("Hold \(LiveState.holdWords(live.holdKey)) and say “open Notes”.").font(strong).foregroundColor(Palette.ink)
                        + Text(" Let go, and earshot does it. Your commands show here.").foregroundColor(Palette.ink2)
                }
            }
            .textStyle(.call)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 270)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26).padding(.bottom, 18)
    }
}

/// The ··· menu of the panel: the pages, start at login, and quit.
struct MoreMenu: View {
    let model: PanelModel
    let go: (WindowPage) -> Void
    var body: some View {
        Menu {
            Button("Settings") { go(.settings) }.keyboardShortcut(",")
            Button("Activity") { go(.activity) }
            if model.live.cloudOn { Button("Cloud settings…") { go(.settings) } }
            Divider()
            Toggle("Start at login", isOn: model.startsAtLogin)
            Divider()
            Button("Quit earshot", action: model.quit).keyboardShortcut("q")
        } label: {
            Glyph(.more).foregroundStyle(Palette.ink2)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
    }
}

/// Opens the link of a board row with the rule of "open <target>" (docs/PLUGINS.md 4).
enum BoardOpen {
    static func open(_ target: String, pages: PluginPages) {
        let url: URL? = target.hasPrefix("/") ? URL(fileURLWithPath: target)
            : (URL(string: target).flatMap { $0.scheme == nil ? pages.folder.appendingPathComponent(target) : $0 })
        guard let url else { return }
        switch pages.place(of: url) {
        case .inView, .outside: NSWorkspace.shared.open(url)
        case .blocked: break
        }
    }
}
