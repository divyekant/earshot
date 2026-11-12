import Foundation
import XCTest
@testable import PACore

/// Phase 3, rule 1: the PA only reads Mail, Notes and the calendar.
final class ReadOnlyTests: XCTestCase {
    static var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    /// No Apple event script has a word that changes something. The test reads the source file as text, so that a
    /// script that is not in `AppleScripts.all` is checked too.
    func testAppleScriptsOnlyRead() throws {
        let file = Self.sources.appendingPathComponent("PACore/Sources/AppleScripts.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        // Only the string literals count: the lines between the #" and "# marks.
        var scripts: [String] = []
        var rest = Substring(text)
        while let a = rest.range(of: "#\"") {
            let after = rest[a.upperBound...]
            guard let b = after.range(of: "\"#") else { break }
            scripts.append(String(after[..<b.lowerBound]))
            rest = after[b.upperBound...]
        }
        XCTAssertGreaterThanOrEqual(scripts.count, AppleScripts.all.count)
        for s in scripts + AppleScripts.all {
            for w in AppleScripts.forbidden {
                XCTAssertFalse(s.lowercased().contains(w), "a script has the word \"\(w)\": \(s)")
            }
        }
    }

    /// The EventKit code for events never saves or removes an event.
    func testNoEventWrites() throws {
        let mac = Self.sources.appendingPathComponent("PAMac")
        for name in try FileManager.default.contentsOfDirectory(atPath: mac.path) where name.hasSuffix(".swift") {
            let text = try String(contentsOf: mac.appendingPathComponent(name), encoding: .utf8)
            for bad in ["save(_ event", "save(event", "remove(event", "remove(_ event", "EKSpan"] {
                XCTAssertFalse(text.contains(bad), "\(name) has \(bad)")
            }
        }
    }
}
