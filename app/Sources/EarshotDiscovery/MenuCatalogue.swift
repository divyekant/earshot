import AppKit
import EarshotCore
import Foundation

/// The time and the result of one menu read, for the log and the management window.
public struct CatalogueRead: Sendable {
    public var bundleID: String
    public var name: String
    public var shortcuts: Int
    public var guess: MenuGuess?
    public var ms: Double
}

/// Builds catalogue rows from the menu bars of the running apps, and from the installed apps
/// (R-MT-1, R-MT-2, E1 section 3.1). It reads only: it opens no menu and presses nothing.
/// It needs the Accessibility permission for the menu read. Without it, it lists the installed apps only.
public final class MenuCatalogue: CatalogueBuilder, @unchecked Sendable {
    /// Bundle ids to leave out, by the owner's choice. earshot always leaves itself out.
    public var skip: Set<String>
    /// Also list the installed apps that do not run now, for "open <app>" commands.
    public var includeInstalled: Bool
    /// The menu reads of the last scan.
    public private(set) var lastReads: [CatalogueRead] = []
    /// The time of the last scan in ms.
    public private(set) var lastMs: Double = 0

    public init(skip: Set<String> = [], includeInstalled: Bool = true) {
        self.skip = skip
        self.includeInstalled = includeInstalled
    }

    public func discover() async -> [AppEntry] {
        let t0 = Clock.nowNs()
        var skipped = skip
        if let own = Bundle.main.bundleIdentifier { skipped.insert(own) }
        let running = NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
            return !skipped.contains(id)
        }
        let trusted = AX.trusted()
        // Read the menu bars side by side: one slow app (up to 700 ms in E1) must not hold up the others.
        let reads: [(AppEntry, CatalogueRead)] = await withTaskGroup(of: (AppEntry, CatalogueRead)?.self) { group in
            for app in running {
                let pid = app.processIdentifier
                let bundleID = app.bundleIdentifier ?? ""
                let name = app.localizedName ?? bundleID
                let url = app.bundleURL
                group.addTask {
                    MenuCatalogue.read(pid: pid, bundleID: bundleID, name: name, url: url, menus: trusted)
                }
            }
            var out: [(AppEntry, CatalogueRead)] = []
            for await r in group { if let r { out.append(r) } }
            return out
        }
        var rows = reads.map(\.0)
        lastReads = reads.map(\.1).sorted { $0.name.lowercased() < $1.name.lowercased() }
        if includeInstalled {
            let known = Set(rows.map(\.bundleID))
            rows += MenuCatalogue.installedApps().filter { !known.contains($0.bundleID) && !skipped.contains($0.bundleID) }
        }
        lastMs = Clock.round1(Clock.ms(since: t0))
        return MenuRules.merge(existing: [], found: rows)
    }

    static func read(pid: pid_t, bundleID: String, name: String, url: URL?, menus: Bool) -> (AppEntry, CatalogueRead)? {
        guard !bundleID.isEmpty else { return nil }
        let t0 = Clock.nowNs()
        let electron = isElectron(url)
        var shortcuts: [MenuShortcut]?
        if menus {
            let el = AX.appElement(pid)
            if electron { AX.askForTree(el) }
            shortcuts = AX.menuShortcuts(el)
        }
        let entry = MenuRules.entry(name: name, bundleID: bundleID, extraNames: bundleNames(url),
                                    shortcuts: shortcuts, electron: electron)
        let read = CatalogueRead(bundleID: bundleID, name: name, shortcuts: shortcuts?.count ?? 0,
                                 guess: shortcuts.flatMap(MenuRules.guess), ms: Clock.round1(Clock.ms(since: t0)))
        return (entry, read)
    }

    static func isElectron(_ url: URL?) -> Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
    }

    /// The display name and the short name in the app's Info.plist.
    static func bundleNames(_ url: URL?) -> [String] {
        guard let info = url.flatMap({ Bundle(url: $0)?.infoDictionary }) else { return [] }
        return ["CFBundleDisplayName", "CFBundleName"].compactMap { info[$0] as? String }
    }

    /// The apps in the standard app folders. It reads the Info.plist of each app, and leaves out
    /// background-only apps. The rows only open the app: they have no chat keys until the app runs and earshot reads its menus.
    public static func installedApps() -> [AppEntry] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                       "/System/Applications/Utilities", "\(home)/Applications"]
        var out: [AppEntry] = []
        var seen = Set<String>()
        for folder in folders {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            for item in items where item.hasSuffix(".app") {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(item)
                guard let info = Bundle(url: url)?.infoDictionary, let bundleID = info["CFBundleIdentifier"] as? String,
                      seen.insert(bundleID).inserted else { continue }
                if (info["LSBackgroundOnly"] as? Bool) == true { continue }
                let name = String(item.dropLast(4))
                out.append(MenuRules.entry(name: name, bundleID: bundleID, extraNames: bundleNames(url), shortcuts: nil,
                                           electron: isElectron(url)))
            }
        }
        return out
    }
}

extension MenuCatalogue {
    /// Scans, joins the scan with the rows in apps.json (the owner's approvals and edits stay), and saves.
    /// Returns the joined rows.
    @discardableResult
    public func refresh(store: Store) async throws -> [AppEntry] {
        let rows = MenuRules.merge(existing: store.apps, found: await discover())
        try store.save(rows, "apps.json")
        return rows
    }
}
