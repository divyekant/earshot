import Foundation

/// A watch on kept folders. macOS uses FSEvents (`PAMac`). Tests call the engine directly.
public protocol FolderWatcher: AnyObject {
    /// Watches these folders, and no others. The handler gets the paths that changed, on any queue.
    func watch(_ folders: [String], _ handler: @escaping ([String]) -> Void)
}

/// Q6: "keep this folder" and new files (phase 2 build spec, 8.5).
extension Engine {
    /// The most files of one kept folder, and the most levels below it.
    static let maxFolderFiles = 500
    static let maxFolderDepth = 3
    /// The file types of 7.3.
    static let readableTypes: Set<String> = ["txt", "md", "markdown", "html", "htm", "pdf", "rtf", "docx", "doc"]

    /// The files of a folder that the PA reads: 3 levels or fewer, no hidden file, no package, no folder with a
    /// `.git` folder. All of them, newest first.
    static func folderFiles(_ root: URL) -> [(URL, Date)] {
        let fm = FileManager.default
        var out: [(URL, Date)] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let rootDepth = root.standardizedFileURL.pathComponents.count
        for case let url as URL in e {
            let v = try? url.resourceValues(forKeys: Set(keys))
            let depth = url.standardizedFileURL.pathComponents.count - rootDepth
            if v?.isDirectory == true {
                if v?.isPackage == true || depth >= maxFolderDepth
                    || fm.fileExists(atPath: url.appendingPathComponent(".git").path) {
                    e.skipDescendants()
                }
                continue
            }
            guard v?.isRegularFile == true, readableTypes.contains(url.pathExtension.lowercased()) else { continue }
            out.append((url, v?.contentModificationDate ?? .distantPast))
        }
        return out.sorted { $0.1 > $1.1 }
    }

