import AppKit
import SwiftUI

// The menu bar icon (design canvas "Note"): the brand ear from the site and the app icon, one color, 16 pt.
// The menu bar is one color, so a state is a small mark next to the ear, and the panel gives the reason.

public enum MenuBarIcon {
    /// The mark next to the ear.
    public enum Mark: Equatable, Sendable { case none, bars, dot, needsYou }

    /// The icon of a state. A template image, so macOS draws it in the color of the menu bar.
    @MainActor public static func image(_ live: LiveState) -> NSImage {
        let key = cacheKey(live)
        if let cached = cache[key] { return cached }
        let image: NSImage
        switch live.listen {
        case .paused: image = draw(glyph: .pause, mark: .none, alpha: 0.55)
        case .listening: image = draw(glyph: .ear, mark: .bars)
        case .followUp: image = draw(glyph: .ear, mark: .dot)
        case .textExpected: image = draw(glyph: .text, mark: .none)
        case .idle: image = draw(glyph: .ear, mark: live.needsYou ? .needsYou : .none)
        }
        cache[key] = image
        return image
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    private static func cacheKey(_ live: LiveState) -> String {
        "\(live.listen.rawValue)-\(live.needsYou)"
    }

    /// Draws the glyph on a 22 × 18 pt image: the ear at the left, room for the mark at the right.
    static func draw(glyph: GlyphKind, mark: Mark, alpha: CGFloat = 1) -> NSImage {
        let width: CGFloat = mark == .none ? 18 : 22
        let image = NSImage(size: NSSize(width: width, height: 18), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setAlpha(alpha)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            // The glyph on the 24 grid, scaled to 16 pt, 1 pt from the top.
            let k: CGFloat = 16 / 24
            let path = glyph.path.applying(CGAffineTransform(translationX: 1, y: 1).scaledBy(x: k, y: k))
            ctx.addPath(path.cgPath)
            ctx.setLineWidth((glyph == .ear ? 2.3 : 2.0) * k)
            ctx.strokePath()
            switch mark {
            case .none: break
            case .bars:
                // Three short bars at the right, of different heights.
                ctx.setLineWidth(1.5)
                for (i, h) in [CGFloat(4), 7, 5].enumerated() {
                    let x = 16.5 + CGFloat(i) * 2.2
                    ctx.move(to: CGPoint(x: x, y: 9 - h / 2))
                    ctx.addLine(to: CGPoint(x: x, y: 9 + h / 2))
                }
                ctx.strokePath()
            case .dot:
                ctx.fillEllipse(in: CGRect(x: 17, y: 11, width: 4, height: 4))
            case .needsYou:
                ctx.fillEllipse(in: CGRect(x: 16.5, y: 1.5, width: 5, height: 5))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
