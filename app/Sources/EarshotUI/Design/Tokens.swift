import AppKit
import CoreText
import SwiftUI

// The earshot design system in Swift: the same tokens as the design system "earshot" and the design canvas
// (dk, 2026-11-15). Dark only. White ink on near-black paper, two state colors and no other color.

/// The colors. Contrast on `paper`: ink 17.4:1, ink2 8.2:1, ink3 5.9:1, amber 10.8:1, coral 8.5:1.
public enum Palette {
    static func hex(_ v: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255, opacity: alpha)
    }

    /// The page.
    public static let paper = hex(0x0C0C0B)
    /// A raised surface: a card, a field, a hovered row.
    public static let raise = hex(0x161615)
    /// A surface on a raised surface, for example a menu.
    public static let raise2 = hex(0x1C1C1B)
    /// The track of a switch, a progress bar or a selected segment.
    public static let fill = hex(0x252523)
    /// The line between rows.
    public static let rule = hex(0x242422)
    /// The edge of a control.
    public static let line = hex(0x363633)
    /// The edge of a control under the pointer.
    public static let lineHi = hex(0x5E5E59)
    /// The edge of the panel, the window and the note.
    public static let edge = hex(0x2E2E2B)
    /// Text and glyphs.
    public static let ink = hex(0xF2F2EE)
    /// Second text: captions, details.
    public static let ink2 = hex(0xA8A8A2)
    /// Third text: times, counts, hints.
    public static let ink3 = hex(0x8E8E88)
    /// Decoration only (3.0:1). Never for text that must be read.
    public static let ink4 = hex(0x5E5E59)
    /// earshot needs you, or a cloud setting is on.
    public static let amber = hex(0xF5B460)
    /// A command failed, or a to-do is late.
    public static let coral = hex(0xFF8A7A)
    public static let amberWash = hex(0xF5B460, 0.07)
    public static let amberEdge = hex(0xF5B460, 0.35)
    public static let coralWash = hex(0xFF8A7A, 0.06)
    public static let coralEdge = hex(0xFF8A7A, 0.40)
    /// The background outside the window, in the snapshots.
    static let night = hex(0x050505)
}

/// The motion of earshot: one ease (cubic-bezier 0.16, 1, 0.3, 1) and short times.
public enum Motion {
    /// The ease of the design system, for a change of state.
    public static func ease(_ seconds: Double = 0.26) -> Animation { .timingCurve(0.16, 1, 0.3, 1, duration: seconds) }
    /// The note: it rises 12 pt and fades in over 300 ms.
    public static let note = ease(0.3)
    /// A switch knob, a segment, a selected link.
    public static let control = ease(0.26)
    /// A hover.
    public static let hover = Animation.easeOut(duration: 0.12)
}

/// One text style of the type scale: size, line height and weight in points, tracking in em.
public struct TextStyle: Hashable, Sendable {
    public var size: CGFloat
    public var lineHeight: CGFloat
    public var weight: CGFloat
    public var tracking: CGFloat
    public var mono: Bool

    public init(_ size: CGFloat, _ lineHeight: CGFloat, _ weight: CGFloat = 400, tracking: CGFloat = 0, mono: Bool = false) {
        self.size = size; self.lineHeight = lineHeight; self.weight = weight; self.tracking = tracking; self.mono = mono
    }

