import AppKit
import SwiftUI

/// earshot brand colors, from assets/brand/README.md.
public enum Brand {
    public static let tileTop = Color(red: 0x6A / 255, green: 0x5C / 255, blue: 0xFF / 255)
    public static let tileBottom = Color(red: 0x24 / 255, green: 0x16 / 255, blue: 0x6B / 255)
    public static let cursor = Color(red: 0xFF / 255, green: 0xC2 / 255, blue: 0x4B / 255)
    public static let ink = Color(red: 0x1B / 255, green: 0x13 / 255, blue: 0x40 / 255)

    /// The version from Info.plist, or nil for a build that is not an app bundle (swift run, tests).
    public static var version: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
}

/// The earshot mark as vector paths: an ear with a text cursor in the ear canal, and two sound arcs.
/// The paths are the same as in assets/brand/src/mark.svg (1024 canvas, tile at 100,100, 824 wide).
/// The view draws them with SwiftUI, so the mark is sharp at every size and needs no image file.
public struct EarshotMark: View {
    /// Draw the tile behind the mark. Without the tile, the mark uses `ink` for the ear, for example for a template image.
    var tile: Bool
    var ink: Color

    public init(tile: Bool = true, ink: Color = .white) { self.tile = tile; self.ink = ink }

    public var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let k = side / 824
            // SVG: translate(-100 -100) for the tile, then translate(-14 0) for the mark group.
            let mark = CGAffineTransform(scaleX: k, y: k).translatedBy(x: -100 - 14, y: -100)
            if tile {
                let rect = CGRect(x: 0, y: 0, width: side, height: side)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 185 * k, style: .continuous),
                         with: .linearGradient(Gradient(colors: [Brand.tileTop, Brand.tileBottom]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0.6 * side, y: side)))
            }
            func stroke(_ p: Path, _ color: Color, _ width: CGFloat, _ opacity: Double = 1) {
                ctx.stroke(p.applying(mark), with: .color(color.opacity(opacity)),
                           style: StrokeStyle(lineWidth: width * k, lineCap: .round, lineJoin: .round))
            }
            stroke(MarkPaths.innerArc, ink, 40, 0.55)
            stroke(MarkPaths.outerArc, ink, 40, 0.28)
            stroke(MarkPaths.rim, ink, 64)
            stroke(MarkPaths.curl, ink, 54)
            stroke(MarkPaths.cursor, Brand.cursor, 46)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("earshot")
    }
}

/// The paths of the mark in SVG coordinates (y goes down).
enum MarkPaths {
    /// An SVG arc "M x y1 A r r 0 0 0 x y2" with the same x at both ends. The arc bulges to the left.
    static func leftArc(x: CGFloat, y1: CGFloat, y2: CGFloat, r: CGFloat) -> Path {
        let half = (y2 - y1) / 2
        let cx = x + (r * r - half * half).squareRoot()
        let cy = y1 + half
        let a1 = atan2(y1 - cy, x - cx)            // upper end, about -138 degrees
        let a2 = atan2(y2 - cy, x - cx)            // lower end, about +138 degrees
        let sweep = (2 * .pi - (a2 - a1))          // the short way, through 180 degrees
        var p = Path()
        let steps = 32
        for i in 0...steps {
            let a = a1 - sweep * CGFloat(i) / CGFloat(steps)
            let pt = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    static let innerArc = leftArc(x: 330, y1: 432, y2: 592, r: 120)
    static let outerArc = leftArc(x: 262, y1: 372, y2: 652, r: 205)

    static let rim: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 420, y: 470))
        p.addCurve(to: CGPoint(x: 600, y: 262), control1: CGPoint(x: 420, y: 340), control2: CGPoint(x: 500, y: 262))
        p.addCurve(to: CGPoint(x: 790, y: 452), control1: CGPoint(x: 712, y: 262), control2: CGPoint(x: 790, y: 344))
        p.addCurve(to: CGPoint(x: 700, y: 620), control1: CGPoint(x: 790, y: 540), control2: CGPoint(x: 738, y: 580))
        p.addCurve(to: CGPoint(x: 626, y: 752), control1: CGPoint(x: 662, y: 660), control2: CGPoint(x: 664, y: 714))
        p.addCurve(to: CGPoint(x: 494, y: 748), control1: CGPoint(x: 590, y: 788), control2: CGPoint(x: 524, y: 790))
        return p
    }()

    static let curl: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 524, y: 448))
        p.addCurve(to: CGPoint(x: 604, y: 372), control1: CGPoint(x: 530, y: 400), control2: CGPoint(x: 562, y: 372))
        p.addCurve(to: CGPoint(x: 680, y: 458), control1: CGPoint(x: 652, y: 372), control2: CGPoint(x: 684, y: 412))
        p.addCurve(to: CGPoint(x: 620, y: 556), control1: CGPoint(x: 676, y: 502), control2: CGPoint(x: 636, y: 516))
        return p
    }()

    static let cursor: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 532, y: 540))
        p.addLine(to: CGPoint(x: 532, y: 640))
        return p
    }()
}

/// The band at the top of the management window: the mark, the name, one line on what earshot does, and the version.
struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            EarshotMark().frame(width: 44, height: 44)
                .shadow(color: Brand.tileBottom.opacity(0.35), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("earshot").font(.system(size: 22, weight: .semibold, design: .rounded))
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
            LinearGradient(colors: [Brand.tileTop.opacity(0.14), Brand.tileBottom.opacity(0.04)],
                           startPoint: .leading, endPoint: .trailing)
        )
    }
}
