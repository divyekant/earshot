/// Sound codes for names (E2, section 7, item 5). Speech to text hears some names as other words:
/// "Aditi" gives "a ditty", "Mrinal" gives "Marinel" or "Manal", "Claude" gives "clawed".
/// The router joins short words ("a ditty" gives "aditty") and compares the sound codes.
///
/// The code is a small key in the style of Soundex and Metaphone, written for English speech to text:
/// - Each run of vowels (a, e, i, o, u, y) becomes "A".
/// - Letters that sound alike share a code: d and t give "T", b and p give "P", f, v and "ph" give "F",
///   c, g, k and q give "K", s, z and a soft c give "S", "sh" and "ch" give "X", "th" gives "T".
/// - "w" and "h" are dropped. A final silent "e" is dropped. A run of one code becomes one code.
enum SoundCode {
    static func code(_ word: String) -> String {
        var s = Array(word.lowercased().unicodeScalars.filter { $0.value >= 97 && $0.value <= 122 }.map { Character($0) })
        if s.count > 3, s.last == "e", let p = s.dropLast().last, !isVowel(p) { s.removeLast() }
        var out: [Character] = []
        func put(_ c: Character) { if out.last != c { out.append(c) } }
        var i = 0
        while i < s.count {
            let c = s[i]
            let next: Character? = i + 1 < s.count ? s[i + 1] : nil
            switch c {
            case "a", "e", "i", "o", "u", "y": put("A")
            case "p":
                if next == "h" { put("F"); i += 1 } else { put("P") }
            case "s":
                if next == "h" { put("X"); i += 1 } else { put("S") }
            case "c":
                if next == "h" { put("X"); i += 1 } else if let n = next, "eiy".contains(n) { put("S") } else { put("K") }
            case "t":
                if next == "h" { i += 1 }
                put("T")
            case "d": put("T")
            case "b": put("P")
            case "f", "v": put("F")
            case "g", "k", "q": put("K")
            case "x": put("K"); put("S")
            case "z": put("S")
            case "j": put("J")
            case "m": put("M")
            case "n": put("N")
            case "l": put("L")
            case "r": put("R")
            default: break // w, h
            }
            i += 1
        }
        return String(out)
    }

    static func isVowel(_ c: Character) -> Bool { "aeiouy".contains(c) }

    /// 1.0 is the same sound code. The first code must be the same, as in Soundex:
    /// "today" must not sound like "Aditi". Words shorter than 3 letters give 0.
    static func similarity(_ a: String, _ b: String) -> Double {
        guard a.count >= 3, b.count >= 3 else { return 0 }
        let x = code(a), y = code(b)
        guard let fx = x.first, fx == y.first else { return 0 }
        return TextKit.similarity(x, y)
    }
}
