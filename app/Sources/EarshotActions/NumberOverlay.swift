import AppKit
import EarshotCore

// "Show numbers" (R-CL-3): a number next to each element of the last screen read.
// The number n marks the element with the id "e<n>", so "click 3" is a click on "e3".
// The overlay never takes keyboard focus and ignores the mouse, so a click goes to the app below.

@MainActor
final class NumberOverlay {
    private var panels: [NSPanel] = []
    private(set) var shown = false

    static let badge = CGSize(width: 26, height: 16)

    func show(_ elements: [ScreenElement]) {
        hide()
        let mainHeight = Double(NSScreen.screens.first?.frame.height ?? 0)
        for screen in NSScreen.screens {
            let sf = screen.frame
            var marks: [(String, CGPoint)] = []
            for e in elements {
                guard let n = Int(e.id.dropFirst()), e.id.hasPrefix("e") else { continue }
                let f = Frame(x: e.x, y: e.y, w: e.w, h: e.h)
                let origin = ActionRules.badgeOrigin(element: f, badge: Self.badge, mainScreenHeight: mainHeight, screenOrigin: sf.origin)
                guard origin.x >= 0, origin.y >= 0, origin.x < sf.width, origin.y < sf.height else { continue }
                marks.append(("\(n)", origin))
            }
            guard !marks.isEmpty else { continue }
            let panel = NSPanel(contentRect: sf, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.contentView = BadgeView(frame: NSRect(origin: .zero, size: sf.size), marks: marks)
            panel.setFrame(sf, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        shown = true
    }

    func hide() {
        for p in panels { p.orderOut(nil) }
        panels.removeAll()
        shown = false
    }
}

private final class BadgeView: NSView {
    let marks: [(String, CGPoint)]

    init(frame: NSRect, marks: [(String, CGPoint)]) {
        self.marks = marks
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        for (text, origin) in marks {
            let size = (text as NSString).size(withAttributes: attributes)
            let rect = NSRect(x: origin.x, y: origin.y, width: max(NumberOverlay.badge.width, size.width + 8), height: NumberOverlay.badge.height)
            NSColor(calibratedRed: 1, green: 0.85, blue: 0.2, alpha: 0.95).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            NSColor.black.withAlphaComponent(0.6).setStroke()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).stroke()
            (text as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
        }
    }
}
