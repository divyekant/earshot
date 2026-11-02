import EarshotCore

/// Pairs of common words for the same UI action, for label matches only (R-MT-1). This is data, with no app in it.
/// "click refresh" finds the button "Reload". A pair never holds a risky word, and a match through a pair is fuzzy,
/// so it never presses a risky label (R-NV-5).
enum UIWords {
    static let groups: [[String]] = [
        ["refresh", "reload"],
        ["settings", "preferences"],
        ["find", "search"],
        ["options", "preferences"],
        ["info", "information", "details"],
        ["profile", "account"],
        ["help", "support"],
    ]

    /// The score of a full match through a pair: below an exact match, above the strong mark.
    static let score = 0.9

    static let other: [String: [String]] = {
        var out: [String: [String]] = [:]
        for g in groups {
            for w in g where !SafetyPolicy.isRisky(w) { out[w, default: []] += g.filter { $0 != w && !SafetyPolicy.isRisky($0) } }
        }
        return out
    }()

    /// The words with one word changed to each of its other words. Empty if no word has another word.
    static func swaps(_ words: [String]) -> [[String]] {
        var out: [[String]] = []
        for (i, w) in words.enumerated() {
            for o in other[w] ?? [] {
                var copy = words
                copy[i] = o
                out.append(copy)
            }
        }
        return out
    }
}
