import AppKit
import EarshotCore
import SwiftUI

/// The small note on screen (R-FB-1, design canvas "Note"): bottom center, 80 pt above the Dock. It floats above
/// other windows, takes no focus and lets clicks pass through, so it never changes the front app.
/// The note rises 12 pt and fades in over 300 ms. The listening note turns into the result in place.
public final class FeedbackNote: FeedbackSink {
    /// How long a done note stays on screen. A failed note stays 1 s longer.
    public var seconds: Double
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    /// The model of the note view. Used on the main thread only.
    private let model = NoteModel()

    public init(seconds: Double = 2.0) { self.seconds = seconds }

    public func show(_ text: String, ok: Bool) {
        show(text, ok: ok, seconds: ok ? seconds : seconds + 1)
    }

    /// Shows the note for `seconds`, for example 10 s for a question that the owner can answer.
    public func show(_ text: String, ok: Bool, seconds: Double) {
        let content = NoteContent.parse(text, ok: ok)
        onMain { $0.present(content, seconds: seconds) }
    }

    /// Shows the answer of a plugin: a card with its list, or a pill for a short text.
    public func showAnswer(from name: String, text: String, seconds: Double) {
        let content = NoteContent.answer(from: name, text: text)
        onMain { $0.present(content, seconds: seconds) }
    }

    /// Shows "Listening" with the voice bars until `endListening` or the next note (dk, 2026-11-11: the note stays
    /// for the whole turn, from the wake to the end). It does nothing if the note shows "Listening" already.
    public func showListening() {
        onMain { note in
            guard note.model.content != .listening || !note.model.visible else { return }
            note.hideWork?.cancel()
            note.model.level.set(dbAboveFloor: 0)
            note.present(.listening, seconds: nil)
        }
    }

    /// The level of the open turn: the loudest frame of the last 100 ms, in dB above the noise floor.
    public func listeningLevel(_ dbAboveFloor: Double) {
        onMain { $0.model.level.set(dbAboveFloor: dbAboveFloor) }
    }

    /// The voice level, for the panel orb.
    @MainActor public var level: VoiceLevel { model.level }

    /// Hides the note if it still shows "Listening". A result note that took its place stays.
    public func endListening() {
        onMain { note in
            guard note.model.content == .listening, note.model.visible else { return }
            note.fadeOut()
        }
    }

    public func hide() {
        onMain { $0.fadeOut() }
    }

    /// Runs `work` on the main thread, while the note exists.
    private func onMain(_ work: @escaping @MainActor (FeedbackNote) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { if let self { work(self) } }
        }
    }

    @MainActor private func present(_ content: NoteContent, seconds: Double?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let size = NoteModel.stage
            panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + 80 - NoteModel.lift, width: size.width, height: size.height),
                           display: false)
        }
        panel.orderFrontRegardless()
        model.duration = seconds
        model.shownAt = Date()
        withAnimation(Motion.note) {
            model.content = content
            model.visible = true
        }
        hideWork?.cancel()
        guard let seconds else { return }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.fadeOut() } }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    @MainActor private func fadeOut() {
        hideWork?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { model.visible = false }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.model.visible else { return }
                self.panel?.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    @MainActor private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: NoteModel.stage), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: NoteStage(model: model))
        host.frame = NSRect(origin: .zero, size: NoteModel.stage)
        // A clear layer, so that no part of the stage around the note can show as a dark area.
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        host.layer?.isOpaque = false
        p.contentView = host
        return p
    }
}

/// The state of the note. Used on the main thread only.
final class NoteModel: ObservableObject {
    /// The clear area of the panel. The note sits at its bottom center, so it can grow and move without a new frame.
    static let stage = CGSize(width: 720, height: 360)
    /// The clear room around the note, inside the view that fades. SwiftUI draws a fading view into its own layer,
    /// and that layer ends at the frame of the view. Without this room, the dark shadow showed as a black rectangle
    /// behind the round note while it faded in or out (Mac check 2026-11-15).
    static let shadowRoom: CGFloat = 40
    /// The note starts 12 pt lower and rises.
    static let lift: CGFloat = 12

    @Published var content: NoteContent = .listening
    @Published var visible = false
    var duration: Double?
    var shownAt = Date()
    let level = VoiceLevel()
}

