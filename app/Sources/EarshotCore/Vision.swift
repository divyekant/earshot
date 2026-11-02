import Foundation

// T9: the screenshot fallback for clicks (R-MD-1, D-10, DESIGN 3.5 step 7).
// When the rules find no target for a click, earshot can send one picture of the front window to Jev.
// The picture has the "show numbers" numbers drawn on it (set-of-marks). Jev picks a number,
// or, if no number marks the target, gives a box on the picture. It is one call for each command at most,
// only after the rules fail, and never a loop (R-SP-2, D-2).

/// What the picker found on the picture.
public enum VisionPick: Sendable, Equatable {
    /// The number of a mark drawn on the picture. Mark n is the element "e<n>".
    case mark(Int)
    /// A box on the picture, with edges as fractions (0...1) of the picture, from the top left.
    case box(top: Double, left: Double, bottom: Double, right: Double)
    /// No answer: none of the marks, no box, an error, or the end of the budget.
    case none
}

/// One picture of the front window for the picker. It stays in memory. earshot never saves it.
public struct VisionShot: Sendable {
    /// JPEG bytes.
    public var jpeg: Data
    /// The numbers that are drawn on the picture.
    public var marks: [Int]
    public var width: Int
    public var height: Int

    public init(jpeg: Data, marks: [Int], width: Int, height: Int) {
        self.jpeg = jpeg; self.marks = marks; self.width = width; self.height = height
    }
}

/// Finds the target of a voice command on a picture of the front window. Implementation: Jev (cloud, opt-in).
public protocol ScreenPicker: Sendable {
    /// One request. It must return within `budgetMs`. It returns `.none` on any failure.
    func pick(_ command: String, shot: VisionShot, budgetMs: Int) async -> VisionPick
}

/// The pure rules of the screenshot fallback. The actions module and the tests use them.
public enum VisionRules {
    /// The fallback runs only for a command from the hold key (R-ON-5), only if the owner switched it on,
    /// and only if the rules found no sure target.
    public static func mayAsk(enabled: Bool, mode: InputMode, sensitive: Bool) -> Bool {
        enabled && mode == .hold && !sensitive
    }

    /// The longest side of the picture, in pixels. The API takes 280 to 1568 pixels on each side and does not resize.
    public static let maxSide = 1568
    /// The shortest side that the API takes. A smaller window gets no picture.
    public static let minSide = 280
    /// JPEG quality of the picture.
    public static let jpegQuality = 0.7
    /// A box larger than this part of the window does not mark one element, so earshot does not click it.
    /// E3 step 1: a large card was 0.34 of the picture. The hit test and SafetyPolicy still check the point.
    public static let maxBoxArea = 0.4
    /// A box smaller than this, in points on each side, is noise.
    public static let minBoxSide = 4.0

    /// Jev's box is used only if the picture has fewer numbers than this: an app with poor labels.
    /// E3 step 2: on pages with many numbers, the box gave no element (4 times) or a wrong element (1 time).
    public static let boxBelowMarks = 3

    /// The size of the picture for a window of `w` x `h` points: the longest side at most `maxSide` pixels,
    /// and the shortest side at least `minSide` pixels if the longest side permits it.
    /// E3 step 2: Calculator (230 x 408 points at scale 1) was too small, so earshot scales a small window up.
    public static func pictureSize(width w: Double, height h: Double, scale: Double) -> (Int, Int) {
        let pw = max(w * scale, 1), ph = max(h * scale, 1)
        var k = min(1, Double(maxSide) / max(pw, ph))
        if min(pw, ph) * k < Double(minSide) { k = min(Double(minSide) / min(pw, ph), Double(maxSide) / max(pw, ph)) }
        return (max(1, Int((pw * k).rounded())), max(1, Int((ph * k).rounded())))
    }

    /// True if the API takes a picture of this size.
    public static func sizeOK(_ w: Int, _ h: Int) -> Bool { min(w, h) >= minSide && max(w, h) <= maxSide }

    /// The screen point (top left origin, points) at the middle of a box on a picture of a window,
    /// or nil if the box is not a plausible single element.
    /// `window` is the screen frame of the window in the picture: x, y, w, h.
    public static func point(top: Double, left: Double, bottom: Double, right: Double,
                             window: (x: Double, y: Double, w: Double, h: Double)) -> (x: Double, y: Double)? {
        let vals = [top, left, bottom, right]
        guard vals.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }), bottom > top, right > left else { return nil }
        guard (bottom - top) * (right - left) <= maxBoxArea else { return nil }
        guard (bottom - top) * window.h >= minBoxSide, (right - left) * window.w >= minBoxSide else { return nil }
        return (window.x + (left + right) / 2 * window.w, window.y + (top + bottom) / 2 * window.h)
    }
}
