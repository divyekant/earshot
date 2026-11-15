import EarshotCore
import SwiftUI

// The menu bar panel (dk, 2026-11-15): daily use is in the panel. The window keeps the settings that the owner
// changes less often.

/// The text of one command in the panel, from an activity record. Pure, so the tests can check it.
public enum PanelText {
    /// True if the panel shows the record: a turn with words, or a command with an intent. Rejected wakes, dropped
    /// turns and turns with no words stay in the Activity page only.
    public static func shows(_ r: ActivityRecord) -> Bool {
        guard !r.stages.isEmpty else { return false }
        return !r.heard.isEmpty || (r.intent != "none" && !r.intent.isEmpty)
    }

    /// The first line: the words that earshot heard, in quotes. A dictation keeps no words in the log, so it uses
    /// the intent ("Type …").
    public static func title(_ r: ActivityRecord) -> String {
        r.heard.isEmpty ? r.intent : "“\(r.heard)”"
    }

    /// The second line in plain words: what earshot did, without the router details. The note of a record is, for
    /// example, "typed · route: focused text field · screen: …". The panel keeps the part before "· route:".
    public static func did(_ r: ActivityRecord) -> String {
        var text = r.note
        if let cut = text.range(of: " · route:") { text = String(text[..<cut.lowerBound]) }
        if text.hasPrefix("→ ") { text.removeFirst(2) }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { text = r.intent }
        guard let first = text.first else { return r.ok ? "Done" : "Not done" }
        return first.uppercased() + text.dropFirst()
    }

    /// The last `count` records that the panel shows, newest first.
    public static func recent(_ records: [ActivityRecord], count: Int = 4) -> [ActivityRecord] {
        Array(records.filter(shows).sorted { $0.at > $1.at }.prefix(count))
    }
}

/// The values and actions that the panel needs. EarshotApp gives them.
public struct PanelModel {
    public var listen: ListenState
    /// The SF Symbol of the state, the same as the menu bar icon.
    public var symbol: String
    /// The first line, for example "Waits for "hey atlas" or the hold key".
    public var listenLabel: String
    /// One line on the state of the parts, for example "Ready · apple · hold key" or why the speech engine does not run.
    public var status: String
    public var isPaused: Bool
    public var mode: Binding<InputMode>
    public var startsAtLogin: Binding<Bool>
    /// True if a cloud setting is on: "Ask Jev" or "Jev sees the screen".
    public var cloudOn: Bool
    public var pause: () -> Void
    public var resume: () -> Void
    public var openSettings: () -> Void
    public var quit: () -> Void

    public init(listen: ListenState, symbol: String, listenLabel: String, status: String, isPaused: Bool, mode: Binding<InputMode>,
                startsAtLogin: Binding<Bool>, cloudOn: Bool, pause: @escaping () -> Void, resume: @escaping () -> Void,
                openSettings: @escaping () -> Void, quit: @escaping () -> Void) {
        self.listen = listen; self.symbol = symbol; self.listenLabel = listenLabel; self.status = status; self.isPaused = isPaused
        self.mode = mode; self.startsAtLogin = startsAtLogin; self.cloudOn = cloudOn
        self.pause = pause; self.resume = resume; self.openSettings = openSettings; self.quit = quit
    }
}

/// The panel under the menu bar icon: the state, Pause, the mode, the last commands and the way to the settings.
public struct MenuPanel: View {
    let model: PanelModel
    let store: Store
    @State private var records: [ActivityRecord] = []

    public init(model: PanelModel, store: Store) {
        self.model = model
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Picker("Mode", selection: model.mode) {
                Text("Hold key").tag(InputMode.hold)
                Text("Always on").tag(InputMode.alwaysOn)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            recent
            footer
        }
        .padding(18)
        .frame(width: 360)
        .background(Quiet.background)
        .foregroundStyle(Quiet.text)
        .preferredColorScheme(.dark)
        .tint(Brand.accent)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.symbol).font(.system(size: 18)).frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isPaused ? "Paused" : "Listening").font(.system(size: 16, weight: .semibold))
                Text(model.listenLabel).font(.system(size: 12)).foregroundStyle(Quiet.dim).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(model.isPaused ? "Resume" : "Pause") { model.isPaused ? model.resume() : model.pause() }
                .buttonStyle(PillButtonStyle(filled: model.isPaused))
                .help(model.isPaused ? "Listen again now" : "Stop all input for 1 hour")
        }
    }

    @ViewBuilder private var recent: some View {
        let shown = PanelText.recent(records)
        VStack(alignment: .leading, spacing: 0) {
            GroupHeading(text: "Last commands").padding(.bottom, 4)
            if shown.isEmpty {
                Text("No commands yet. Hold the key and say “open Notes”.").font(.system(size: 13)).foregroundStyle(Quiet.dim)
                    .padding(.vertical, 8)
            }
            ForEach(shown) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(PanelText.title(r)).font(.system(size: 14)).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(r.at, format: .dateTime.hour().minute())
                        Text("·")
                        Text(PanelText.did(r)).foregroundStyle(r.ok ? Quiet.dim : Quiet.late).lineLimit(1)
                    }
                    .font(.system(size: 12)).foregroundStyle(Quiet.dim)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(Quiet.line).frame(height: 1) }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.cloudOn ? "Cloud on: Jev can get the command words" : "Cloud off · all on this Mac")
                .font(.system(size: 12)).foregroundStyle(model.cloudOn ? Color.orange : Quiet.dim)
            if !model.status.isEmpty && !model.status.hasPrefix("Ready") {
                Text(model.status).font(.system(size: 12)).foregroundStyle(Quiet.dim).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Toggle("Start at login", isOn: model.startsAtLogin).toggleStyle(.checkbox).font(.system(size: 12))
                Spacer()
                Button("Settings…", action: model.openSettings).buttonStyle(PillButtonStyle())
                Button("Quit", action: model.quit).buttonStyle(PillButtonStyle())
            }
        }
    }

    private func load() {
        records = PanelText.recent(ActivityLog(store: store).last(40))
    }
}
