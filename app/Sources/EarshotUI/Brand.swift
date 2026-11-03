import AppKit
import SwiftUI

/// earshot brand colors, from assets/brand/README.md.
public enum Brand {
    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    public static let tileTop = hex(0x2C2C29)
    public static let tileBottom = hex(0x0C0C0B)
    public static let ear = hex(0xF2F2EE)
    public static let ink = hex(0x161615)
    /// The tint of the window controls: graphite in light mode, a light gray in dark mode, so the controls keep their contrast.
    public static let accent = Color(nsColor: NSColor(name: "earshotAccent") { look in
        look.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xD8 / 255, green: 0xD8 / 255, blue: 0xD2 / 255, alpha: 1)
            : NSColor(srgbRed: 0x2C / 255, green: 0x2C / 255, blue: 0x29 / 255, alpha: 1)
    })

    /// The version from Info.plist, or nil for a build that is not an app bundle (swift run, tests).
    public static var version: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
}

/// The earshot mark as vector shapes: an ear, drawn as one stroke.
/// The shapes are the same as in assets/brand/src/mark.svg (1024 canvas, tile at 100,100, 824 wide).
/// SwiftUI draws them, so the mark is sharp at every size, and the module needs no resource file.
public struct EarshotMark: View {
    /// Draw the tile behind the mark. Without the tile, the ear uses `glyph`, as glyph.svg does.
    var tile: Bool
    var glyph: Color

    public init(tile: Bool = true, glyph: Color = .primary) { self.tile = tile; self.glyph = glyph }

    public var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let k = side / 824
            let toView = CGAffineTransform(scaleX: k, y: k).translatedBy(x: -100, y: -100)
            let ear = MarkShapes.path().applying(toView)
            let stroke = StrokeStyle(lineWidth: MarkShapes.strokeWidth * k, lineCap: .round, lineJoin: .round)
            guard tile else {
                ctx.stroke(ear, with: .color(glyph), style: stroke)
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
            ctx.stroke(ear, with: .color(Brand.ear), style: stroke)
            ctx.stroke(tilePath.applying(CGAffineTransform(translationX: side / 2, y: side / 2).scaledBy(x: 0.9964, y: 0.9964)
                        .translatedBy(x: -side / 2, y: -side / 2)),
                       with: .color(.white.opacity(0.16)), lineWidth: max(0.5, 3 * k))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("earshot")
    }
}

/// The ear in SVG coordinates (y goes down). The curves use a 24-unit grid, the same as the menu bar icon.
/// `scale` and `origin` put the grid on the 1024 canvas, with the center of the ear at 512,512.
enum MarkShapes {
    static let scale: CGFloat = 27
    static let origin = CGPoint(x: 161, y: 180)
    /// The stroke width on the 1024 canvas (2.2 grid units).
    static let strokeWidth: CGFloat = 2.2 * scale

    /// Each stroke: a start point, then cubic curves as (control 1, control 2, end), in grid units.
    typealias Curve = (CGPoint, CGPoint, CGPoint)
    static let strokes: [(start: CGPoint, curves: [Curve])] = [
        // The outer rim, down to the lobe.
        (CGPoint(x: 6.5, y: 9.6), [
            (CGPoint(x: 6.5, y: 5.9), CGPoint(x: 9.3, y: 3), CGPoint(x: 12.9, y: 3)),
            (CGPoint(x: 16.6, y: 3), CGPoint(x: 19.4, y: 5.9), CGPoint(x: 19.4, y: 9.5)),
            (CGPoint(x: 19.4, y: 12.3), CGPoint(x: 17.9, y: 13.7), CGPoint(x: 16.5, y: 15)),
            (CGPoint(x: 15.3, y: 16.1), CGPoint(x: 14.7, y: 16.9), CGPoint(x: 14.5, y: 18.5)),
            (CGPoint(x: 14.2, y: 20.5), CGPoint(x: 12.8, y: 21.6), CGPoint(x: 11.1, y: 21.6)),
            (CGPoint(x: 9.6, y: 21.6), CGPoint(x: 8.4, y: 20.7), CGPoint(x: 7.9, y: 19.3)),
        ]),
        // The inner fold.
        (CGPoint(x: 9.9, y: 9.7), [
            (CGPoint(x: 9.9, y: 7.8), CGPoint(x: 11.3, y: 6.3), CGPoint(x: 13, y: 6.3)),
            (CGPoint(x: 14.8, y: 6.3), CGPoint(x: 16.1, y: 7.7), CGPoint(x: 16.1, y: 9.4)),
            (CGPoint(x: 16.1, y: 10.7), CGPoint(x: 15.3, y: 11.4), CGPoint(x: 14.4, y: 11.8)),
            (CGPoint(x: 13.4, y: 12.2), CGPoint(x: 12.9, y: 13), CGPoint(x: 12.9, y: 14)),
        ]),
    ]

    /// A grid point on the 1024 canvas.
    static func canvas(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + scale * p.x, y: origin.y + scale * p.y)
    }

    /// The ear as one path on the 1024 canvas.
    static func path() -> Path {
        var path = Path()
        for s in strokes {
            path.move(to: canvas(s.start))
            for c in s.curves {
                path.addCurve(to: canvas(c.2), control1: canvas(c.0), control2: canvas(c.1))
            }
        }
        return path
    }
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
