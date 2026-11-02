import AppKit
import EarshotCore
import Foundation

/// The name source for the router (E1, section 6):
/// - The sidebar index is a fast hint for the chats on screen. It is built in the background.
/// - The app's own search at command time is the main source, because it knows every chat.
/// - Contacts is optional, and off by default.
/// Names that the owner wrote by hand (source "manual") always stay and win.
public actor NameIndex: NameFinder {
    /// The catalogue rows. The index reads only chat apps that the owner approved and enabled.
    private let apps: @Sendable () -> [AppEntry]
    /// The owner's full name. E0 showed that Slack and Messages find the owner's own chat by this name.
    public let owner: String
    public var useContacts: Bool
    /// Names older than this are read again on the next `names(appID:)` call, in seconds.
    public var maxAge: TimeInterval
    /// Bring each app to the front for a moment during `refresh`. Some apps show no window to
    /// Accessibility while they are in the background. It presses no key.
    public var readInFront: Bool = false
    private let store: Store?
    private var cache: [String: (at: Date, names: [NameEntry])] = [:]
    private var contactsCache: [NameEntry]?
    /// The last sidebar scan and the last search of each app, for the log and the management window.
    public private(set) var lastScans: [String: SidebarScan] = [:]
    public private(set) var lastSearch: SearchScan?

    /// - Parameters:
    ///   - apps: returns the current catalogue rows.
    ///   - store: if given, `refresh` keeps the manual names of names.json and saves the result there.
    public init(apps: @escaping @Sendable () -> [AppEntry], owner: String = NSFullUserName(), useContacts: Bool = false,
                maxAge: TimeInterval = 600, store: Store? = nil) {
        self.apps = apps
        self.owner = owner
        self.useContacts = useContacts
        self.maxAge = maxAge
        self.store = store
    }

    public func setReadInFront(_ on: Bool) { readInFront = on }

    public func setUseContacts(_ on: Bool) {
        useContacts = on
        contactsCache = nil
    }

    private func chatApp(_ appID: String) -> AppEntry? {
        apps().first { $0.id == appID && $0.isChat && $0.approved && $0.enabled }
    }

    /// The known names of one app: the manual names, the sidebar, the owner's own chat and, if on, Contacts.
    /// It reads the sidebar only if the cached names are older than `maxAge`. It presses nothing.
    public func names(appID: String) async -> [NameEntry] {
        if let c = cache[appID], Date().timeIntervalSince(c.at) < maxAge { return c.names }
        return await read(appID: appID)
    }

    /// Types `term` into the app's own search and returns the chat names that it shows, best first.
    /// It presses keys in the app, but never Return. It opens no chat (R-NV-5).
    public func search(appID: String, term: String) async -> [NameEntry] {
        guard let app = chatApp(appID) else { return [] }
        let scan = await SearchReader.search(app, term: term)
        lastSearch = scan
        let ownerKey = Words.key(owner)
        return scan.names.map { NameEntry(appID: appID, name: $0, isSelf: Words.key($0) == ownerKey, source: .search) }
    }

    /// Reads the sidebars of all approved chat apps again, or of the given apps. Saves to the store if there is one.
    /// It reads only. Returns all names.
    @discardableResult
    public func refresh(appIDs: [String]? = nil) async -> [NameEntry] {
        let ids = appIDs ?? apps().filter { $0.isChat && $0.approved && $0.enabled }.map(\.id)
        for id in ids { _ = await read(appID: id, front: readInFront) }
        let all = NameMerge.merge(cache.values.map(\.names))
        if let store { try? store.save(all.filter { $0.source != .contacts }, "names.json") }
        return all
    }

    /// All names in the cache.
    public func all() -> [NameEntry] { NameMerge.merge(cache.values.map(\.names)) }

    private func read(appID: String, front: Bool = false) async -> [NameEntry] {
        let manual = (store?.names ?? []).filter { $0.appID == appID && $0.source == .manual }
        guard let app = chatApp(appID) else { return manual }
        var found: [NameEntry] = []
        if let scan = await SidebarReader.scan(app, front: front) {
            lastScans[appID] = scan
            found = scan.names.map { NameEntry(appID: appID, name: $0.name, isSelf: $0.isSelf, source: .sidebar) }
        }
        let ownerKey = Words.key(owner)
        for i in found.indices where Words.key(found[i].name) == ownerKey { found[i].isSelf = true }
        var lists = [manual, found]
        if !(manual + found).contains(where: \.isSelf), !owner.isEmpty {
            // The owner's own chat: the app's search finds it by the owner's name (E0).
            lists.append([NameEntry(appID: appID, name: owner, isSelf: true, source: .search)])
        }
        if useContacts {
            if contactsCache == nil { contactsCache = ContactsSource.names(appID: "") }
            lists.append((contactsCache ?? []).map { var e = $0; e.appID = appID; return e })
        }
        let names = NameMerge.merge(lists)
        cache[appID] = (Date(), names)
        return names
    }
}
