import AppKit
import EarshotCore
import SwiftUI

// The page of a plugin in the window (design canvas "Window: Footnote"). If the plugin writes board.json, earshot
// draws its lists with the type and the rows of earshot, so that the plugin looks like a part of the app. The tabs are
// the pages of the plugin. The last tab is the settings form of plugin.json. Without a board, the page shows the HTML
// page of the plugin, with script off (docs/PLUGINS.md 5.4).

struct BoardPage: View {
    let pages: PluginPages
    let reload: Int
    /// The tab to show first, for example the settings tab when the Plugins page opens the rules.
    var start: String?
    @State private var board: Board?
    @State private var tab = ""
    /// The tab id of the settings form.
    static let settingsID = "__settings"

    var body: some View {
        Group {
            if let board {
                boardBody(board)
            } else if pages.hasIndex && tab != Self.settingsID {
                VStack(spacing: 0) {
                    if !pages.settings.isEmpty { tabRow(nil).padding(.horizontal, 32).padding(.vertical, 12) }
                    PluginPageView(pages: pages, reload: reload)
                }
            } else {
                PageFrame(top: 26) {
                    if pages.hasIndex { tabRow(nil) }
                    PageTitle(title: pages.name, sub: "\(pages.name) has no lists to show. These are its settings.")
                        .padding(.top, pages.hasIndex ? 22 : 4)
                    PluginSettingsForm(pages: pages).padding(.top, 24)
                }
            }
        }
        .onAppear {
            if let start { tab = start }
            load()
        }
        .onChange(of: start) { _, new in if let new { tab = new } }
        .onChange(of: reload) { _, _ in load() }
        .onChange(of: pages) { _, _ in load() }
    }

    private func load() {
        board = pages.board
        if let board, tab.isEmpty || (tab != Self.settingsID && !board.tabs.contains { $0.id == tab }) {
            tab = board.tabs.first?.id ?? Self.settingsID
        }
    }

    private func tabRow(_ board: Board?) -> some View {
        var tabs: [(value: String, title: String)] = board?.tabs.map { ($0.id, $0.title) } ?? [("", "Pages")]
        if !pages.settings.isEmpty { tabs.append((Self.settingsID, board?.settingsTab ?? "Settings")) }
        return PageTabs(selection: $tab, tabs: tabs)
    }

    @ViewBuilder private func boardBody(_ board: Board) -> some View {
        PageFrame(top: 26) {
            HStack {
                tabRow(board)
                Spacer()
                if let date = board.tabs.first(where: { $0.id == tab })?.date {
                    Text(date).textStyle(.mono, Palette.ink3)
                }
            }
            if tab == Self.settingsID {
                PageTitle(title: board.settingsTab ?? "Settings",
                          sub: "\(pages.name) reads these choices from its settings file. A change works at once.")
                    .padding(.top, 22)
                PluginSettingsForm(pages: pages).padding(.top, 20)
            } else if let t = board.tabs.first(where: { $0.id == tab }) {
                PageTitle(title: t.heading ?? t.title, sub: t.sub).padding(.top, 22)
                ForEach(Array(t.sections.enumerated()), id: \.offset) { _, s in section(s) }
                if let hint = t.hint {
                    HStack(spacing: 8) {
                        Glyph(.plugin, size: 14)
                        Text(hint)
                    }
                    .textStyle(.detail, Palette.ink3)
                    .padding(.top, 26)
                }
            }
        }
    }

