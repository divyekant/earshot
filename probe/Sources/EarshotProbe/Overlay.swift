import AppKit

/// A small note at the top right of the screen (R-FB-1).
/// It never takes keyboard focus and ignores the mouse.
@MainActor
final class Overlay {
    private let panel: NSPanel
    private let label: NSTextField

    init() {
        let size = NSSize(width: 560, height: 72)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let background = NSView(frame: NSRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.85).cgColor
        background.layer?.cornerRadius = 12
        panel.contentView = background

        label = NSTextField(wrappingLabelWithString: "")
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.frame = NSRect(x: 16, y: 8, width: size.width - 32, height: size.height - 16)
        background.addSubview(label)

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - size.width - 16, y: f.maxY - size.height - 16))
        }
    }

    func show(_ text: String) {
        label.stringValue = text
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}
