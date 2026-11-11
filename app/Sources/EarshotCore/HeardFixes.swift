import Foundation

/// Words that speech to text wrote for a name or a label, and the label that the owner then chose (gap item 12).
/// Example: the owner said "open Claude", speech wrote "open cloud", the note was "not sure", and the owner answered
/// "yes" for the app Claude. The pair "cloud" → "claude" then corrects the same words the next time, but only if the
/// corrected words give a sure route to the same target (`key`) on the screen and in the names of that time (I-15).
/// Data in the store folder (`heard.json`, next to `names.json` and `habits.json`). An entry holds the heard words
/// of the target (at most 3 words), the label words and the target key. No message text and no audio.
public final class HeardFixes: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        /// The words that speech wrote, normalized ("cloud").
        public var heard: String
        /// The words of the label that the owner chose, normalized ("claude").
        public var label: String
        /// The key of the chosen target (TieHabits.key). A correction counts only for a route to this target.
        public var key: String
        public var at: Date

        public init(heard: String, label: String, key: String, at: Date) {
            self.heard = SafetyPolicy.normalize(heard); self.label = SafetyPolicy.normalize(label); self.key = key; self.at = at
        }
    }

    public static let fileName = "heard.json"
    /// The most entries. The oldest go first.
    public static let maxEntries = 200
    /// The most words in the heard part.
    public static let maxWords = 3

    private let lock = NSLock()
    private var entries: [Entry]
    private let write: ([Entry]) -> Void

    public init(entries: [Entry] = [], write: @escaping ([Entry]) -> Void = { _ in }) {
        self.entries = entries
        self.write = write
    }

    /// The corrections of the store folder. A save error does not stop a command.
    public convenience init(store: Store) {
        self.init(entries: store.load([Entry].self, Self.fileName) ?? [], write: { try? store.save($0, Self.fileName) })
    }

    public var all: [Entry] { lock.lock(); defer { lock.unlock() }; return entries }

    /// Keeps a correction. It replaces an older entry with the same heard words and the same target.
    /// It keeps nothing if the heard words are the label, if the heard part is longer than `maxWords`, or if the label
    /// is risky (R-NV-5): a correction never leads to a risky press or a send.
    public func record(_ entry: Entry) {
        let heardWords = entry.heard.split(separator: " ")
        guard !heardWords.isEmpty, heardWords.count <= Self.maxWords, !entry.label.isEmpty, !entry.key.isEmpty,
              entry.heard.replacingOccurrences(of: " ", with: "") != entry.label.replacingOccurrences(of: " ", with: ""),
              !SafetyPolicy.isRisky(entry.label), !SafetyPolicy.isRisky(entry.heard) else { return }
        lock.lock()
        entries.removeAll { $0.heard == entry.heard && $0.key == entry.key }
        entries.append(entry)
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
        let copy = entries
        lock.unlock()
        write(copy)
    }

    /// The entries whose heard words are in `words` (normalized words, in order), the newest first.
    public func matches(_ words: [String]) -> [Entry] {
        let line = " " + words.joined(separator: " ") + " "
        lock.lock(); defer { lock.unlock() }
        return entries.reversed().filter { line.contains(" \($0.heard) ") }
    }
}
