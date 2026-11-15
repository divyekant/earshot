import AppKit
import EarshotCore
import SwiftUI

// The Settings page (design canvas "Window: Settings"): the two ways to listen are two large cards, each group has
// one plain sentence, and the cloud group has a thin amber edge while a Jev setting is on. Each change saves at once:
// ManageView writes settings.json and tells the app.

struct SettingsPage: View {
    @Binding var settings: EarshotSettings
    let hooks: ManageHooks
    @State private var phrase = ""
    @State private var voiceStatus = ""
    @State private var teaching = false
    @State private var recording = false
    @State private var monitor: Any?
    @State private var jevKey = ""
    @State private var jevKeySaved = KeychainSecret.jev.exists
    @State private var locale = ""
    @State private var modelPath = ""

    var body: some View {
        PageFrame(top: 30) {
            PageTitle(title: "Settings", sub: "Changes save at once. Audio never leaves this Mac.")
            listening.padding(.top, 34)
            speech.padding(.top, 44)
            cloud.padding(.top, 44)
            feedback.padding(.top, 44)
            HStack(spacing: 8) {
                Glyph(.check, size: 14)
                Text("Saved · the command line can read and change the same settings:")
                Text("earshot settings").textStyle(.mono, Palette.ink2)
            }
            .textStyle(.detail, Palette.ink3)
            .padding(.top, 40)
        }
        .sheet(isPresented: $teaching) {
            if let voice = hooks.voice {
                TeachVoiceSheet(phrase: settings.wakePhrase, voice: voice) { Task { voiceStatus = await voice.status() } }
            }
        }
        .task {
            phrase = settings.wakePhrase
            locale = settings.locale
            modelPath = settings.parakeetModelPath
            // The status changes while the models download, so read it again every second while the page shows.
            while !Task.isCancelled, let voice = hooks.voice {
                voiceStatus = await voice.status()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .onDisappear { stopRecording() }
    }

    // MARK: How earshot listens

    private var listening: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupTitle("How earshot listens")
            HStack(alignment: .top, spacing: 14) {
                ModeCard(title: "Hold a key",
                         detail: "Hold \(HoldKeys.name(of: settings)), say the command, let go. The mic is open only while you hold the key.",
                         on: settings.mode == .hold, choose: { settings.mode = .hold }) {
                    Keycap(LiveState.capOnly(HoldKeys.capText(of: settings)), size: .big)
                }
                ModeCard(title: "Always on",
                         detail: "Say the wake phrase, then the command. For 5 s after it, say the next one with no phrase.",
                         on: settings.mode == .alwaysOn, choose: { settings.mode = .alwaysOn }) {
                    HStack(spacing: 14) {
                        VoiceBars(count: 7, height: 18)
                        (Text("“\(settings.wakePhrase), ").foregroundColor(Palette.ink) + Text("open notes”").foregroundColor(Palette.ink3))
                            .textStyle(TextStyle(13, 16, 500)).lineLimit(1)
                    }
                }
            }
            .padding(.top, 14)
            RowGroup {
                if settings.mode == .alwaysOn { alwaysOnRows }
                holdKeyRow(last: settings.mode == .hold)
                if settings.mode == .alwaysOn {
                    SettingRow("In always-on mode, earshot never presses Send",
                               detail: "Except when you say “send” alone, in your voice, within 5 s after earshot typed.", last: true) {
                        Glyph(.onMac).foregroundStyle(Palette.ink3)
                    }
                }
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder private var alwaysOnRows: some View {
        SettingRow("Wake phrase", detail: WakePhraseRule.warning(cleaned) ?? "Two or three words that you do not say often.",
                   detailTone: WakePhraseRule.warning(cleaned) == nil ? Palette.ink2 : Palette.amber) {
            Field(text: $phrase, prompt: WakePhrase.defaultPhrase, onCommit: savePhrase).frame(width: 200)
        }
        SettingRow("Your voice", detail: voiceLine) {
            if let voice = hooks.voice {
                Button("Forget") { Task { await voice.forget(); voiceStatus = await voice.status() } }
                    .buttonStyle(QuietStyle(TextStyle(12.5, 17, 500)))
                Button(voiceStatus.lowercased().contains("taught") || voiceStatus.lowercased().contains("profile") ? "Teach again" : "Teach")
                    { teaching = true }
                    .buttonStyle(KeyStyle(.line, small: true))
            } else {
                NotConnected(what: "The voice check")
            }
        }
        SettingRow("Keep the numbers of each turn for 7 days",
                   detail: "Numbers only, no audio. They help to tune the wake phrase. Turn off to delete them.") {
            Toggle("", isOn: $settings.recordTurns).labelsHidden().toggleStyle(SwitchStyle())
        }
    }

    private var voiceLine: String {
        voiceStatus.isEmpty ? "Reading the voice status…" : voiceStatus
    }

    private func holdKeyRow(last: Bool) -> some View {
        let warning = HoldKeys.warning(code: settings.holdKeyCode, modifierOnly: settings.holdKeyIsModifierOnly,
                                       modifiers: settings.holdKeyModifiers)
        return SettingRow("Hold key",
                          detail: warning ?? (recording ? "Press the key that you want to hold." :
                                                (settings.mode == .alwaysOn ? "It also works in always-on mode." : "A modifier key alone types nothing.")),
                          detailTone: warning == nil ? Palette.ink2 : Palette.amber, last: last) {
            Button(recording ? "Cancel" : "Record a key") { recording ? stopRecording() : startRecording() }
                .buttonStyle(QuietStyle(TextStyle(12.5, 17, 500)))
            Pick(selection: holdKeyBinding, options: holdKeyOptions)
        }
    }

    private var holdKeyOptions: [(value: UInt32, title: String)] {
        var out = HoldKeys.modifiers.map { ($0.code, $0.name) }
        if !isListedModifier { out.append((settings.holdKeyCode, HoldKeys.name(of: settings))) }
        return out
    }

    // MARK: Speech

    private var speech: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupTitle("Speech", sub: "earshot turns speech into text on this Mac.")
            RowGroup {
                SettingRow("Speech engine", detail: "Parakeet is more exact for names. Apple uses less memory.") {
                    Segmented(selection: $settings.engine, options: [(EngineChoice.auto, "Automatic"), (.apple, "Apple"), (.parakeet, "Parakeet")])
                }
                SettingRow("Language", detail: "A language code, for example en_US or en_GB.", last: settings.engine == .apple) {
                    Field(text: $locale, prompt: "en_US", mono: true) {
                        let t = locale.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty, t != settings.locale { settings.locale = t }
                    }
                    .frame(width: 120)
                }
                if settings.engine != .apple {
                    SettingRow("Parakeet model file",
                               detail: settings.parakeetModelPath.isEmpty ? "The model file of Hex, if it is on this Mac." : settings.parakeetModelPath,
                               last: true) {
                        if !settings.parakeetModelPath.isEmpty {
                            Button("Use Hex") { settings.parakeetModelPath = "" }.buttonStyle(QuietStyle(TextStyle(12.5, 17, 500)))
                        }
                        Button("Change") { chooseModel() }.buttonStyle(KeyStyle(.line, small: true))
                    }
                }
            }
            .padding(.top, 16)
        }
    }

    // MARK: Cloud

    private var cloudOn: Bool { settings.tier2 == .jev || settings.jevSeesScreen }

    private var cloud: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupTitle("Cloud", sub: "Both are off when you install earshot. Each one sends text or one picture to Jev, never audio.")
            RowGroup(edge: cloudOn ? Palette.amberEdge : Palette.rule) {
                HStack(spacing: 10) {
                    Glyph(.cloud, size: 14)
                    Text("Jev is a cloud model. earshot asks it only when the rules on this Mac are not sure.")
                }
                .textStyle(.call, Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14).padding(.bottom, 12)
                .overlay(alignment: .bottom) { Rule() }
                SettingRow("Ask Jev when earshot is not sure",
                           detail: settings.tier2 == .jev
                               ? "On · sends the command words and a short list of labels, as text · \(settings.tier2BudgetMs) ms at most"
                               : "Off · all decisions stay on this Mac",
                           detailTone: settings.tier2 == .jev ? Palette.amber : Palette.ink2) {
                    if settings.tier2 == .jev {
                        Pick(selection: $settings.tier2BudgetMs, options: stride(from: 300, through: 1000, by: 100).map { ($0, "\($0) ms") })
                    }
                    Toggle("", isOn: Binding(get: { settings.tier2 == .jev }, set: { settings.tier2 = $0 ? .jev : .off }))
                        .labelsHidden().toggleStyle(SwitchStyle())
                }
                if cloudOn || jevKeySaved {
                    HStack(spacing: 10) {
                        if jevKeySaved {
                            Text("Jev key · saved on this Mac, in the keychain").textStyle(TextStyle(12.5, 18, mono: true), Palette.ink2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Remove") { KeychainSecret.jev.delete(); jevKeySaved = false }
                                .buttonStyle(QuietStyle(TextStyle(12.5, 17, 500)))
                        } else {
                            Field(text: $jevKey, prompt: "Paste the Jev key", mono: true, secure: true)
                            Button("Save") {
                                KeychainSecret.jev.write(jevKey)
                                jevKey = ""
                                jevKeySaved = KeychainSecret.jev.exists
                            }
                            .buttonStyle(KeyStyle(.line, small: true))
                            .disabled(jevKey.isEmpty)
                        }
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) { Rule() }
                }
                // D-10: a separate switch. "Ask Jev" (text only) never turns it on.
                SettingRow("Jev sees the screen",
                           detail: settings.jevSeesScreen && !jevKeySaved
                               ? "Save the Jev key first. It also needs the Screen Recording permission."
                               : "Hold key only. Sends one picture of the front window. Never on a sign-in, code or payment page.",
                           detailTone: settings.jevSeesScreen && !jevKeySaved ? Palette.amber : Palette.ink2, last: true) {
                    if settings.jevSeesScreen {
                        Pick(selection: $settings.jevScreenBudgetMs, options: stride(from: 500, through: 1500, by: 100).map { ($0, "\($0) ms") })
                    }
                    Toggle("", isOn: $settings.jevSeesScreen).labelsHidden().toggleStyle(SwitchStyle())
                }
            }
            .padding(.top, 16)
        }
    }