    /// The title of a window page: "Settings", "Today".
    public static let display = TextStyle(30, 34, 650, tracking: -0.03)
    /// The title of an empty or a problem state.
    public static let title = TextStyle(20, 26, 650, tracking: -0.02)
    /// The title of a group of settings, and the state in the panel header.
    public static let head = TextStyle(17, 22, 650, tracking: -0.015)
    /// The title of a section in a page.
    public static let section = TextStyle(15, 20, 650, tracking: -0.01)
    public static let body = TextStyle(14, 20)
    public static let bodyStrong = TextStyle(14, 20, 500)
    /// One plain sentence under a title.
    public static let call = TextStyle(13, 18)
    /// The heading of a part of the panel: "Today", "Recent".
    public static let label = TextStyle(12, 16, 600)
    /// A command in the panel.
    public static let row = TextStyle(13.5, 19)
    /// The line under a command or a setting.
    public static let detail = TextStyle(12.5, 17)
    public static let small = TextStyle(12, 16)
    /// The note on screen.
    public static let note = TextStyle(14, 20, 500)
    public static let noteQuestion = TextStyle(14, 20, 550)
    /// A key: a button with a label.
    public static let key = TextStyle(13, 18, 600, tracking: -0.005)
    public static let keySmall = TextStyle(12, 16, 600)
    /// Times, counts and versions.
    public static let mono = TextStyle(12, 16, mono: true)
    public static let monoSmall = TextStyle(11.5, 16, mono: true)
}

/// The two typefaces of earshot, from the web site: Schibsted Grotesk (variable weight) and JetBrains Mono. Both
/// use the SIL Open Font License 1.1. The app bundle has them in Contents/Resources/Fonts. Without the files, for
/// example in `swift test`, the system font takes their place.
public enum Typeface {
    static let sansName = "SchibstedGrotesk-Regular"
    static let monoName = "JetBrainsMono-Regular"
    /// The 'wght' axis of a variable font.
    static let weightAxis = 0x7767_6874

    private static let lock = NSLock()
    nonisolated(unsafe) private static var registered: Bool?
    nonisolated(unsafe) private static var cache: [TextStyle: NSFont] = [:]

    /// Registers the font files of the app bundle for this process. Call it once at start. It is safe to call again.
    @discardableResult
    public static func register(bundle: Bundle = .main) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let registered { return registered }
        var ok = false
        if let folder = bundle.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
           let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for url in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
                var error: Unmanaged<CFError>?
                if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { ok = true }
            }
        }
        ok = ok && NSFont(name: sansName, size: 12) != nil
        registered = ok
        return ok
    }

    /// The font of a style, as an AppKit font. The system font if the files are not registered.
    public static func nsFont(_ style: TextStyle) -> NSFont {
        let ready = register()
        lock.lock()
        defer { lock.unlock() }
        if let f = cache[style] { return f }
        let font: NSFont
        if style.mono {
            font = (ready ? NSFont(name: monoName, size: style.size) : nil)
                ?? .monospacedSystemFont(ofSize: style.size, weight: .regular)
        } else if ready, let base = NSFont(name: sansName, size: style.size) {
            let variation = [NSNumber(value: weightAxis): NSNumber(value: Double(style.weight))]
            let desc = base.fontDescriptor.addingAttributes([
                NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variation,
            ])
            font = NSFont(descriptor: desc, size: style.size) ?? base
        } else {
            font = .systemFont(ofSize: style.size, weight: systemWeight(style.weight))
        }
        cache[style] = font
        return font
    }

    /// The SwiftUI font of a style.
    public static func font(_ style: TextStyle) -> Font { Font(nsFont(style) as CTFont) }

    /// The space to add between lines, so that a line of text is `lineHeight` high.
    static func lineSpacing(_ style: TextStyle) -> CGFloat {
        let f = nsFont(style)
        let natural = ceil(f.ascender - f.descender + f.leading)
        return max(0, style.lineHeight - natural)
    }

    static func systemWeight(_ w: CGFloat) -> NSFont.Weight {
        switch w {
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        default: return .heavy
        }
    }
}

extension View {
    /// Sets the font, the tracking and the line spacing of a text style.
    public func textStyle(_ style: TextStyle) -> some View {
        font(Typeface.font(style))
            .tracking(style.tracking * style.size)
            .lineSpacing(Typeface.lineSpacing(style))
    }

    /// A text style and a color.
    public func textStyle(_ style: TextStyle, _ color: Color) -> some View {
        textStyle(style).foregroundStyle(color)
    }
}
