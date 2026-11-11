import Foundation

/// The text of one page of a file. `page` is set for a PDF.
public struct PageText: Equatable, Sendable {
    public var page: Int?
    public var text: String
    public init(page: Int?, text: String) { self.page = page; self.text = text }
}

/// The result of a read of a kept file (phase 2 build spec, 7.3).
public enum ReadOutcome: Equatable, Sendable {
    case text([PageText])
    /// A file with no text, for example a PDF scan.
    case noText
    case tooLarge
    case noAccess
    case gone
    /// A file type that the PA does not read. The reference still works.
    case unsupported
}

/// Reads the text of a file. The PA never changes, moves or deletes the file (R-PA-3).
public protocol TextReader: AnyObject {
    func read(_ url: URL) -> ReadOutcome
}

/// Reads plain text, Markdown and HTML. The program adds the readers of macOS (PDF, RTF, Word) in `formats`.
public final class FileTextReader: TextReader {
    /// The largest file that the PA reads: 20 MB.
    public static let maxBytes: Int64 = 20 * 1_000_000
    /// More readers by file extension (lower case). A reader gives nil for a file with no text.
    public var formats: [String: (URL) throws -> [PageText]?] = [:]

    public init() {}

    public static let plainTypes: Set<String> = ["txt", "text", "md", "markdown"]
    public static let htmlTypes: Set<String> = ["html", "htm"]

    public func canRead(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return Self.plainTypes.contains(ext) || Self.htmlTypes.contains(ext) || formats[ext] != nil
    }

    public func read(_ url: URL) -> ReadOutcome {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return .gone }
        guard canRead(url) else { return .unsupported }
        guard fm.isReadableFile(atPath: url.path) else { return .noAccess }
        let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
        if size > Self.maxBytes { return .tooLarge }
        let ext = url.pathExtension.lowercased()
        do {
            if Self.plainTypes.contains(ext) || Self.htmlTypes.contains(ext) {
                let data = try Data(contentsOf: url)
                var text = String(decoding: data, as: UTF8.self)
                if Self.htmlTypes.contains(ext) { text = Self.htmlText(text) }
                return Self.outcome([PageText(page: nil, text: text)])
            }
            guard let pages = try formats[ext]?(url) else { return .noText }
            return Self.outcome(pages)
        } catch {
            return Self.isAccessError(error) ? .noAccess : .noText
        }
    }

    static func outcome(_ pages: [PageText]) -> ReadOutcome {
        let kept = pages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return kept.isEmpty ? .noText : .text(kept)
    }

    static func isAccessError(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain, e.code == NSFileReadNoPermissionError { return true }
        if e.domain == NSPOSIXErrorDomain, e.code == Int(EPERM) || e.code == Int(EACCES) { return true }
        if let u = e.userInfo[NSUnderlyingErrorKey] as? NSError { return isAccessError(u) }
        return false
    }

    /// The text of an HTML file: no scripts, no styles, no tags. A block tag ends a line.
    public static func htmlText(_ html: String) -> String {
        var s = html
        for tag in ["script", "style", "head"] {
            s = s.replacingOccurrences(of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "</?(p|div|br|li|h[1-6]|tr|section|article|ul|ol|table)\\b[^>]*>", with: "\n",
                                   options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        let lines = s.split(separator: "\n").map {
            $0.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" }).joined(separator: " ")
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
