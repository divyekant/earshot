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

    public init(seconds: Double = 2.0) { self.seconds = seconds }

    public func show(_ text: String, ok: Bool) {
        show(text, ok: ok, seconds: seconds)
    }

    /// Shows the note for `seconds`, for example 10 s for a question that the owner can answer.
    public func show(_ text: String, ok: Bool, seconds: Double) {
        DispatchQueue.main.async { [weak self] in self?.present(text, ok: ok, seconds: seconds) }
    }

    public func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.hideWork?.cancel()
            self?.panel?.orderOut(nil)
        }
    }

    private func present(_ text: String, ok: Bool, seconds: Double) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: NoteView(text: text, ok: ok))
        host.frame.size = host.fittingSize
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - host.fittingSize.width / 2, y: f.minY + 80))
        }
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
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
