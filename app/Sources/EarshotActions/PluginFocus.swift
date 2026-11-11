import ApplicationServices
import EarshotCore
import Foundation

// The context keys "document" and "selection" for plugins (docs/PLUGINS.md, section 5.1). Read only.

extension EarshotActionRunner {
    /// The file path of the document in the front window (AXDocument), and the selected text of the focused element
    /// (AXSelectedText). earshot reads each one only if the plugin names its key. Nil if the app gives none.
    /// A password field gives no selection.
    public func pluginFocus(document: Bool, selection: Bool) async -> PluginFocus {
        guard document || selection, AX.trusted(), let pid = AX.frontPid() else { return PluginFocus() }
        let app = AX.appElement(pid)
        var out = PluginFocus()
        if document, let window = AX.window(app) {
            if let raw = AX.string(window, "AXDocument") {
                out.document = PluginContract.documentPath(raw)
            } else if let title = AX.string(window, "AXTitle") {
                // A file window with no AXDocument (Finder): read the file addresses of its items.
                out.document = PluginContract.windowFolder(title: title, urls: AX.fileURLs(in: window))
            }
        }
        if selection, let focused = AX.focused(app), AX.role(focused) != "AXSecureTextField",
           AX.subrole(focused) != "AXSecureTextField" {
            out.selection = PluginContract.selectionText(AX.string(focused, "AXSelectedText"))
        }
        return out
    }
}

extension AX {
    /// The file addresses (AXURL with "file:") of the elements of a window. Web content is skipped. The walk stops
    /// after `budgetMs` or `maxNodes` elements.
    static func fileURLs(in window: AXUIElement, budgetMs: Int = 80, maxNodes: Int = 800) -> [String] {
        let t0 = Clock.nowNs()
        var queue: [AXUIElement] = [window]
        var index = 0
        var out: [String] = []
        while index < queue.count, index < maxNodes, Clock.ms(since: t0) < Double(budgetMs) {
            let element = queue[index]
            index += 1
            if role(element) == "AXWebArea" { continue }
            if let u = copy(element, "AXURL") {
                let s = (u as? URL)?.absoluteString ?? text(u)
                if let s, s.hasPrefix("file:") { out.append(s) }
            }
            queue.append(contentsOf: elements(element, "AXChildren"))
        }
        return out
    }
}
