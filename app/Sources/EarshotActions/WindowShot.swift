import AppKit
import CoreGraphics
import EarshotCore
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

// One picture of the front window, for the OCR fallback (on the Mac) and for the screenshot fallback (D-10, Jev).
// The picture stays in memory. earshot never saves it. It needs the Screen Recording permission.

enum WindowShot {
    /// True if earshot has the Screen Recording permission. This call never shows a prompt.
    static func allowed() -> Bool { CGPreflightScreenCaptureAccess() }

    /// A picture of the window of the app with this pid whose frame is nearest to `window` (the AX frame),
    /// and the screen frame of the captured window. Nil on any failure.
    static func capture(pid: pid_t, window: Frame) async -> (CGImage, Frame)? {
        guard allowed() else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let mine = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 }
            func distance(_ r: CGRect) -> Double { abs(r.minX - window.x) + abs(r.minY - window.y) + abs(r.width - window.w) + abs(r.height - window.h) }
            guard let target = mine.min(by: { distance($0.frame) < distance($1.frame) }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: target)
            let config = SCStreamConfiguration()
            let scale = Double(filter.pointPixelScale)
            config.width = Int(target.frame.width * scale)
            config.height = Int(target.frame.height * scale)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return (image, Frame(x: target.frame.minX, y: target.frame.minY, w: target.frame.width, h: target.frame.height))
        } catch {
            return nil
        }
    }

    /// The picture for Jev: scaled so that its longest side is at most VisionRules.maxSide pixels, with a numbered
    /// badge at the top left of each element (set-of-marks, the same numbers as "show numbers"), as JPEG.
    /// Risky elements get a number too, so that Jev can point at them, and earshot then refuses the pick (R-NV-5).
    /// E3 step 2: with no number on "Star", Jev picked the link next to it.
    static func marked(_ image: CGImage, window: Frame, elements: [ScreenElement]) -> VisionShot? {
        let scale = Double(image.width) / max(window.w, 1)
        let (pw, ph) = VisionRules.pictureSize(width: window.w, height: window.h, scale: scale)
        // The picture can be larger than the capture (a small window). Then the drawing scales it up.
        guard VisionRules.sizeOK(pw, ph) else { return nil }
        let k = Double(pw) / max(window.w, 1)  // picture pixels for each screen point
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: pw, height: ph))

        let marks = VisionMarks.place(elements, window: window, k: k, pictureHeight: Double(ph))
        let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: VisionMarks.fontSize, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        for m in marks {
            let text = "\(m.number)" as NSString
            let size = text.size(withAttributes: attributes)
            let rect = NSRect(x: m.x, y: m.y, width: max(VisionMarks.badgeWidth, size.width + 8), height: VisionMarks.badgeHeight)
            NSColor(calibratedRed: 1, green: 0.85, blue: 0.2, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            NSColor.black.setStroke()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).stroke()
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let out = ctx.makeImage(), let jpeg = jpeg(out) else { return nil }
        return VisionShot(jpeg: jpeg, marks: marks.map(\.number), width: pw, height: ph)
    }

    static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: VisionRules.jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

/// Where the number badges go on the picture. Pure, so that the tests can check it.
enum VisionMarks {
    // E3 step 1: at half size (digits about 10 px), Jev read a 5 as a 3 in 1 of 8 calls. At full size, 14 of 14 were right.
    // So the badges are drawn on the final picture, with digits of about 13 px or more.
    static let fontSize: CGFloat = 17
    static let badgeWidth: CGFloat = 30
    static let badgeHeight: CGFloat = 22

    struct Mark: Equatable {
        let number: Int
        /// The bottom left corner of the badge, in picture pixels, with the origin at the bottom left.
        let x: Double
        let y: Double
    }

    /// One badge for each numbered element ("e<n>") that is inside the window. Risky elements get one too.
    /// `k` is picture pixels for each screen point.
    static func place(_ elements: [ScreenElement], window w: Frame, k: Double, pictureHeight ph: Double) -> [Mark] {
        elements.compactMap { e in
            guard e.id.hasPrefix("e"), let n = Int(e.id.dropFirst()) else { return nil }
            let left = (e.x - w.x) * k, top = (e.y - w.y) * k
            guard left >= 0, top >= 0, left < w.w * k, top < w.h * k else { return nil }
            // Top left of the element, inside the picture.
            let x = min(left, w.w * k - Double(badgeWidth))
            let y = max(0, ph - top - Double(badgeHeight))
            return Mark(number: n, x: max(0, x), y: y)
        }
    }
}
