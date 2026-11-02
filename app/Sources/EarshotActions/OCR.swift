import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision

// The OCR fallback for apps with poor accessibility labels (R-CL-4, DESIGN 3.5 step 6).
// It takes one picture of the front window and reads its text with Apple Vision, on the Mac.
// The picture stays in memory and is not saved. It needs the Screen Recording permission.

enum OCR {
    /// True if earshot has the Screen Recording permission. This call never shows a prompt.
    static func allowed() -> Bool { CGPreflightScreenCaptureAccess() }

    /// The texts in the window of the app, with their screen frames. Empty on any failure.
    static func read(pid: pid_t, window: Frame) async -> [(String, Frame)] {
        guard allowed() else { return [] }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let mine = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 }
            // The window with the frame nearest to the AX frame of the front window.
            func distance(_ r: CGRect) -> Double { abs(r.minX - window.x) + abs(r.minY - window.y) + abs(r.width - window.w) + abs(r.height - window.h) }
            guard let target = mine.min(by: { distance($0.frame) < distance($1.frame) }) else { return [] }
            let filter = SCContentFilter(desktopIndependentWindow: target)
            let config = SCStreamConfiguration()
            let scale = Double(filter.pointPixelScale)
            config.width = Int(target.frame.width * scale)
            config.height = Int(target.frame.height * scale)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let f = Frame(x: target.frame.minX, y: target.frame.minY, w: target.frame.width, h: target.frame.height)
            return try await Task.detached { try recognize(image, window: f) }.value
        } catch {
            return []
        }
    }

    static func recognize(_ image: CGImage, window: Frame) throws -> [(String, Frame)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { o in
            guard let top = o.topCandidates(1).first, top.confidence >= 0.3 else { return nil }
            return (top.string, ActionRules.ocrFrame(box: o.boundingBox, window: window))
        }
    }
}
