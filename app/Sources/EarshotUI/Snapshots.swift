import AppKit
import EarshotCore
import SwiftUI

// Pictures of each screen, for the design check (`earshot snapshot <folder>`). Each view draws in a window off the
// screen, and the picture goes to a PNG file. The run reads a copy of the store, so it changes no file of the owner.
// It starts no module: no microphone, no keys, no plugin.

public enum UISnapshots {
    /// Writes one PNG file for each screen to `folder`. Returns the file names.
    @MainActor public static func write(to folder: URL, store: Store) -> [String] {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var out: [String] = []
        func shot<V: View>(_ name: String, _ size: CGSize?, _ view: V) {
            if render(view, size: size, to: folder.appendingPathComponent(name + ".png")) { out.append(name) }
        }
        let settings = store.settings
        let key = HoldKeys.capText(of: settings)
        let idle = LiveState(mode: settings.mode, wakePhrase: settings.wakePhrase, holdKey: key)
        let window = CGSize(width: 1040, height: 720)

        // The panel in four states.
        let level = VoiceLevel()
        level.set(dbAboveFloor: 18)
        func panel(_ live: LiveState, notices: [Notice] = []) -> AnyView {
            AnyView(panelView(live, notices: notices, level: level, store: store))
        }
        shot("panel-ready", nil, panel(idle))
        var hearing = idle
        hearing.listen = .listening
        shot("panel-hearing", nil, panel(hearing))
        var paused = idle
        paused.listen = .paused
        paused.pausedUntil = Date().addingTimeInterval(3600)
        shot("panel-paused", nil, panel(paused))
        var needs = idle
        needs.needsYou = true
        shot("panel-needs-you", nil, panel(needs, notices: [
            Notice(id: "plugin-x", glyph: .plugin, title: "A plugin waits for you", detail: "It does not run until you approve it.",
                   action: "Look"),
            Notice(id: "wake", kind: .working, glyph: .download, title: "Downloading the wake phrase models",
                   detail: "About 35 MB, one time. The hold key works now.", progress: 0.4),
        ]))

        // The window pages.
        let plugins = PluginPages.find(store: store)
        let pages: [(String, WindowPage)] = plugins.map { ("window-plugin-\($0.id)", WindowPage.plugin($0.id)) } + [
            ("window-activity", .activity), ("window-settings", .settings), ("window-apps", .apps),
            ("window-plugins", .plugins), ("window-system", .system),
        ]
        for (name, page) in pages {
            WindowNav.shared.request = page
            shot(name, window, ManageView(settings: .constant(settings), store: store, live: idle))
        }
        WindowNav.shared.request = nil

        // A plugin board from made-up rows. The page of a plugin that waits for approval does not show, so the
        // check of the board does not depend on the plugins of the owner.
        if let sample = sampleBoard(in: store.folder.appendingPathComponent("snapshot-sample", isDirectory: true)) {
            shot("window-board-sample", window, BoardPage(pages: sample.pages, reload: 0)
                .frame(width: window.width, height: window.height).background(Palette.paper))
            if let list = sample.board.panel {
                let data = PanelData(records: sampleRecords, apps: [], boards: [(sample.pages, list)], notices: [])
                shot("panel-board-sample", nil, MenuPanel(model: panelModel(idle, notices: [], level: level), store: store, fixed: data)
                    .frame(width: 360).background(Palette.raise))
            }
        }
        let apps = store.apps
        if let chat = apps.first(where: { $0.isChat && $0.approved }) ?? apps.first {
            shot("window-app", window, AppPage(app: .constant(chat), names: .constant(store.names), hooks: ManageHooks(), back: {})
                .background(Palette.paper).preferredColorScheme(.dark))
        }

        // The empty and problem states.
        shot("state-activity-empty", window, EmptyActivity(holdKey: key).background(Palette.paper))
        shot("state-apps-reading", window, ReadingApps(start: Date().addingTimeInterval(-4)).background(Palette.paper))
        shot("state-no-mic", window, CenterState(glyph: .micOff, tone: .amber, title: "earshot cannot hear you",
                                                 detail: "macOS turned off the microphone for earshot. Turn it on in Privacy settings, then come back.") {
            Button("Open Privacy settings") {}.buttonStyle(KeyStyle(.ink))
        }.background(Palette.paper))

        // The notes on screen.
        let notes: [(String, NoteContent)] = [
            ("note-listening", .listening),
            ("note-done", NoteContent.parse("→ Notes", ok: true)),
            ("note-typed", NoteContent.parse("typed · 12 words", ok: true)),
            ("note-failed", NoteContent.parse("✗ the search field did not show in 1200 ms", ok: false)),
            ("note-question", NoteContent.parse("not sure: two apps are close · 1: Notes · 2: Notion · say one or two", ok: false)),
            ("note-answer", NoteContent.answer(from: "Plugin", text: "Due today · Call the plumber, 5 pm · Pay the rent, 6 pm")),
        ]
        for (name, content) in notes {
            shot(name, CGSize(width: 560, height: 220), VStack {
                Spacer()
                NoteView(content: content, level: level, duration: content.kindKey == "pill" ? nil : 8)
                Spacer()
            }
            .frame(width: 560, height: 220)
            .background(Palette.night))
        }

        // The menu bar icon, black on white and white on black.
        let states: [(String, LiveState)] = [("ready", idle), ("hearing", hearing), ("paused", paused), ("needs-you", needs)]
        for (name, live) in states {
            let image = MenuBarIcon.image(live)
            shot("icon-\(name)", CGSize(width: 120, height: 44), HStack(spacing: 0) {
                Image(nsImage: image).renderingMode(.template).foregroundStyle(.black).frame(width: 60, height: 44).background(.white)
                Image(nsImage: image).renderingMode(.template).foregroundStyle(.white).frame(width: 60, height: 44).background(.black)
            })
        }
        return out
    }

