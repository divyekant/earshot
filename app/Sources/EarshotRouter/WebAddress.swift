import Foundation

/// "Open <web address>" (R-NV-7). The words after a command word must look like a domain name:
/// "open hn.com", "go to news dot ycombinator dot com", "visit https://example.org/docs".
/// Speech can glue the command word to the address ("Openhnm.com"). The rule splits it only when the rest is a domain.
enum WebAddress {
    /// The command words that can start the command, longest first.
    static let leads = ["browse to", "go to", "open up", "open", "visit", "load"]

    /// The address as an https (or the spoken http) URL, or nil if the words are not "open <domain>".
    static func parse(_ text: String) -> String? {
        var s = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = s.last, ".!?,".contains(last) { s.removeLast() }
        for filler in ["please ", "can you ", "could you "] where s.hasPrefix(filler) { s.removeFirst(filler.count) }
        if s.hasSuffix(" please") { s.removeLast(" please".count) }

        var rest: String?
        for lead in leads {
            if s.hasPrefix(lead + " ") { rest = String(s.dropFirst(lead.count + 1)); break }
        }
        // A glued command word: only "open", and only if the rest alone is a domain.
        if rest == nil, s.hasPrefix("open"), !s.hasPrefix("open "), let glued = address(String(s.dropFirst(4))) { return glued }
        guard let rest else { return nil }
        return address(rest)
    }

    /// "news dot ycombinator dot com" → "https://news.ycombinator.com". Nil if it is not a domain.
    static func address(_ words: String) -> String? {
        var a = " " + words.trimmingCharacters(in: .whitespaces) + " "
        a = a.replacingOccurrences(of: " dot ", with: ".").replacingOccurrences(of: " slash ", with: "/")
        a = a.trimmingCharacters(in: .whitespaces)
        a = a.replacingOccurrences(of: " .", with: ".").replacingOccurrences(of: ". ", with: ".")
        var scheme = "https"
        for prefix in ["https://", "http://"] where a.hasPrefix(prefix) {
            scheme = String(prefix.dropLast(3))
            a.removeFirst(prefix.count)
        }
        guard !a.contains(" "), !a.isEmpty else { return nil }
        let host = String(a.split(separator: "/", maxSplits: 1).first ?? "")
        guard isDomain(host) else { return nil }
        return "\(scheme)://\(a)"
    }

    /// Labels of letters, digits and hyphens, at least one dot, and a top-level label of 2 or more letters.
    static func isDomain(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2, tld.allSatisfy({ $0.isLetter && $0.isASCII }) else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { ($0.isLetter || $0.isNumber || $0 == "-") && $0.isASCII }
        }
    }
}
