import Foundation
import XCTest
@testable import PACore
import PAMac
#if canImport(AppKit) && canImport(PDFKit)
import AppKit
import PDFKit

/// Phase 2, Q2: the readers of macOS (build spec 7.3) on made-up files: a PDF with text, a PDF with no text
/// (as a scan), RTF and Word.
final class MacReaderTests: XCTestCase {
    func folder() -> URL { tempFolder() }

    /// A PDF with one line of text on each page. With no lines: a page with a grey box only, like a scan.
    func makePDF(_ url: URL, pages: [String?]) {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        for line in pages {
            ctx.beginPDFPage(nil)
            if let line {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSAttributedString(string: line, attributes: [.font: NSFont.systemFont(ofSize: 14)]).draw(at: CGPoint(x: 50, y: 700))
                NSGraphicsContext.restoreGraphicsState()
            } else {
                ctx.setFillColor(gray: 0.5, alpha: 1)
                ctx.fill(CGRect(x: 50, y: 50, width: 400, height: 600))
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    func testPDFWithTextHasPages() {
        let url = folder().appendingPathComponent("quote.pdf")
        makePDF(url, pages: ["The floor tiles cost 42 pounds per square metre.", nil, "Delivery takes ten working days."])
        guard case .text(let pages) = makeTextReader().read(url) else { return XCTFail("no text") }
        XCTAssertEqual(pages.map(\.page), [1, 3])
        XCTAssertTrue(pages[0].text.contains("floor tiles"))
    }

    func testPDFScanHasNoText() {
        let url = folder().appendingPathComponent("scan.pdf")
        makePDF(url, pages: [nil, nil])
        XCTAssertEqual(makeTextReader().read(url), .noText)
    }

    func testRTFAndWord() throws {
        let dir = folder()
        let s = NSAttributedString(string: "The plumber starts on Monday the 23rd.")
        let rtf = dir.appendingPathComponent("letter.rtf")
        try s.data(from: NSRange(location: 0, length: s.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]).write(to: rtf)
        let docx = dir.appendingPathComponent("letter.docx")
        try s.data(from: NSRange(location: 0, length: s.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]).write(to: docx)
        for url in [rtf, docx] {
            guard case .text(let pages) = makeTextReader().read(url) else { XCTFail(url.lastPathComponent); continue }
            XCTAssertTrue(pages[0].text.contains("plumber starts"), url.lastPathComponent)
        }
    }
}
#endif
