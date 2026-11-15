import AppKit
import EarshotCore
import SwiftUI

// The plugins (design canvas "Window: Plugins", R-PL-4, docs/PLUGINS.md). A plugin is a separate program. earshot
// starts only a plugin that the owner approved, and gives it only the words after its lead words. A changed
// plugin.json waits for a new approval. Only the owner approves: this page has the one key for it.

/// The words of the Plugins page, as pure functions for the tests.
public enum PluginWords {
    /// What the plugin gets with each command, as lines. `text` is true for text that the plugin can keep.
    public static func gets(_ m: PluginManifest) -> [(glyph: GlyphKind, text: String, aside: String, tone: Tone)] {
        var out: [(GlyphKind, String, String, Tone)] = []
        out.append((.typed, "The words after its lead word", "as text, never audio", .plain))
        let window = ["app", "windowTitle", "url", "document"].filter { m.context.contains($0) }
        if !window.isEmpty {
            let words: [String: String] = ["app": "the front app", "windowTitle": "the window title",
                                           "url": "the page address", "document": "the document path"]
            out.append((.window, capital(list(window.compactMap { words[$0] })), "", .plain))
        }
        let text = ["selection", "pageText"].filter { m.context.contains($0) }
        if !text.isEmpty {
            let words: [String: String] = ["selection": "the text that you selected",
                                           "pageText": "the text of the web page in front, when it asks after your command"]
            out.append((.text, capital(list(text.compactMap { words[$0] })), "\(m.name) can keep it", .amber))
        }
        let unknown = m.context.filter { !PluginContract.contextKeys.contains($0) }
        for key in unknown { out.append((.more, key, "", .plain)) }
        if m.network.isEmpty {
            out.append((.onMac, "No network. \(m.name) says so in its file; earshot does not check it.", "", .quiet))
        } else {
            out.append((.cloud, "Network: " + m.network.joined(separator: ", "), "\(m.name) says so; earshot does not check it", .amber))
        }
        return out.map { (glyph: $0.0, text: $0.1, aside: $0.2, tone: $0.3) }
    }

    public enum Tone: Sendable { case plain, amber, quiet }

    /// A short summary of what the plugin gets: "Words, front window, selected text, page text".
    public static func getsShort(_ m: PluginManifest) -> String {
        var parts = ["Words"]
        if m.context.contains(where: { ["app", "windowTitle", "url", "document"].contains($0) }) { parts.append("front window") }
        if m.context.contains("selection") { parts.append("selected text") }
        if m.context.contains("pageText") { parts.append("page text") }
        if !m.network.isEmpty { parts.append("network") }
        return parts.joined(separator: ", ")
    }

    /// "a", "a and b", "a, b and c".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }

    static func capital(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// The settings of a plugin by their value: "6 rules: 4 alert, 1 list, 1 off".
    public static func settingsSummary(values: [String], noun: String) -> String {
        guard !values.isEmpty else { return "" }
        var counts: [(String, Int)] = []
        for v in values {
            if let i = counts.firstIndex(where: { $0.0 == v }) { counts[i].1 += 1 } else { counts.append((v, 1)) }
        }
        let parts = counts.sorted { $0.1 > $1.1 }.map { "\($0.1) \($0.0)" }.joined(separator: ", ")
        return "\(values.count) \(noun.lowercased()): \(parts)"
    }

    /// The commands of today that went to the plugin. The log names a hand-off "<plugin name> · <lead>".
    public static func today(_ records: [ActivityRecord], name: String, now: Date = Date(), calendar: Calendar = .current) -> Int {
        records.filter { calendar.isDate($0.at, inSameDayAs: now) && $0.intent.hasPrefix("\(name) · ") }.count
    }
}

struct PluginsPage: View {
    let store: Store
    let hooks: ManageHooks
    /// Opens the page of a plugin, at a tab (BoardPage.settingsID for the settings), or at its first tab.
    let open: (_ id: String, _ tab: String?) -> Void
    @State private var plugins: [PluginEntry] = []
    @State private var approvals: [String: String] = [:]
    @State private var records: [ActivityRecord] = []
    @State private var runs: [String: PluginRun] = [:]
    /// The plugins that the owner put aside with "Not now", while the window is open.
    @State private var later = Set<String>()
    /// The approved plugins whose "What it gets" the owner opened.
    @State private var unfolded = Set<String>()
    @State private var notes: [String: String] = [:]
    @State private var error = ""

