import AppKit
import EarshotCore
import SwiftUI
import WebKit

// The pages of a plugin in the window and in the panel (dk, 2026-11-15: Footnote gets its own section). A plugin
// can write local pages to <store>/plugin-data/<id>/pages/. If the folder has index.html, the window gets a link
// with the name of the plugin, and the panel gets a part for it. earshot only shows the pages: it runs no script
// in them, and opens a web or app address outside the page view (docs/PLUGINS.md 5.4).

/// One plugin that has pages.
public struct PluginPages: Hashable, Identifiable, Sendable {
    public var id: String
    /// The name from plugin.json, for example "Footnote".
    public var name: String
    /// The folder of the pages.
    public var folder: URL
    /// The settings that the window shows as a form (docs/PLUGINS.md 3.2).
    public var settings: [PluginSetting]
    /// The settings file of the plugin.
    public var settingsFile: URL
    /// True if the pages folder has index.html.
    public var hasIndex: Bool
    public var index: URL { folder.appendingPathComponent("index.html") }

    public init(id: String, name: String, folder: URL, settings: [PluginSetting] = [], settingsFile: URL? = nil,
                hasIndex: Bool = true) {
        self.id = id; self.name = name; self.folder = folder; self.settings = settings
        self.settingsFile = settingsFile ?? folder.deletingLastPathComponent().appendingPathComponent("settings.json")
        self.hasIndex = hasIndex
    }

    /// The approved plugins with no problems whose pages folder has index.html or board.json, or that have settings.
    public static func find(store: Store) -> [PluginPages] {
        let catalog = PluginCatalog(store: store)
        return find(entries: catalog.scan(), dataFolder: catalog.dataFolder)
    }

    /// The same as `find(store:)`, for the tests.
    public static func find(entries: [PluginEntry], dataFolder: URL) -> [PluginPages] {
        entries.filter { $0.approved && $0.problems.isEmpty }.compactMap { e in
            let data = dataFolder.appendingPathComponent(e.id, isDirectory: true)
            let folder = data.appendingPathComponent("pages", isDirectory: true)
            let index = FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path)
            let board = FileManager.default.fileExists(atPath: folder.appendingPathComponent(Board.fileName).path)
            guard index || board || !e.manifest.settings.isEmpty else { return nil }
            return PluginPages(id: e.id, name: e.manifest.name, folder: folder, settings: e.manifest.settings,
                               settingsFile: data.appendingPathComponent("settings.json"), hasIndex: index)
        }
    }

    /// What a link in a page does. Only a file in the pages folder opens in the page view.
    public enum LinkPlace: Equatable, Sendable { case inView, outside, blocked }

    /// A file in the pages folder opens in the page view. Any other address opens in its app only if
    /// PluginTargetOpen allows it, the same rule as "open <target>": http, https and message addresses, documents
    /// and plain folders. Any other address does nothing.
    public func place(of url: URL, fileManager: FileManager = .default) -> LinkPlace {
        if url.isFileURL {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            let root = folder.standardizedFileURL.resolvingSymlinksInPath().path + "/"
            if path.hasPrefix(root) { return .inView }
            return PluginTargetOpen.url(path, fileManager: fileManager).url == nil ? .blocked : .outside
        }
        if url.scheme?.lowercased() == "about" { return .inView }
        return PluginTargetOpen.url(url.absoluteString, fileManager: fileManager).url == nil ? .blocked : .outside
    }
}

/// A local page of a plugin, with script off.
struct PluginPageView: NSViewRepresentable {
    let pages: PluginPages
    /// Changes when the owner opens the page again, so the view reads the file again.
    var reload: Int = 0
    /// The zoom of the page: 1 in the window, smaller in the panel.
    var zoom: CGFloat = 1

    func makeCoordinator() -> Coordinator { Coordinator(pages: pages) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        // The pages are local files. Nothing is kept between loads.
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.underPageBackgroundColor = .black
        view.pageZoom = zoom
        load(view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.pages != pages || context.coordinator.loaded != reload {
            context.coordinator.pages = pages
            context.coordinator.loaded = reload
            load(view)
        }
    }

    private func load(_ view: WKWebView) {
        view.loadFileURL(pages.index, allowingReadAccessTo: pages.folder)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var pages: PluginPages
        var loaded = 0
        init(pages: PluginPages) { self.pages = pages }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            switch pages.place(of: url) {
            case .inView:
                decisionHandler(.allow)
            case .outside:
                decisionHandler(.cancel)
                NSWorkspace.shared.open(url)
            case .blocked:
                decisionHandler(.cancel)
            }
        }
    }
}