/// The clear stage with the note at its bottom center.
struct NoteStage: View {
    @ObservedObject var model: NoteModel
    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if model.visible {
                NoteView(content: model.content, level: model.level, duration: model.duration, shownAt: model.shownAt)
                    .padding(EdgeInsets(top: NoteModel.shadowRoom, leading: NoteModel.shadowRoom,
                                        bottom: NoteModel.lift + 24, trailing: NoteModel.shadowRoom))
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: NoteModel.lift)), removal: .opacity))
                    .id(model.content.kindKey)
            }
        }
        .frame(width: NoteModel.stage.width, height: NoteModel.stage.height)
        .animation(Motion.note, value: model.content)
    }
}

extension NoteContent {
    /// The pills share one key, so a pill changes in place. A card is a new note.
    var kindKey: String {
        switch self {
        case .pill, .listening: return "pill"
        case .question: return "question"
        case .answer: return "answer"
        }
    }
}

/// The note itself: a pill or a card.
struct NoteView: View {
    let content: NoteContent
    let level: VoiceLevel
    var duration: Double?
    var shownAt = Date()

    var body: some View {
        switch content {
        case .listening:
            pill {
                Glyph(.ear).foregroundStyle(Palette.ink)
                Text("Listening").textStyle(.note, Palette.ink)
                VoiceBars(count: 12, height: 18, level: level).padding(.leading, 4)
            }
        case let .pill(glyph, text, aside, failed):
            pill {
                Glyph(glyph).foregroundStyle(failed ? Palette.coral : Palette.ink)
                (Text(text).foregroundColor(Palette.ink)
                    + Text(aside.isEmpty ? "" : " · \(aside)").foregroundColor(Palette.ink3).font(Typeface.font(TextStyle(14, 20))))
                    .textStyle(.note)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)
            }
        case let .question(title, question, choices, hint):
            card(width: 380, top: title, glyph: .notSure, tone: Palette.amber) {
                Text(question).textStyle(.noteQuestion, Palette.ink).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(choices.prefix(4).enumerated()), id: \.offset) { i, choice in
                    HStack(spacing: 10) {
                        Text("\(i + 1)").textStyle(TextStyle(11, 14, mono: true), Palette.ink2)
                            .frame(width: 20, height: 20)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.raise2))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                        Text(choice).textStyle(TextStyle(14, 20, 450), Palette.ink).lineLimit(1)
                    }
                    .padding(.top, 7)
                }
                Text(hint).textStyle(.small, Palette.ink3).padding(.top, 9)
            }
        case let .answer(from, text, items):
            card(width: items.isEmpty ? 380 : 320, top: from, glyph: .plugin, tone: Palette.ink3) {
                if !text.isEmpty {
                    Text(text).textStyle(.noteQuestion, Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(item.text).textStyle(TextStyle(13.5, 20), Palette.ink).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(item.when).textStyle(TextStyle(11.5, 20, mono: true), item.late ? Palette.coral : Palette.ink3).lineLimit(1)
                        }
                        .padding(.vertical, 5)
                        .overlay(alignment: .top) { if i > 0 { Rule() } }
                    }
                }
                .padding(.top, text.isEmpty ? 0 : 2)
            }
        }
    }

    private func pill<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 10) { c() }
            .padding(.leading, 14).padding(.trailing, 16)
            .frame(height: 42)
            .background(Capsule().fill(Palette.raise.opacity(0.96)))
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 0.5)
            .shadow(color: .black.opacity(0.85), radius: 20, y: 18)
            .fixedSize()
    }

    private func card<C: View>(width: CGFloat, top: String, glyph: GlyphKind, tone: Color, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Glyph(glyph, size: 14).foregroundStyle(tone)
                Text(top).textStyle(TextStyle(12, 16, 500), Palette.ink3)
            }
            .padding(.bottom, 6)
            c()
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
        .frame(width: width, alignment: .leading)
        .overlay(alignment: .bottomLeading) {
            if let duration {
                // The time left to answer, as a line that empties.
                TimelineView(.animation) { context in
                    let left = max(0, 1 - context.date.timeIntervalSince(shownAt) / max(0.1, duration))
                    Rectangle().fill(Palette.ink.opacity(0.3)).frame(width: width * left, height: 2)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.raise.opacity(0.96)))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 0.5)
        .shadow(color: .black.opacity(0.85), radius: 20, y: 18)
    }
}
