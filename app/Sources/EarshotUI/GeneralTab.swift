import AppKit
import EarshotCore
import SwiftUI

struct GeneralTab: View {
    @Binding var settings: EarshotSettings
    let hooks: ManageHooks
    @State private var recording = false
    @State private var monitor: Any?
    @State private var jevKey = ""
    @State private var jevKeySaved = KeychainSecret.jev.exists

    var body: some View {
        Form {
            Section("Input") {
                Picker("Mode", selection: $settings.mode) {
                    Text("Hold key").tag(InputMode.hold)
                    Text("Always on").tag(InputMode.alwaysOn)
                }
                .pickerStyle(.segmented)
                if settings.mode == .alwaysOn {
                    Text("Say the wake phrase, then the command, for example \"\(settings.wakePhrase), open Notes\". For 5 s after a command, your voice can give the next command with no phrase. earshot never presses Send or does a risky action from always-on mode. The hold key also stays available.")
                        .font(.caption).foregroundStyle(.secondary)
                    WakeSection(settings: $settings, voice: hooks.voice)
                }
                Picker("Hold key", selection: holdKeyBinding) {
                    ForEach(HoldKeys.modifiers) { Text($0.name).tag(Optional($0.code)) }
                    if !isListedModifier { Text(HoldKeys.name(of: settings)).tag(Optional(settings.holdKeyCode)) }
                }
                HStack {
                    Button(recording ? "Press a key…" : "Record a different key") { recording ? stopRecording() : startRecording() }
                    if recording { Button("Cancel") { stopRecording() } }
                }
                if let w = HoldKeys.warning(code: settings.holdKeyCode, modifierOnly: settings.holdKeyIsModifierOnly,
                                            modifiers: settings.holdKeyModifiers) {
                    Text(w).font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Speech") {
                Picker("Speech engine", selection: $settings.engine) {
                    Text("Automatic (Apple)").tag(EngineChoice.auto)
                    Text("Apple").tag(EngineChoice.apple)
                    Text("Parakeet").tag(EngineChoice.parakeet)
                }
                if settings.engine != .apple {
                    TextField("Parakeet model file", text: $settings.parakeetModelPath,
                              prompt: Text("Empty: use the model file of Hex"))
                }
                TextField("Language", text: $settings.locale, prompt: Text("en_US"))
            }
            Section("When the rules are unsure") {
                Picker("Tier 2", selection: $settings.tier2) {
                    Text("Do nothing (all decisions on this Mac)").tag(Tier2.off)
                    Text("Ask Jev (cloud, text only)").tag(Tier2.jev)
                }
                if settings.tier2 == .jev {
                    Text("earshot sends the command words and a short list of labels to Jev as text. Audio stays on this Mac. If Jev does not answer in time, the rules result wins.")
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper("Wait for Jev: \(settings.tier2BudgetMs) ms", value: $settings.tier2BudgetMs, in: 200...1000, step: 100)
                    HStack {
                        SecureField("Jev key", text: $jevKey, prompt: Text(jevKeySaved ? "Saved in the Keychain" : "Paste the key"))
                        Button("Save") {
                            KeychainSecret.jev.write(jevKey)
                            jevKey = ""
                            jevKeySaved = KeychainSecret.jev.exists
                        }
                        .disabled(jevKey.isEmpty)
                        Button("Remove") {
                            KeychainSecret.jev.delete()
                            jevKeySaved = false
                        }
                        .disabled(!jevKeySaved)
                    }
                }
            }
            Section("When a click finds no target") {
                // D-10: a separate switch. "Ask Jev" (text only) never turns it on.
                Toggle("Jev sees the screen (cloud, sends a screenshot)", isOn: $settings.jevSeesScreen)
                if settings.jevSeesScreen {
                    Text("Only for the hold key. earshot sends one picture of the front window, with numbers on the elements, and the command words to Jev. Never on a sign-in, code or payment page. earshot checks the element under the point before it clicks, and never clicks a risky label. Audio stays on this Mac. It needs the Jev key and the Screen Recording permission.")
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper("Wait for Jev: \(settings.jevScreenBudgetMs) ms", value: $settings.jevScreenBudgetMs, in: 500...1500, step: 100)
                    if !jevKeySaved {
                        Text("Save the Jev key above first (choose \"Ask Jev\" to show the key field).")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Section("Behavior") {
                Toggle("Type dictated text into chats with other people", isOn: $settings.typeIntoOthers)
                Toggle("Show the note on screen", isOn: $settings.showFeedback)
                Toggle("Play sounds", isOn: $settings.playSounds)
                HStack {
                    Button("Show a test note") { hooks.feedback?.show("→ test note", ok: true) }
                        .disabled(hooks.feedback == nil)
                    if hooks.feedback == nil { NotConnected(what: "The note") }
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { stopRecording() }
    }

    private var isListedModifier: Bool {
        settings.holdKeyIsModifierOnly && HoldKeys.modifiers.contains { $0.code == settings.holdKeyCode }
    }

    private var holdKeyBinding: Binding<UInt32?> {
        Binding(get: { settings.holdKeyCode }, set: { code in
            guard let code, HoldKeys.modifiers.contains(where: { $0.code == code }) else { return }
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
                guard HoldKeys.isModifierKey(code), modifierIsDown(code: code, flags: event.modifierFlags) else { return nil }
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

    private func modifierIsDown(code: UInt32, flags: NSEvent.ModifierFlags) -> Bool {
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
