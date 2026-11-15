import SwiftUI

// Generated from the icons of the earshot design system (assets/Icons, 24 grid, round stroke, no fill).
// Arcs are cubic curves here. Do not edit by hand: change the SVG and generate again.

/// The glyphs of earshot.
public enum GlyphKind: String, CaseIterable, Sendable {
    case ear, open, click, typed, sent, plugin, failed, notDone, notSure, pause, onMac, cloud, text, more, mic, micOff, download, search, chevronRight, chevronDown, back, check, remove, window, wake

    /// The stroke width in grid units. The dots of `more` are thicker, so they read as dots.
    public var weight: CGFloat { self == .more ? 2.6 : (self == .ear ? 2.2 : 1.6) }

    /// The glyph on the 24-unit grid. y goes down.
    public var path: Path {
        var p = Path()
        switch self {
        case .ear:
            p.move(to: CGPoint(x: 6.5, y: 9.6))
            p.addCurve(to: CGPoint(x: 12.9, y: 3), control1: CGPoint(x: 6.5, y: 5.9), control2: CGPoint(x: 9.3, y: 3))
            p.addCurve(to: CGPoint(x: 19.4, y: 9.5), control1: CGPoint(x: 16.6, y: 3), control2: CGPoint(x: 19.4, y: 5.9))
            p.addCurve(to: CGPoint(x: 16.5, y: 15), control1: CGPoint(x: 19.4, y: 12.3), control2: CGPoint(x: 17.9, y: 13.7))
            p.addCurve(to: CGPoint(x: 14.5, y: 18.5), control1: CGPoint(x: 15.3, y: 16.1), control2: CGPoint(x: 14.7, y: 16.9))
            p.addCurve(to: CGPoint(x: 11.1, y: 21.6), control1: CGPoint(x: 14.2, y: 20.5), control2: CGPoint(x: 12.8, y: 21.6))
            p.addCurve(to: CGPoint(x: 7.9, y: 19.3), control1: CGPoint(x: 9.6, y: 21.6), control2: CGPoint(x: 8.4, y: 20.7))
            p.move(to: CGPoint(x: 9.9, y: 9.7))
            p.addCurve(to: CGPoint(x: 13, y: 6.3), control1: CGPoint(x: 9.9, y: 7.8), control2: CGPoint(x: 11.3, y: 6.3))
            p.addCurve(to: CGPoint(x: 16.1, y: 9.4), control1: CGPoint(x: 14.8, y: 6.3), control2: CGPoint(x: 16.1, y: 7.7))
            p.addCurve(to: CGPoint(x: 14.4, y: 11.8), control1: CGPoint(x: 16.1, y: 10.7), control2: CGPoint(x: 15.3, y: 11.4))
            p.addCurve(to: CGPoint(x: 12.9, y: 14), control1: CGPoint(x: 13.4, y: 12.2), control2: CGPoint(x: 12.9, y: 13))
        case .open:
            p.move(to: CGPoint(x: 7, y: 17))
            p.addLine(to: CGPoint(x: 17, y: 7))
            p.move(to: CGPoint(x: 9, y: 7))
            p.addLine(to: CGPoint(x: 17, y: 7))
            p.addLine(to: CGPoint(x: 17, y: 15))
        case .click:
            p.move(to: CGPoint(x: 5, y: 4))
            p.addLine(to: CGPoint(x: 10.5, y: 19))
            p.addLine(to: CGPoint(x: 12.7, y: 12.7))
            p.addLine(to: CGPoint(x: 19, y: 10.5))
            p.closeSubpath()
        case .typed:
            p.move(to: CGPoint(x: 4, y: 7))
            p.addLine(to: CGPoint(x: 20, y: 7))
            p.move(to: CGPoint(x: 4, y: 12))
            p.addLine(to: CGPoint(x: 20, y: 12))
            p.move(to: CGPoint(x: 4, y: 17))
            p.addLine(to: CGPoint(x: 13, y: 17))
        case .sent:
            p.move(to: CGPoint(x: 4, y: 12))
            p.addLine(to: CGPoint(x: 20, y: 4))
            p.addLine(to: CGPoint(x: 14, y: 20))
            p.addLine(to: CGPoint(x: 11, y: 13))
            p.closeSubpath()
        case .plugin:
            p.move(to: CGPoint(x: 12, y: 3))
            p.addLine(to: CGPoint(x: 12, y: 21))
            p.move(to: CGPoint(x: 7.5, y: 8))
            p.addLine(to: CGPoint(x: 16.5, y: 8))
        case .failed:
            p.addEllipse(in: CGRect(x: 3.5, y: 3.5, width: 17, height: 17))
            p.move(to: CGPoint(x: 12, y: 8))
            p.addLine(to: CGPoint(x: 12, y: 13))
            p.move(to: CGPoint(x: 12, y: 16.2))
            p.addLine(to: CGPoint(x: 12, y: 16.3))
        case .notDone:
            p.addEllipse(in: CGRect(x: 3.5, y: 3.5, width: 17, height: 17))
            p.move(to: CGPoint(x: 9, y: 9))
            p.addLine(to: CGPoint(x: 15, y: 15))
            p.move(to: CGPoint(x: 15, y: 9))
            p.addLine(to: CGPoint(x: 9, y: 15))
        case .notSure:
            p.addEllipse(in: CGRect(x: 3.5, y: 3.5, width: 17, height: 17))
            p.move(to: CGPoint(x: 9.6, y: 9.4))
            p.addCurve(to: CGPoint(x: 11.7722, y: 6.8893), control1: CGPoint(x: 9.5836, y: 8.1337), control2: CGPoint(x: 10.5167, y: 7.0552))
            p.addCurve(to: CGPoint(x: 14.5221, y: 8.7495), control1: CGPoint(x: 13.0277, y: 6.7233), control2: CGPoint(x: 14.209, y: 7.5224))
            p.addCurve(to: CGPoint(x: 13, y: 11.7), control1: CGPoint(x: 14.8353, y: 9.9766), control2: CGPoint(x: 14.1815, y: 11.244))
            p.addCurve(to: CGPoint(x: 12, y: 13.2), control1: CGPoint(x: 12.4, y: 12), control2: CGPoint(x: 12, y: 12.5))
            p.addLine(to: CGPoint(x: 12, y: 13.5))
            p.move(to: CGPoint(x: 12, y: 16.4))
            p.addLine(to: CGPoint(x: 12, y: 16.5))
        case .pause:
            p.move(to: CGPoint(x: 9.5, y: 7))
            p.addLine(to: CGPoint(x: 9.5, y: 17))
            p.move(to: CGPoint(x: 14.5, y: 7))
            p.addLine(to: CGPoint(x: 14.5, y: 17))
        case .onMac:
            p.addRoundedRect(in: CGRect(x: 5, y: 11, width: 14, height: 9), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: CGPoint(x: 8, y: 11))
            p.addLine(to: CGPoint(x: 8, y: 8))
            p.addCurve(to: CGPoint(x: 12, y: 4), control1: CGPoint(x: 8, y: 5.7909), control2: CGPoint(x: 9.7909, y: 4))
            p.addCurve(to: CGPoint(x: 16, y: 8), control1: CGPoint(x: 14.2091, y: 4), control2: CGPoint(x: 16, y: 5.7909))
            p.addLine(to: CGPoint(x: 16, y: 11))
        case .cloud:
            p.move(to: CGPoint(x: 7, y: 18))
            p.addLine(to: CGPoint(x: 17, y: 18))
            p.addCurve(to: CGPoint(x: 20.9589, y: 14.3011), control1: CGPoint(x: 19.0809, y: 17.9845), control2: CGPoint(x: 20.8023, y: 16.3762))
            p.addCurve(to: CGPoint(x: 17.6, y: 10.05), control1: CGPoint(x: 21.1155, y: 12.2261), control2: CGPoint(x: 19.655, y: 10.3776))
            p.addCurve(to: CGPoint(x: 12.7042, y: 5.66), control1: CGPoint(x: 17.1188, y: 7.6648), control2: CGPoint(x: 15.1276, y: 5.8793))
            p.addCurve(to: CGPoint(x: 7.1, y: 9.1), control1: CGPoint(x: 10.2809, y: 5.4408), control2: CGPoint(x: 8.0015, y: 6.8399))
            p.addCurve(to: CGPoint(x: 3.2173, y: 13.5069), control1: CGPoint(x: 4.8934, y: 9.4055), control2: CGPoint(x: 3.2424, y: 11.2794))
            p.addCurve(to: CGPoint(x: 7, y: 18), control1: CGPoint(x: 3.1923, y: 15.7345), control2: CGPoint(x: 4.8008, y: 17.645))
            p.closeSubpath()
        case .text:
            p.move(to: CGPoint(x: 9, y: 4))
            p.addLine(to: CGPoint(x: 15, y: 4))
            p.move(to: CGPoint(x: 9, y: 20))
            p.addLine(to: CGPoint(x: 15, y: 20))
            p.move(to: CGPoint(x: 12, y: 4))
            p.addLine(to: CGPoint(x: 12, y: 20))
        case .more:
            p.move(to: CGPoint(x: 6, y: 12))
            p.addLine(to: CGPoint(x: 6.01, y: 12))
            p.move(to: CGPoint(x: 12, y: 12))
            p.addLine(to: CGPoint(x: 12.01, y: 12))
            p.move(to: CGPoint(x: 18, y: 12))
            p.addLine(to: CGPoint(x: 18.01, y: 12))
        case .mic:
            p.addRoundedRect(in: CGRect(x: 9, y: 3, width: 6, height: 11), cornerSize: CGSize(width: 3, height: 3))
            p.move(to: CGPoint(x: 6, y: 11))
            p.addCurve(to: CGPoint(x: 12, y: 17), control1: CGPoint(x: 6, y: 14.3137), control2: CGPoint(x: 8.6863, y: 17))
            p.addCurve(to: CGPoint(x: 18, y: 11), control1: CGPoint(x: 15.3137, y: 17), control2: CGPoint(x: 18, y: 14.3137))
            p.move(to: CGPoint(x: 12, y: 17))
            p.addLine(to: CGPoint(x: 12, y: 21))
        case .micOff:
            p.addRoundedRect(in: CGRect(x: 9, y: 3, width: 6, height: 11), cornerSize: CGSize(width: 3, height: 3))
            p.move(to: CGPoint(x: 6, y: 11))
            p.addCurve(to: CGPoint(x: 12, y: 17), control1: CGPoint(x: 6, y: 14.3137), control2: CGPoint(x: 8.6863, y: 17))
            p.addCurve(to: CGPoint(x: 18, y: 11), control1: CGPoint(x: 15.3137, y: 17), control2: CGPoint(x: 18, y: 14.3137))
            p.move(to: CGPoint(x: 12, y: 17))
            p.addLine(to: CGPoint(x: 12, y: 21))
            p.move(to: CGPoint(x: 4, y: 4))
            p.addLine(to: CGPoint(x: 20, y: 20))
        case .download:
            p.move(to: CGPoint(x: 12, y: 4))
            p.addLine(to: CGPoint(x: 12, y: 15))
            p.move(to: CGPoint(x: 7, y: 10))
            p.addLine(to: CGPoint(x: 12, y: 15))
            p.addLine(to: CGPoint(x: 17, y: 10))
            p.move(to: CGPoint(x: 5, y: 20))
            p.addLine(to: CGPoint(x: 19, y: 20))
        case .search:
            p.addEllipse(in: CGRect(x: 5, y: 5, width: 12, height: 12))
            p.move(to: CGPoint(x: 20, y: 20))
            p.addLine(to: CGPoint(x: 15.5, y: 15.5))
        case .chevronRight:
            p.move(to: CGPoint(x: 10, y: 7))
            p.addLine(to: CGPoint(x: 15, y: 12))
            p.addLine(to: CGPoint(x: 10, y: 17))
        case .chevronDown:
            p.move(to: CGPoint(x: 7, y: 10))
            p.addLine(to: CGPoint(x: 12, y: 15))
            p.addLine(to: CGPoint(x: 17, y: 10))
        case .back:
            p.move(to: CGPoint(x: 14, y: 7))
            p.addLine(to: CGPoint(x: 9, y: 12))
            p.addLine(to: CGPoint(x: 14, y: 17))
        case .check:
            p.move(to: CGPoint(x: 6, y: 12.5))
            p.addLine(to: CGPoint(x: 10, y: 16.5))
            p.addLine(to: CGPoint(x: 18, y: 7.5))
        case .remove:
            p.move(to: CGPoint(x: 8, y: 8))
            p.addLine(to: CGPoint(x: 16, y: 16))
            p.move(to: CGPoint(x: 16, y: 8))
            p.addLine(to: CGPoint(x: 8, y: 16))
        case .window:
            p.addRoundedRect(in: CGRect(x: 3.5, y: 5, width: 17, height: 14), cornerSize: CGSize(width: 2.5, height: 2.5))
            p.move(to: CGPoint(x: 3.5, y: 9))
            p.addLine(to: CGPoint(x: 20.5, y: 9))
        case .wake:
            p.move(to: CGPoint(x: 5, y: 12))
            p.addLine(to: CGPoint(x: 7, y: 12))
            p.move(to: CGPoint(x: 9, y: 9))
            p.addLine(to: CGPoint(x: 9, y: 15))
            p.move(to: CGPoint(x: 13, y: 7))
            p.addLine(to: CGPoint(x: 13, y: 17))
            p.move(to: CGPoint(x: 17, y: 10))
            p.addLine(to: CGPoint(x: 17, y: 14))
            p.move(to: CGPoint(x: 19, y: 12))
            p.addLine(to: CGPoint(x: 19.01, y: 12))
        }
        return p
    }
}

