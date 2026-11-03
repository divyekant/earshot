import EarshotCore
import SwiftUI

/// The wake phrase and the voice enrolment of always-on mode, in the General tab (R-ON-1, R-ON-3, D-11).
struct WakeSection: View {
    @Binding var settings: EarshotSettings
    let voice: VoiceHooks?
    @State private var phrase = ""
    @State private var status = ""
    @State private var teaching = false

    var body: some View {
        Group {
            HStack {
                TextField("Wake phrase", text: $phrase, prompt: Text(WakePhrase.defaultPhrase))
                    .onSubmit { savePhrase() }
                Button("Save") { savePhrase() }
                    .disabled(cleaned.isEmpty || cleaned == settings.wakePhrase)
            }
            if let warning = Self.phraseWarning(cleaned) {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
            if let voice {
                Text(status.isEmpty ? "Reading the voice status…" : status)
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Teach earshot your voice…") { teaching = true }
                    Button("Forget my voice") { Task { await voice.forget(); status = await voice.status() } }
                }
            } else {
                NotConnected(what: "The voice check")
            }
        }
        .sheet(isPresented: $teaching) {
            if let voice {
                TeachVoiceSheet(phrase: settings.wakePhrase, voice: voice) { Task { status = await voice.status() } }
            }
        }
        .task {
            phrase = settings.wakePhrase
            // The status changes while the models download, so read it again every second while the tab shows.
            while !Task.isCancelled, let voice {
                status = await voice.status()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private var cleaned: String { WakePhrase.words(phrase).joined(separator: " ") }

    private func savePhrase() {
        guard !cleaned.isEmpty, cleaned != settings.wakePhrase else { return }
        var s = settings
        s.wakePhrase = cleaned
        settings = s
        phrase = cleaned
    }

    /// A warning for a phrase that wakes earshot by mistake too often, or nil.
    static func phraseWarning(_ phrase: String) -> String? {
        let words = WakePhrase.words(phrase)
        if words.isEmpty { return nil }
        if words.count < 2 { return "One word wakes earshot by mistake more often. Use two or more words." }
        if words.count > 4 { return "A long phrase is slow to say. Use two to four words." }
        return nil
    }
}

/// Records the enrolment phrases, one at a time, and makes the voice profile.
struct TeachVoiceSheet: View {
    let phrase: String
    let voice: VoiceHooks
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var clips: [[Float]] = []
    @State private var busy = false
    @State private var message = ""
    @State private var finished = false

    private var needed: Int { WakePhrase.enrolmentSamples }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teach earshot your voice").font(.headline)
            Text("Press Record, then say \"\(phrase)\" in your normal voice, at your normal place. Do it \(needed) times. earshot keeps a voice summary and the sound pattern of the phrase on this Mac. It does not keep the audio.")
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(clips.count), total: Double(needed))
            Text("\(clips.count) of \(needed) phrases").font(.caption)
            if !message.isEmpty {
                Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(busy ? "Listening…" : "Record") { record() }
                    .disabled(busy || finished || clips.count >= needed)
                Spacer()
                Button(finished ? "Done" : "Cancel") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func record() {
        busy = true
        message = ""
        Task {
            do {
                let clip = try await voice.record()
                clips.append(clip)
                if clips.count >= needed {
                    message = "Making the voice summary…"
                    message = try await voice.teach(phrase, clips)
                    clips.removeAll()
                    clips = Array(repeating: [], count: needed)  // a full bar
                    finished = true
                    done()
                }
            } catch {
                message = error.localizedDescription
                if clips.count >= needed { clips.removeAll() }
            }
            busy = false
        }
    }
}