    // MARK: Feedback

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupTitle("Feedback")
            RowGroup {
                SettingRow("Show the note on screen", detail: "A short line near the bottom of the screen after each command.") {
                    Button("Show a test note") { hooks.feedback?.show("→ Notes", ok: true) }
                        .buttonStyle(QuietStyle(TextStyle(12.5, 17, 500)))
                        .disabled(hooks.feedback == nil)
                    Toggle("", isOn: $settings.showFeedback).labelsHidden().toggleStyle(SwitchStyle())
                }
                SettingRow("Play sounds", detail: "A short tick when earshot starts to listen. One sound when a command is done, sent or failed.") {
                    Toggle("", isOn: $settings.playSounds).labelsHidden().toggleStyle(SwitchStyle())
                }
                SettingRow("Type dictated text into chats with other people",
                           detail: settings.typeIntoOthers ? "On · earshot types into any chat. It never presses Send by itself."
                                                           : "Off · earshot types only into your own notes and your own chat.",
                           last: true) {
                    Toggle("", isOn: $settings.typeIntoOthers).labelsHidden().toggleStyle(SwitchStyle())
                }
            }
            .padding(.top, 16)
        }
    }

    // MARK: Actions

    private var cleaned: String { WakePhrase.words(phrase).joined(separator: " ") }

    private func savePhrase() {
        guard !cleaned.isEmpty, cleaned != settings.wakePhrase else { return }
        settings.wakePhrase = cleaned
        phrase = cleaned
    }

    private func chooseModel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the Parakeet model file or its folder."
        if panel.runModal() == .OK, let url = panel.url { settings.parakeetModelPath = url.path }
    }

    private var isListedModifier: Bool {
        settings.holdKeyIsModifierOnly && HoldKeys.modifiers.contains { $0.code == settings.holdKeyCode }
    }

    private var holdKeyBinding: Binding<UInt32> {
        Binding(get: { settings.holdKeyCode }, set: { code in
            guard HoldKeys.modifiers.contains(where: { $0.code == code }) else { return }
            var s = settings
            HoldKeys.apply(code: code, modifiers: 0, to: &s)
            settings = s
        })
    }

    private func startRecording() {
        stopRecording()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let code = UInt32(event.keyCode)
            let flags = UInt32(truncatingIfNeeded: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
            if event.type == .flagsChanged {
                // Take a modifier key on press only. On release, its flag is no longer set.
                guard HoldKeys.isModifierKey(code), Self.modifierIsDown(code: code, flags: event.modifierFlags) else { return nil }
            }
            var s = settings
            HoldKeys.apply(code: code, modifiers: flags, to: &s)
            settings = s
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    static func modifierIsDown(code: UInt32, flags: NSEvent.ModifierFlags) -> Bool {
        switch code {
        case 58, 61: return flags.contains(.option)
        case 54, 55: return flags.contains(.command)
        case 59, 62: return flags.contains(.control)
        case 56, 60: return flags.contains(.shift)
        case 63: return flags.contains(.function)
        default: return false
        }
    }
}
