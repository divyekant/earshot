import EarshotCore
import SwiftUI

/// The rules of the wake phrase field (R-ON-1, D-11).
enum WakePhraseRule {
    /// A warning for a phrase that wakes earshot by mistake too often, or nil.
    static func warning(_ phrase: String) -> String? {
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
        VStack(alignment: .leading, spacing: 0) {
            Text("Teach earshot your voice").textStyle(.title, Palette.ink)
            Text("Press Record, then say “\(phrase)” in your normal voice, at your normal place. Do it \(needed) times. earshot keeps a voice summary and the sound pattern of the phrase on this Mac. It does not keep the audio.")
                .textStyle(.call, Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            HStack(spacing: 6) {
                ForEach(0..<needed, id: \.self) { i in
                    Capsule().fill(i < clips.count ? Palette.ink : Palette.fill).frame(height: 4)
                }
            }
            .padding(.top, 20)
            HStack {
                Text("\(min(clips.count, needed)) of \(needed) phrases").textStyle(.mono, Palette.ink3)
                Spacer()
                if busy { VoiceBars(count: 7, height: 16) }
            }
            .padding(.top, 8)
            if !message.isEmpty {
                Text(message).textStyle(.detail, Palette.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
            HStack(spacing: 10) {
                Spacer()
                Button(finished ? "Done" : "Cancel") { dismiss() }.buttonStyle(KeyStyle(.line))
                Button(busy ? "Listening…" : "Record") { record() }
                    .buttonStyle(KeyStyle(.ink))
                    .disabled(busy || finished || clips.count >= needed)
            }
            .padding(.top, 22)
        }
        .padding(24)
        .frame(width: 460)
        .background(Palette.paper)
        .preferredColorScheme(.dark)
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
