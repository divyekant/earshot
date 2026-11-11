import Foundation

/// The owner's last answer to a tie (gap item 6): "the second one" for the same name in two chat apps.
/// The router uses it the next time that the rules score the same targets the same. It changes the order only
/// between those targets, and it never makes a risky press sure: a risky element has no key.
/// Data in the store folder (`habits.json`, next to `names.json`). It holds target keys only: an app id, a chat name,
/// a label. No message text and no audio.
public final class TieHabits: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        /// The key of the target that the owner chose.
        public var chosen: String
        /// The keys of the other targets of the note, sorted.
        public var over: [String]
        public var at: Date

        public init(chosen: String, over: [String], at: Date) {
            self.chosen = chosen; self.over = over.sorted(); self.at = at
        }
    }

    public static let fileName = "habits.json"
    /// The most entries. The oldest go first.
    public static let maxEntries = 200

    private let lock = NSLock()
    private var entries: [Entry]
    private let write: ([Entry]) -> Void

    public init(entries: [Entry] = [], write: @escaping ([Entry]) -> Void = { _ in }) {
        self.entries = entries
        self.write = write
    }

    /// The habits of the store folder. A save error does not stop a command.
    public convenience init(store: Store) {
        self.init(entries: store.load([Entry].self, Self.fileName) ?? [], write: { try? store.save($0, Self.fileName) })
    }

    public var all: [Entry] { lock.lock(); defer { lock.unlock() }; return entries }

    /// The key of a target, or nil if the target cannot have a habit: a send, typing with no target, scroll,
    /// back, numbers, and each risky element (R-NV-5). Keys of screen elements hold the front app, the role and
    /// the label, because element ids change with each read. A chat key holds no message text.
    public static func key(_ intent: Intent, screen: ScreenSnapshot?) -> String? {
        func norm(_ s: String) -> String { SafetyPolicy.normalize(s) }
        switch intent {
        case .openChat(let app, let target, _): return "chat:\(app):\(norm(target))"
        case .openApp(let app): return "app:\(app)"
        case .openURL(let address): return "url:\(address)"
        case .click(let id), .typeInto(let id, _):
            guard let screen else { return nil }
            let kind: String
            if case .click = intent { kind = "click" } else { kind = "field" }
            if let path = MenuElements.path(id) {
                if SafetyPolicy.isRisky(path.last ?? "") { return nil }
                return "menu:\(screen.bundleID):\(path.map(norm).joined(separator: ">"))"
            }
            guard let e = screen.elements.first(where: { $0.id == id }), !e.risky, !SafetyPolicy.isRisky(e) else { return nil }
            return "\(kind):\(screen.bundleID):\(e.role):\(norm(e.label))"
        default: return nil
        }
    }

    /// Keeps the owner's answer. It replaces an older answer for the same targets.
    public func record(chosen: String, over others: [String], at: Date = Date()) {
        let others = others.filter { $0 != chosen }
        guard !others.isEmpty else { return }
        let set = Set(others + [chosen])
        lock.lock()
        entries.removeAll { Set($0.over + [$0.chosen]) == set }
        entries.append(Entry(chosen: chosen, over: others, at: at))
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
        let copy = entries
        lock.unlock()
        write(copy)
    }

    /// The index in `keys` of the target that the owner chose the last time, or nil. It counts only if the owner's
    /// note showed all the targets of `keys`: a tie with a target that the owner did not see has no habit.
    public func preferred(among keys: [String]) -> Int? {
        guard keys.count >= 2, Set(keys).count == keys.count else { return nil }
        let want = Set(keys)
        lock.lock(); defer { lock.unlock() }
        for e in entries.reversed() where want.contains(e.chosen) && want.isSubset(of: Set(e.over + [e.chosen])) {
            return keys.firstIndex(of: e.chosen)
        }
        return nil
    }
}
