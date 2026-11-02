// T4 owns this module. See docs/BUILD-PLAN.md.
import EarshotCore
import Foundation

/// Text helpers for discovery. The same rules as the probe (probe/Sources/EarshotProbe/Support.swift).
enum Words {
    /// Lower case, letters and digits only, single spaces.
    static func normalize(_ s: String) -> String { SafetyPolicy.normalize(s) }

    /// The normalized text with no spaces. "Whats App" and "WhatsApp" have the same key.
    static func key(_ s: String) -> String { normalize(s).replacingOccurrences(of: " ", with: "") }

    /// Removes invisible characters, turns no-break spaces into spaces, and joins runs of white space.
    static func squash(_ s: String) -> String {
        let invisible: Set<UInt32> = [0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0xFEFF, 0xFFFC]
        var view = String.UnicodeScalarView()
        for u in s.unicodeScalars where !invisible.contains(u.value) {
            view.append(u.value == 0xA0 ? " " : u)
        }
        return String(view).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Removes control characters, so that typed text can never hold Return or Tab (R-NV-5).
    static func printable(_ s: String) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return String(view)
    }
}