    /// "keep this folder [for <project>]" with a folder in front (the context key `document`).
    func keepFolder(id: String, text: String, context: [String: String]) -> Outgoing {
        guard let store else { return .note(id, "The PA store does not open. Nothing saved.") }
        var isDir: ObjCBool = false
        guard let path = context["document"], path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return .note(id, "No folder here. Nothing kept.")
        }
        let (project, _) = readProject("x " + text)
        let root = URL(fileURLWithPath: path, isDirectory: true)
        var folder: Doc
        if let old = store.doc(path: path), old.kind == .folder {
            folder = old
        } else {
            folder = Doc(address: nil, title: root.lastPathComponent, app: context["app"], projectID: project?.id, createdAt: clock.now)
            folder.path = path
            folder.kind = .folder
            do { folder.id = try store.insertDoc(folder) } catch { return .note(id, "The store had an error. Nothing kept.") }
        }
        let all = Engine.folderFiles(root)
        let files = all.prefix(Engine.maxFolderFiles)
        for (url, _) in files { _ = addFolderFile(url, folder: folder, arrival: false) }
        store.log("keep", .doc, folder.id, at: clock.now)
        docsChanged()
        watchFolders()
        var parts = ["Kept"]
        if let p = project { parts.append(p.name) }
        if all.count > files.count {
            parts.append("\(files.count) of \(Engine.grouped(all.count)) files")
        } else {
            parts.append("\(folder.title) · \(files.count) file\(files.count == 1 ? "" : "s")")
        }
        return .note(id, parts.joined(separator: " · "))
    }

    /// 1240 → "1,240".
    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// Saves one file of a kept folder and reads it in the background. Gives the new doc, or nil if it was kept.
    @discardableResult
    func addFolderFile(_ url: URL, folder: Doc, arrival: Bool) -> Doc? {
        guard let store else { return nil }
        if let old = store.doc(path: url.path) {
            if old.droppedAt == nil { queueReadIfChanged(old) }
            return nil
        }
        var d = Doc(address: nil, title: url.lastPathComponent, app: nil, projectID: folder.projectID, createdAt: clock.now)
        d.path = url.path
        d.kind = .file
        d.parentDocID = folder.id
        d.textState = .queued
        guard let newID = try? store.insertDoc(d) else { return nil }
        d.id = newID
        queueRead(d)
        if arrival { newArrival(d) }
        return d
    }

    func queueReadIfChanged(_ d: Doc) {
        guard let path = d.path, let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return }
        let size = (attrs[.size] as? NSNumber)?.int64Value
        let modified = attrs[.modificationDate] as? Date
        if size != d.size || !Engine.sameTime(modified, d.modifiedAt) || d.textState == .gone { queueRead(d) }
    }

    /// The kept folders, for the watch.
    func keptFolders() -> [Doc] {
        store?.docs(where: "dropped_at IS NULL AND kind = 'folder' AND path IS NOT NULL") ?? []
    }

    /// Starts the watch on all kept folders. A change comes back to the engine queue.
    func watchFolders() {
        guard let folderWatcher else { return }
        let paths = keptFolders().compactMap(\.path)
        folderWatcher.watch(paths) { [weak self] changed in
            self?.runLater(0) { [weak self] in self?.foldersChanged(changed) }
        }
    }

    /// Paths that changed in a kept folder: a new file is read and is a new arrival, a changed file is read again,
    /// a deleted file is `gone` (at the next file check).
    public func foldersChanged(_ paths: [String]) {
        guard let store else { return }
        let folders = keptFolders()
        var changed = false
        for p in Set(paths) {
            let url = URL(fileURLWithPath: p)
            guard Engine.readableTypes.contains(url.pathExtension.lowercased()),
                  !url.pathComponents.contains(where: { $0.hasPrefix(".") }),
                  let folder = folders.first(where: { f in f.path.map { p.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") } ?? false }),
                  let root = folder.path else { continue }
            let depth = url.pathComponents.count - URL(fileURLWithPath: root).pathComponents.count
            guard depth <= Engine.maxFolderDepth else { continue }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue else {
                if let d = store.doc(path: p), d.textState != .gone {
                    var g = d
                    g.textState = .gone
                    try? store.updateDoc(g, event: "doc-gone", at: clock.now)
                    changed = true
                }
                continue
            }
            let count = store.docs(where: "dropped_at IS NULL AND parent_doc_id = ?", [.int(folder.id)]).count
            if store.doc(path: p) == nil && count >= Engine.maxFolderFiles { continue }
            if addFolderFile(url, folder: folder, arrival: true) != nil { changed = true }
        }
        if changed { docsChanged() }
    }

    /// The text of a new arrival: "New in Kitchen · quote-2.pdf", or "New · quote-2.pdf" with no project.
    func arrivalText(_ d: Doc) -> String {
        if let p = projectName(d.projectID) { return "New in \(p) · \(d.title)" }
        return "New · \(d.title)"
    }

    /// Rule "new arrival" (8.5): "list" puts the file in the morning list and on the project page. "alert" shows
    /// an alert at once, inside the limits of phase 1.
    func newArrival(_ d: Doc) {
        guard let store else { return }
        let now = clock.now
        store.log("new-arrival", .doc, d.id, at: now)
        let mode = settings.rules(project: projectName(d.projectID)).newArrival
        guard mode == .alert else { return }
        if isQuiet(now) || settings.quietHours.contains(clockTime(now)) || alertsShownInLastHour(now) >= settings.maxAlertsPerHour {
            return
        }
        output.send(.alert(arrivalText(d)))
        store.log("alert-shown", .doc, d.id, at: now)
    }

    /// The new arrivals since a time, newest last, for the morning list and the project page.
    func arrivals(since: Date, project: Int64? = nil) -> [Doc] {
        guard let store else { return [] }
        let rows = (try? store.db.query("SELECT DISTINCT record_id FROM event WHERE type = 'new-arrival' AND at >= ? ORDER BY id",
                                        [.real(since.timeIntervalSince1970)])) ?? []
        return rows.compactMap { $0.first?.int.flatMap(store.doc) }.filter {
            $0.droppedAt == nil && (project == nil || $0.projectID == project)
                && settings.rules(project: projectName($0.projectID)).newArrival != .off
        }
    }
}
