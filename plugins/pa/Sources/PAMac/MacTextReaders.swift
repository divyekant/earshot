import Foundation
import PACore
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// The text reader with the readers of macOS (phase 2 build spec, 7.3): PDF with PDFKit, RTF and Word with
/// NSAttributedString. Plain text, Markdown and HTML come from PACore.
public func makeTextReader() -> FileTextReader {
    let r = FileTextReader()
    #if canImport(PDFKit)
    r.formats["pdf"] = { url in
        guard let doc = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
        if doc.isLocked { throw CocoaError(.fileReadNoPermission) }
        var pages: [PageText] = []
        for i in 0..<doc.pageCount {
            if let t = doc.page(at: i)?.string, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pages.append(PageText(page: i + 1, text: t))
            }
        }
        return pages.isEmpty ? nil : pages
    }
    #endif
    #if canImport(AppKit)
    let types: [String: NSAttributedString.DocumentType] = ["rtf": .rtf, "docx": .officeOpenXML, "doc": .docFormat]
    for (ext, type) in types {
        r.formats[ext] = { url in
            let s = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
            return [PageText(page: nil, text: s.string)]
        }
    }
    #endif
    return r
}