    private var catalog: PluginCatalog { PluginCatalog(store: store) }

    var body: some View {
        PageFrame(top: 30) {
            PageTitle(title: "Plugins", sub: "A plugin is a separate program on this Mac. It gets only the words after its lead "
                      + "words, never audio. It answers with a note on screen.")
            if plugins.isEmpty {
                Text("No plugins yet. Put each plugin in its own folder, with a plugin.json file, in the plugins folder.")
                    .textStyle(.body, Palette.ink3).fixedSize(horizontal: false, vertical: true).padding(.top, 26)
            }
            ForEach(plugins) { p in
                Group {
                    if !p.problems.isEmpty {
                        problemCard(p)
                    } else if !p.approved && later.contains(p.id) {
                        laterRow(p)
                    } else if !p.approved {
                        waitingCard(p)
                    } else {
                        approvedCard(p)
                    }
                }
                .padding(.top, 22)
            }
            if !error.isEmpty { Text(error).textStyle(.detail, Palette.coral).padding(.top, 12) }
            HStack(spacing: 18) {
                Button("Open the plugins folder", action: openFolder).buttonStyle(QuietStyle())
                Button("Look for new plugins") { reload(); hooks.pluginsChanged?() }.buttonStyle(QuietStyle())
                Spacer()
                Text("plugin contract \(PluginContract.version)").textStyle(.mono, Palette.ink3)
            }
            .padding(.top, 26)
        }
        .onAppear(perform: reload)
        .task {
            while !Task.isCancelled {
                readRuns()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: Cards

    private func card<C: View>(edge: Color, @ViewBuilder _ content: () -> C) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) { content() }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Palette.hex(0x111110)))
            .overlay(shape.strokeBorder(edge, lineWidth: 1))
    }

