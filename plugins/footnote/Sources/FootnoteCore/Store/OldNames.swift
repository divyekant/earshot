import Foundation

/// The file names from the time when Footnote had the name "PA" (before 2026-11-15).
/// At its start, Footnote gives the old files in its data folder the new names, so that no data is lost.
/// earshot moves the data folder itself (plugin-data/pa to plugin-data/footnote, docs/PLUGINS.md 2.1).
public enum OldNames {
    /// The old prefix of the store, the log and the store copies.
    public static let oldPrefix = "pa"
    public static let newPrefix = "footnote"

    /// Gives the new name to each old file in the folder. It does not replace a file that has the new name.
    /// It moves the store with its "-wal" and "-shm" files together, or it does not move them.
    /// Returns the old names that it moved.
    @discardableResult
    public static func migrate(folder: URL, fileManager fm: FileManager = .default) -> [String] {
        var moved: [String] = []
        func move(_ old: URL, _ new: URL) -> Bool {
            guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return false }
            do { try fm.moveItem(at: old, to: new); moved.append(old.lastPathComponent); return true } catch { return false }
        }
        // The store and its WAL files.
        let store = folder.appendingPathComponent("\(oldPrefix).sqlite")
        let newStore = folder.appendingPathComponent("\(newPrefix).sqlite")
        if fm.fileExists(atPath: store.path), !fm.fileExists(atPath: newStore.path) {
            for suffix in ["-wal", "-shm"] {
                let side = folder.appendingPathComponent("\(newPrefix).sqlite\(suffix)")
                if fm.fileExists(atPath: side.path) { try? fm.removeItem(at: side) }
                _ = move(folder.appendingPathComponent("\(oldPrefix).sqlite\(suffix)"), side)
            }
            _ = move(store, newStore)
        }
        _ = move(folder.appendingPathComponent("\(oldPrefix).log"), folder.appendingPathComponent("\(newPrefix).log"))
        // The copies of a store that did not open (pa-broken-<time>.sqlite), and the daily copies (backups/pa-<day>.sqlite).
        for dir in [folder, folder.appendingPathComponent("backups", isDirectory: true)] {
            let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names where name.hasPrefix("\(oldPrefix)-") && name.hasSuffix(".sqlite") {
                let rest = name.dropFirst(oldPrefix.count)
                _ = move(dir.appendingPathComponent(name), dir.appendingPathComponent(newPrefix + rest))
            }
        }
        return moved
    }
}
