import AppKit
import SwiftUI

/// earshot brand colors, from assets/brand/README.md.
public enum Brand {
    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    public static let tileTop = hex(0x3A2FA8)
    public static let tileBottom = hex(0x0E0B2E)
    public static let barTop = hex(0xFFFFFF)
    public static let barBottom = hex(0xC4BAFF)
    public static let cursorTop = hex(0xFFD978)
    public static let cursorBottom = hex(0xFF9A3C)
    public static let ink = hex(0x14112E)
    /// The tint of the window controls. A lighter violet in dark mode, so the controls keep their contrast.
    public static let accent = Color(nsColor: NSColor(name: "earshotAccent") { look in
        look.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x9A / 255, green: 0x8F / 255, blue: 0xFF / 255, alpha: 1)
            : NSColor(srgbRed: 0x3A / 255, green: 0x2F / 255, blue: 0xA8 / 255, alpha: 1)
    })

    /// The version from Info.plist, or nil for a build that is not an app bundle (swift run, tests).
    public static var version: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
}

/// The earshot mark as vector shapes: four voice bars, then the text cursor.
/// The shapes are the same as in assets/brand/mark.svg and glyph.svg (1024 canvas, tile at 100,100, 824 wide).
/// SwiftUI draws them, so the mark is sharp at every size, and the module needs no resource file.
public struct EarshotMark: View {
    /// Draw the tile behind the mark. Without the tile, the bars and the cursor use `glyph`, as glyph.svg does.
    var tile: Bool
    var glyph: Color

    public init(tile: Bool = true, glyph: Color = .primary) { self.tile = tile; self.glyph = glyph }

    public var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let k = side / 824
            let toView = CGAffineTransform(scaleX: k, y: k).translatedBy(x: -100, y: -100)
            func path(_ r: MarkShapes.Bar) -> Path {
                Path(roundedRect: r.rect, cornerRadius: r.rect.width / 2).applying(toView)
            }
            guard tile else {
                for b in MarkShapes.bars + [MarkShapes.cursor] { ctx.fill(path(b), with: .color(glyph)) }
                return
            }
            let tileRect = CGRect(x: 0, y: 0, width: side, height: side)
            let tilePath = Path(roundedRect: tileRect, cornerRadius: 0.2245 * side, style: .continuous)
            ctx.fill(tilePath, with: .linearGradient(Gradient(colors: [Brand.tileTop, Brand.tileBottom]),
                                                     startPoint: CGPoint(x: 0.15 * side, y: 0),
                                                     endPoint: CGPoint(x: 0.85 * side, y: side)))
            ctx.fill(tilePath, with: .radialGradient(Gradient(colors: [.white.opacity(0.18), .white.opacity(0)]),
                                                     center: CGPoint(x: 0.3 * side, y: 0.12 * side),
                                                     startRadius: 0, endRadius: 0.75 * side))
            let barTop = CGPoint(x: 0, y: (286 - 100) * k), barBottom = CGPoint(x: 0, y: (738 - 100) * k)
            for b in MarkShapes.bars {
                ctx.fill(path(b), with: .linearGradient(Gradient(colors: [Brand.barTop, Brand.barBottom]),
                                                        startPoint: barTop, endPoint: barBottom))
            }
            let c = path(MarkShapes.cursor)
            var glow = ctx
            glow.addFilter(.blur(radius: 16 * k))
            glow.fill(c, with: .color(Brand.cursorBottom.opacity(0.55)))
            ctx.fill(c, with: .linearGradient(Gradient(colors: [Brand.cursorTop, Brand.cursorBottom]),
                                              startPoint: CGPoint(x: 0, y: c.boundingRect.minY),
                                              endPoint: CGPoint(x: 0, y: c.boundingRect.maxY)))
            ctx.stroke(tilePath.applying(CGAffineTransform(translationX: side / 2, y: side / 2).scaledBy(x: 0.9964, y: 0.9964)
                        .translatedBy(x: -side / 2, y: -side / 2)),
                       with: .color(.white.opacity(0.16)), lineWidth: max(0.5, 3 * k))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("earshot")
    }
}

/// The shapes of the mark in SVG coordinates (y goes down). Each is a rounded bar: corner radius is half the width.
enum MarkShapes {
    struct Bar { var rect: CGRect }
    static let bars = [
        Bar(rect: CGRect(x: 276, y: 437, width: 70, height: 150)),
        Bar(rect: CGRect(x: 384, y: 367, width: 70, height: 290)),
        Bar(rect: CGRect(x: 492, y: 307, width: 70, height: 410)),
        Bar(rect: CGRect(x: 600, y: 387, width: 70, height: 250)),
    ]
    /// The text cursor: earshot puts the cursor in the message box. It never sends.
    static let cursor = Bar(rect: CGRect(x: 708, y: 286, width: 40, height: 452))
}

/// The band at the top of the management window: the mark, the name, one line on what earshot does, and the version.
struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            EarshotMark().frame(width: 44, height: 44)
                .shadow(color: Brand.tileBottom.opacity(0.35), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("earshot").font(.system(size: 22, weight: .semibold))
                Text("Voice control for this Mac. Audio stays on this Mac. earshot never presses Send unless you say \"send\".")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if let v = Brand.version {
                Text("Version \(v)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(
            LinearGradient(colors: [Brand.accent.opacity(0.16), Brand.accent.opacity(0.02)],
                           startPoint: .leading, endPoint: .trailing)
        )
    }
}
