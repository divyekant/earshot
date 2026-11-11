import AppKit
import EarshotCore
import SwiftUI

/// The small note on screen (R-FB-1), for example "→ Slack · Ravi".
/// The panel floats above other windows, takes no focus and lets clicks pass through, so it never changes the front app.
public final class FeedbackNote: FeedbackSink {
    /// How long the note stays on screen.
    public var seconds: Double
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    /// The level of the open turn, while the note shows "Listening". Nil when the note shows other text.
    private var listening: ListeningLevel?

    public init(seconds: Double = 2.0) { self.seconds = seconds }

    public func show(_ text: String, ok: Bool) {
        show(text, ok: ok, seconds: seconds)
    }

    /// Shows the note for `seconds`, for example 10 s for a question that the owner can answer.
    public func show(_ text: String, ok: Bool, seconds: Double) {
        DispatchQueue.main.async { [weak self] in self?.present(text, ok: ok, seconds: seconds) }
    }

    /// Shows "Listening" with a level bar until `endListening` or the next note (dk, 2026-11-11: the note must stay for
    /// the whole turn, from the wake to the end). It does nothing if the note shows "Listening" already.
    public func showListening() {
        DispatchQueue.main.async { [weak self] in
            guard let self, listening == nil else { return }
            let level = ListeningLevel()
            listening = level
            put(NoteHost(rootView: AnyView(ListeningView(level: level))))
            hideWork?.cancel()
        }
    }

    /// The level of the open turn: the loudest frame of the last 100 ms, in dB above the noise floor.
    public func listeningLevel(_ dbAboveFloor: Double) {
        DispatchQueue.main.async { [weak self] in self?.listening?.set(dbAboveFloor) }
    }

    /// Hides the note if it still shows "Listening". A result note that took its place stays.
    public func endListening() {
        DispatchQueue.main.async { [weak self] in
            guard let self, listening != nil else { return }
            listening = nil
            hideWork?.cancel()
            panel?.orderOut(nil)
        }
    }

    public func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.listening = nil
            self?.hideWork?.cancel()
            self?.panel?.orderOut(nil)
        }
    }

    private func present(_ text: String, ok: Bool, seconds: Double) {
        listening = nil
        put(NoteHost(rootView: AnyView(NoteView(text: text, ok: ok))))
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// Puts a view in the panel, at the bottom center of the main screen, and shows the panel.
    private func put(_ host: NoteHost) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        host.frame.size = host.fittingSize
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - host.fittingSize.width / 2, y: f.minY + 80))
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return p
    }
}

struct NoteView: View {
    let text: String
    let ok: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(text).font(.system(size: 15, weight: .medium)).lineLimit(2)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }
}

typealias NoteHost = NSHostingView<AnyView>

/// The level bar of the "Listening" note. Used only on the main thread.
final class ListeningLevel: ObservableObject {
    /// 0 is the noise floor, 1 is 30 dB or more above it.
    @Published private(set) var value: Double = 0

    func set(_ dbAboveFloor: Double) {
        let next = min(1, max(0, dbAboveFloor / 30))
        // Rise at once, fall slowly, so that the bar is easy to read.
        value = next >= value ? next : value * 0.6 + next * 0.4
    }
}

struct ListeningView: View {
    @ObservedObject var level: ListeningLevel
    private let bars = 5
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "ear.fill").foregroundStyle(.blue)
            Text("Listening").font(.system(size: 15, weight: .medium))
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    let on = level.value * Double(bars) > Double(i)
                    Capsule()
                        .fill(on ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(width: 4, height: 6 + CGFloat(i) * 3)
                }
            }
            .frame(height: 18)
            .animation(.easeOut(duration: 0.1), value: level.value)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }
}