    private func head<T: View>(_ p: PluginEntry, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 14) {
            Tile(p.manifest.name, size: 36, dim: p.approved && !p.on)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.manifest.name).textStyle(.head, Palette.ink)
                Text("\(p.id) · \(p.manifest.version) · \(p.manifest.leads.count) lead word\(p.manifest.leads.count == 1 ? "" : "s")")
                    .textStyle(.mono, Palette.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).textStyle(.label, Palette.ink3)
    }

    /// A plugin that waits for the owner: what it gets, its lead words, and the key to approve it.
    private func waitingCard(_ p: PluginEntry) -> some View {
        let changed = approvals[p.id] != nil
        return card(edge: Palette.amberEdge) {
            head(p) {
                HStack(spacing: 7) {
                    Dot(.amber)
                    Text(changed ? "Changed · waits for you" : "Waits for you").textStyle(TextStyle(12.5, 17, 600), Palette.amber)
                }
            }
            label("With each command, \(p.manifest.name) gets").padding(.top, 20)
            gets(p.manifest).padding(.top, 6)
            label("You start a command with").padding(.top, 16)
            leads(p).padding(.top, 10)
            Rule().padding(.top, 18)
            HStack(spacing: 10) {
                Text(changed
                     ? "\(p.manifest.name) changed its plugin file. Look at what it gets, then approve it again."
                     : "Only you can approve a plugin. If \(p.manifest.name) changes this list, it waits for you again.")
                    .textStyle(.detail, Palette.ink3).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Not now") { withAnimation(Motion.control) { _ = later.insert(p.id) } }
                    .buttonStyle(KeyStyle(.line, small: true))
                Button("Approve \(p.manifest.name)") { approve(p, true) }
                    .buttonStyle(KeyStyle(.ink, small: true))
            }
            .padding(.top, 14)
        }
    }

    private func laterRow(_ p: PluginEntry) -> some View {
        HStack(spacing: 10) {
            Dot(.amber)
            Text("\(p.manifest.name) waits for your approval.").textStyle(.call, Palette.ink2)
            Spacer()
            Button("Show") { withAnimation(Motion.control) { _ = later.remove(p.id) } }.buttonStyle(QuietStyle())
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.amberWash))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.amberEdge, lineWidth: 1))
    }

    private func problemCard(_ p: PluginEntry) -> some View {
        card(edge: Palette.coralEdge) {
            head(p) {
                Text("Cannot start").textStyle(TextStyle(12.5, 17, 600), Palette.coral)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(p.problems, id: \.self) { why in
                    Text(PluginWords.capital(why) + ".").textStyle(.call, Palette.ink2)
                }
            }
            .padding(.top, 14)
            Text("earshot starts a plugin only when its plugin.json has no problem. Fix the file, then look for new plugins.")
                .textStyle(.detail, Palette.ink3).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
        }
    }

    /// An approved plugin: On or Off, its state now, its lists and settings, and what it gets.
    private func approvedCard(_ p: PluginEntry) -> some View {
        let run = runs[p.id] ?? PluginRun(running: false)
        let pages = PluginPages.find(entries: [p], dataFolder: catalog.dataFolder).first
        return card(edge: run.stopped != nil && p.on ? Palette.coralEdge : Palette.rule) {
            head(p) {
                Segmented(selection: onBinding(p), options: [(true, "On"), (false, "Off")])
            }
            state(p, run).padding(.top, 14)
            VStack(spacing: 0) {
                if let pages, let board = pages.board, !board.tabs.isEmpty {
                    linkRow("\(p.manifest.name)’s lists", value: board.tabs.map(\.title).joined(separator: ", ")) { open(p.id, nil) }
                }
                if let pages, !pages.settings.isEmpty {
                    let noun = pages.board?.settingsTab ?? "Settings"
                    let file = PluginSettingsFile(url: pages.settingsFile)
                    linkRow(noun, value: PluginWords.settingsSummary(values: pages.settings.map(file.value), noun: noun)) {
                        open(p.id, BoardPage.settingsID)
                    }
                }
                let shows = unfolded.contains(p.id)
                Button { withAnimation(Motion.control) { if shows { unfolded.remove(p.id) } else { unfolded.insert(p.id) } } } label: {
                    HStack(spacing: 10) {
                        Text("What \(p.manifest.name) gets").textStyle(.body, Palette.ink)
                        Spacer()
                        Text(PluginWords.getsShort(p.manifest)).textStyle(.detail, Palette.ink3)
                        Glyph(shows ? .chevronDown : .chevronRight, size: 13).foregroundStyle(Palette.ink4)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if shows {
                    VStack(alignment: .leading, spacing: 10) {
                        gets(p.manifest)
                        leads(p)
                    }
                    .padding(.bottom, 10)
                    .transition(.opacity)
                }
            }
            .padding(.top, 12)
            Rule().padding(.top, 6)
            HStack(spacing: 16) {
                Text(notes[p.id] ?? "Approved by you.").textStyle(.detail, Palette.ink3)
                Spacer()
                Button("Restart") { restart(p) }.buttonStyle(QuietStyle(TextStyle(12.5, 17, 500)))
                    .disabled(hooks.restartPlugin == nil || !p.on)
                Button("Remove approval") { approve(p, false) }.buttonStyle(QuietStyle(TextStyle(12.5, 17, 500)))
            }
            .padding(.top, 14)
        }
    }

    @ViewBuilder private func state(_ p: PluginEntry, _ run: PluginRun) -> some View {
        let count = PluginWords.today(records, name: p.manifest.name)
        if !p.on {
            Text("Off. \(p.manifest.name) does not run, and its lead words do nothing. Its data stays in its folder.")
                .textStyle(.call, Palette.ink3).fixedSize(horizontal: false, vertical: true)
        } else if let stopped = run.stopped {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Glyph(.failed, size: 14).foregroundStyle(Palette.coral)
                    Text("\(p.manifest.name) stopped").textStyle(TextStyle(13.5, 19, 600), Palette.coral)
                }
                Text("\(stopped) Your data is safe in its folder.").textStyle(.call, Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Open its folder") { NSWorkspace.shared.open(catalog.dataFolder.appendingPathComponent(p.id)) }
                        .buttonStyle(KeyStyle(.line, small: true))
                    Button("Start again") { restart(p) }.buttonStyle(KeyStyle(.ink, small: true))
                        .disabled(hooks.restartPlugin == nil)
                }
            }
        } else {
            HStack(spacing: 18) {
                HStack(spacing: 7) {
                    Dot(run.running ? .live : .still)
                    Text(run.running ? (run.since.map { "Running since \(MenuPanel.time($0))" } ?? "Running")
                         : "Starts with your next command").textStyle(.call, Palette.ink2)
                }
                fact("\(count)", "command\(count == 1 ? "" : "s") today")
                fact("0", "problems")
            }
        }
    }

    private func fact(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).textStyle(TextStyle(13, 18, 500, mono: true), Palette.ink)
            Text(label).textStyle(.call, Palette.ink2)
        }
    }

    private func linkRow(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).textStyle(.body, Palette.ink)
                Spacer()
                Text(value).textStyle(.detail, Palette.ink3).lineLimit(1)
                Glyph(.chevronRight, size: 13).foregroundStyle(Palette.ink4)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func gets(_ m: PluginManifest) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(PluginWords.gets(m).enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Glyph(line.glyph, size: 14)
                        .foregroundStyle(line.tone == .amber ? Palette.amber : (line.tone == .quiet ? Palette.ink4 : Palette.ink2))
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                    (Text(line.text).foregroundColor(line.tone == .quiet ? Palette.ink3 : Palette.ink)
                        + Text(line.aside.isEmpty ? "" : " · \(line.aside)")
                        .foregroundColor(line.tone == .amber ? Palette.amber : Palette.ink3))
                        .textStyle(TextStyle(13.5, 19))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func leads(_ p: PluginEntry) -> some View {
        let refused = p.manifest.leads.compactMap { lead in hooks.leadRefusal?(lead).map { (lead, $0) } }
        let used = p.manifest.leads.filter { lead in !refused.contains { $0.0 == lead } }
        let first = Array(used.prefix(10))
        return VStack(alignment: .leading, spacing: 8) {
            Flow(spacing: 6, lineSpacing: 6) {
                ForEach(first, id: \.self) { lead in
                    Text(lead).textStyle(TextStyle(12.5, 16), Palette.ink)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.raise2))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
                }
                if used.count > first.count {
                    Text("and \(used.count - first.count) more").textStyle(TextStyle(12.5, 16), Palette.ink3)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .help(used.dropFirst(first.count).joined(separator: ", "))
                }
            }
            ForEach(Array(refused.enumerated()), id: \.offset) { _, item in
                Text("“\(item.0)” is not used: \(item.1).").textStyle(.detail, Palette.coral)
            }
        }
    }

    // MARK: Changes

    private func onBinding(_ p: PluginEntry) -> Binding<Bool> {
        Binding(get: { p.on }, set: { on in
            do {
                try catalog.setOn(p.id, on)
                error = ""
            } catch {
                self.error = "Could not turn \(p.manifest.name) \(on ? "on" : "off"): \(error.localizedDescription)"
            }
            reload()
            hooks.pluginsChanged?()
        })
    }

    private func approve(_ p: PluginEntry, _ on: Bool) {
        do {
            try catalog.setApproved(p, on)
            error = ""
        } catch {
            self.error = "Could not save the approval: \(error.localizedDescription)"
        }
        withAnimation(Motion.control) { reload() }
        hooks.pluginsChanged?()
    }

    private func restart(_ p: PluginEntry) {
        guard let restart = hooks.restartPlugin else { return }
        let why = restart(p.id)
        notes[p.id] = why.map { "Did not start: \($0)." } ?? "Started again at \(MenuPanel.time(Date()))."
        readRuns()
    }

    private func reload() {
        plugins = catalog.scan()
        approvals = catalog.approvals
        records = ActivityLog(store: store).last(400)
        readRuns()
    }

    private func readRuns() {
        guard let read = hooks.pluginRun else { return }
        var out: [String: PluginRun] = [:]
        for p in plugins where p.approved { out[p.id] = read(p.id) }
        if out != runs { runs = out }
    }

    private func openFolder() {
        try? FileManager.default.createDirectory(at: catalog.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(catalog.folder)
    }
}
