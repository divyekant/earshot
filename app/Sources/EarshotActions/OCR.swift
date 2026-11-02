import CoreGraphics
import Foundation
import Vision

// The OCR fallback for apps with poor accessibility labels (R-CL-4, DESIGN 3.5 step 6).
// It takes one picture of the front window and reads its text with Apple Vision, on the Mac.
// The picture stays in memory and is not saved. It needs the Screen Recording permission.

enum OCR {
    /// True if earshot has the Screen Recording permission. This call never shows a prompt.
    static func allowed() -> Bool { WindowShot.allowed() }

    /// The texts in the window of the app, with their screen frames. Empty on any failure.
    static func read(pid: pid_t, window: Frame) async -> [(String, Frame)] {
        guard let capture = await WindowShot.capture(pid: pid, window: window) else { return [] }
        let (image, f) = capture
        return (try? await Task.detached { try recognize(image, window: f) }.value) ?? []
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