    @MainActor static func panelView(_ live: LiveState, notices: [Notice], level: VoiceLevel, store: Store) -> some View {
        MenuPanel(model: panelModel(live, notices: notices, level: level), store: store)
            .frame(width: 360)
            .background(Palette.raise)
    }

    @MainActor static func panelModel(_ live: LiveState, notices: [Notice], level: VoiceLevel) -> PanelModel {
        PanelModel(live: live, mode: .constant(live.mode), startsAtLogin: .constant(true), level: level,
                   notices: { notices }, pause: {}, resume: {}, open: { _ in }, quit: {})
    }

    /// Made-up commands for the panel with a board.
    static let sampleRecords = [
        ActivityRecord(heard: "todo call the shop", intent: "Planner · todo", tier: .rules, ok: true, note: "sent to Planner", stages: [:]),
        ActivityRecord(heard: "open notes", intent: "→ Notes", tier: .rules, ok: true, note: "→ Notes · route: app name", stages: [:]),
        ActivityRecord(heard: "(9 words)", intent: "Type \"(9 words)\"", tier: .rules, ok: true, note: "typed", stages: [:]),
    ]

    /// Writes a board.json of made-up rows to `folder`/pages and returns its plugin pages. Nil if the write fails.
    static func sampleBoard(in folder: URL) -> (pages: PluginPages, board: Board)? {
        typealias R = Board.Row
        let late = [R(text: "Pay the rent", detail: "Home", when: "Wed", late: true, mark: "todo")]
        let today = [R(text: "Call the shop about the lamp", detail: "Home", when: "5 pm", mark: "todo"),
                     R(text: "Send the draft to the editor", detail: "Book", when: "6 pm", mark: "todo"),
                     R(text: "The tiler can start on Monday", detail: "Kitchen", mark: "note")]
        let tomorrow = [R(text: "Book the car service", when: "9 am", mark: "todo")]
        let board = Board(
            panel: Board.PanelList(title: "Today", rows: late + today, empty: "Nothing for today."),
            tabs: [
                Board.Tab(id: "today", title: "Today", sub: "1 late, 3 for today, 1 for tomorrow", date: "Sun 15 Nov", sections: [
                    Board.Section(title: "Late", tone: "late", rows: late),
                    Board.Section(title: "Today", rows: today),
                    Board.Section(title: "Tomorrow", rows: tomorrow),
                    Board.Section(title: "The last 7 days", numbers: [
                        Board.Number(label: "captured", value: 23), Board.Number(label: "done", value: 17),
                        Board.Number(label: "snoozed", value: 4), Board.Number(label: "dropped", value: 2),
                    ]),
                ], hint: "Say “done” or “snooze” with the words of a to-do."),
                Board.Tab(id: "all", title: "All open", sub: "5 open", sections: [Board.Section(title: "Home", rows: late + today)]),
            ])
        let pages = folder.appendingPathComponent("pages", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
            try JSONEncoder().encode(board).write(to: pages.appendingPathComponent(Board.fileName))
        } catch { return nil }
        let p = PluginPages(id: "sample", name: "Planner", folder: pages, settings: [],
                            settingsFile: folder.appendingPathComponent("settings.json"), hasIndex: false)
        guard let read = p.board else { return nil }
        return (p, read)
    }

    /// Draws a view in a window off the screen and writes it as PNG. `size` nil uses the size that the view needs.
    @MainActor static func render<V: View>(_ view: V, size: CGSize?, to url: URL) -> Bool {
        let host = NSHostingView(rootView: view.preferredColorScheme(.dark))
        let fit = size ?? host.fittingSize
        let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: fit.width, height: fit.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: fit)
        window.orderFrontRegardless()
        // Let the views appear, read their files and finish their first animation.
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }
}
