import Foundation

/// The envelope of a mail from its raw headers (probe run 3: "all headers" takes about 0.5 s, the envelope event about
/// 4.7 s). It reads only the headers that the reader needs. It keeps no other header.
public enum MailHeaders {
    /// The header lines as (name in lower case, value). A line that starts with a space or a tab continues the last one.
    public static func parse(_ raw: String) -> [(String, String)] {
        var out: [(String, String)] = []
        for line in raw.components(separatedBy: .newlines) {
            if line.isEmpty { continue }
            if line.first == " " || line.first == "\t", !out.isEmpty {
                out[out.count - 1].1 += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            out.append((name, value))
        }
        return out
    }

    /// Decodes RFC 2047 words ("=?UTF-8?B?...?=" and "=?UTF-8?Q?...?=").
    public static func decode(_ s: String) -> String {
        guard s.contains("=?") else { return s }
        let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        var lastWasWord = false
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let between = ns.substring(with: NSRange(location: last, length: m.range.location - last))
            // Space between two encoded words is not part of the text.
            if !(lastWasWord && between.trimmingCharacters(in: .whitespaces).isEmpty) { out += between }
            let charset = ns.substring(with: m.range(at: 1)).lowercased()
            let kind = ns.substring(with: m.range(at: 2)).uppercased()
            let body = ns.substring(with: m.range(at: 3))
            var data: Data?
            if kind == "B" {
                data = Data(base64Encoded: body + String(repeating: "=", count: (4 - body.count % 4) % 4))
            } else {
                var bytes: [UInt8] = []
                var chars = Array(body.replacingOccurrences(of: "_", with: " ").utf8)[...]
                while let c = chars.first {
                    chars = chars.dropFirst()
                    if c == UInt8(ascii: "="), chars.count >= 2, let v = UInt8(String(decoding: chars.prefix(2), as: UTF8.self), radix: 16) {
                        bytes.append(v)
                        chars = chars.dropFirst(2)
                    } else {
                        bytes.append(c)
                    }
                }
                data = Data(bytes)
            }
            let enc: String.Encoding = charset.contains("8859-1") || charset.contains("latin1") ? .isoLatin1
                : charset.contains("1252") ? .windowsCP1252 : .utf8
            out += data.flatMap { String(data: $0, encoding: enc) } ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
            lastWasWord = true
        }
        out += ns.substring(from: last)
        return out
    }

    /// "Sam Lee <sam.lee@example.net>" gives the name and the address.
    public static func nameAndAddress(_ s: String) -> (String, String) {
        let line = decode(s)
        guard let lt = line.lastIndex(of: "<"), let gt = line.lastIndex(of: ">"), lt < gt else {
            return ("", line.trimmingCharacters(in: .whitespaces))
        }
        let name = line[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        return (name, String(line[line.index(after: lt)..<gt]).trimmingCharacters(in: .whitespaces))
    }

    /// The addresses of a To or Cc value. A comma inside quotes does not split.
    public static func addresses(_ s: String) -> [String] {
        var parts: [String] = []
        var cur = ""
        var quoted = false
        var angle = false
        for ch in s {
            if ch == "\"" { quoted.toggle() }
            if ch == "<" { angle = true }
            if ch == ">" { angle = false }
            if ch == ",", !quoted, !angle { parts.append(cur); cur = ""; continue }
            cur.append(ch)
        }
        parts.append(cur)
        return parts.map { nameAndAddress($0).1 }.filter { $0.contains("@") }
    }

    static let dateFormats = ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z",
                              "EEE, d MMM yyyy HH:mm:ss zzz"]

    /// The Date header ("Tue, 3 Nov 2026 08:12:00 +0000"). A comment in brackets at the end is removed.
    public static func date(_ s: String) -> Date? {
        var v = s
        if let p = v.firstIndex(of: "(") { v = String(v[..<p]) }
        v = v.trimmingCharacters(in: .whitespaces)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in dateFormats {
            f.dateFormat = format
            if let d = f.date(from: v) { return d }
        }
        return nil
    }

    /// The envelope of message `id` from its raw headers, with two facts that are not headers.
    public static func envelope(id: String, raw: String, replied: Bool, junk: Bool, received: Date? = nil) -> MailMessage {
        let h = parse(raw)
        func first(_ n: String) -> String? { h.first { $0.0 == n }?.1 }
        func all(_ n: String) -> [String] { h.filter { $0.0 == n }.flatMap { addresses($0.1) } }
        let (name, address) = nameAndAddress(first("from") ?? "")
        let auto = (first("auto-submitted") ?? "no").lowercased()
        return MailMessage(
            id: id, messageID: (first("message-id") ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "<> ")),
            fromName: name, fromAddress: address, to: all("to"), cc: all("cc"), subject: decode(first("subject") ?? ""),
            date: received ?? first("date").flatMap(date) ?? Date(),
            listHeader: first("list-unsubscribe") != nil || first("list-id") != nil,
            precedence: (first("precedence") ?? "").lowercased(),
            autoSubmitted: !(auto.isEmpty || auto.hasPrefix("no")), junk: junk, replied: replied)
    }
}
