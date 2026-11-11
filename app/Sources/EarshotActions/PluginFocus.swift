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
        if document, let window = AX.window(app), let raw = AX.string(window, "AXDocument") {
            out.document = PluginContract.documentPath(raw)
        }
        if selection, let focused = AX.focused(app), AX.role(focused) != "AXSecureTextField",
           AX.subrole(focused) != "AXSecureTextField" {
            out.selection = PluginContract.selectionText(AX.string(focused, "AXSelectedText"))
        }
        return out
    }
}