    @ViewBuilder private func section(_ s: Board.Section) -> some View {
        if let title = s.title {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).textStyle(TextStyle(13, 18, 600), s.late ? Palette.coral : Palette.ink2)
                if let n = s.rows?.count, n > 0 { Text("\(n)").textStyle(.mono, Palette.ink3) }
            }
            .padding(.top, 28).padding(.bottom, 4)
        }
        if let text = s.text {
            Text(text).textStyle(.call, Palette.ink2).fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)
        }
        if let rows = s.rows {
            if rows.isEmpty, let empty = s.empty {
                Text(empty).textStyle(.body, Palette.ink3).padding(.vertical, 11)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    BoardRow(row: row, late: s.late || row.isLate, last: i == rows.count - 1) {
                        if let open = row.open { BoardOpen.open(open, pages: pages) }
                    }
                }
            }
        }
        if let numbers = s.numbers, !numbers.isEmpty {
            HStack(alignment: .top, spacing: 26) {
                ForEach(Array(numbers.enumerated()), id: \.offset) { _, n in
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(n.value)").textStyle(TextStyle(18, 24, mono: true), Palette.ink)
                        Text(n.label).textStyle(.detail, Palette.ink3)
                    }
                }
            }
            .padding(.top, 12)
        }
    }
}

/// One row of a board: a mark, the text, an aside and a time.
struct BoardRow: View {
    let row: Board.Row
    let late: Bool
    let last: Bool
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            switch row.mark {
            case "todo":
                Circle().strokeBorder(late ? Palette.coral : Palette.ink3, lineWidth: 1.5).frame(width: 12, height: 12)
            case "doc": Glyph(.window, size: 14).foregroundStyle(Palette.ink3)
            case "flag": Glyph(.failed, size: 14).foregroundStyle(Palette.amber)
            case "note": Glyph(.typed, size: 14).foregroundStyle(Palette.ink3)
            default: EmptyView()
            }
            (Text(row.text).foregroundColor(Palette.ink) + Text(row.detail.map { " · \($0)" } ?? "").foregroundColor(Palette.ink3))
                .textStyle(TextStyle(14.5, 20))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let when = row.when {
                Text(when).textStyle(TextStyle(12, 20, mono: true), late ? Palette.coral : Palette.ink3).lineLimit(1)
            }
            if row.open != nil {
                Glyph(.chevronRight, size: 14).foregroundStyle(hover ? Palette.ink2 : Palette.ink4)
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { if !last { Rule() } }
        .contentShape(Rectangle())
        .onHover { h in if row.open != nil { withAnimation(Motion.hover) { hover = h } } }
        .onTapGesture { if row.open != nil { open() } }
    }
}

/// The settings of a plugin as rows with a segmented choice (docs/PLUGINS.md 3.2). earshot writes each change to the
/// settings file of the plugin at once. The plugin reads the file again.
struct PluginSettingsForm: View {
    let pages: PluginPages
    @State private var values: [String: String] = [:]
    @State private var error = ""

    private var file: PluginSettingsFile { PluginSettingsFile(url: pages.settingsFile) }

    /// The settings in their groups, in the order of plugin.json.
    private var groups: [(name: String, items: [PluginSetting])] {
        var out: [(String, [PluginSetting])] = []
        for s in pages.settings {
            let g = s.group ?? ""
            if let i = out.firstIndex(where: { $0.0 == g }) { out[i].1.append(s) } else { out.append((g, [s])) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(groups, id: \.name) { group in
                VStack(alignment: .leading, spacing: 10) {
                    if !group.name.isEmpty { GroupTitle(group.name) }
                    RowGroup {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { i, s in
                            SettingRow(s.label, last: i == group.items.count - 1) {
                                Segmented(selection: binding(s), options: s.choices.map { ($0, Self.title($0)) })
                            }
                        }
                    }
                }
            }
            if !error.isEmpty { Text(error).textStyle(.detail, Palette.coral) }
        }
        .onAppear(perform: load)
    }

    /// "alert" shows as "Alert".
    static func title(_ choice: String) -> String {
        guard let f = choice.first else { return choice }
        return f.uppercased() + choice.dropFirst()
    }

    private func load() {
        var v: [String: String] = [:]
        for s in pages.settings { v[s.key] = file.value(s) }
        values = v
    }

    private func binding(_ s: PluginSetting) -> Binding<String> {
        Binding(get: { values[s.key] ?? s.default }, set: { new in
            do {
                try file.set(s, to: new)
                values[s.key] = new
                error = ""
            } catch {
                self.error = "Could not save “\(s.label)”: \(error.localizedDescription)"
            }
        })
    }
}
