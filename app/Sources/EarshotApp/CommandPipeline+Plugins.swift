import EarshotCore
import Foundation

// The plugin hand-off of the command path (R-PL-2, R-PL-3, R-PL-5, docs/PLUGINS.md).
// It is in its own file, so that the body of CommandPipeline.finish changes by a few lines only.

/// What the pipeline logs and shows for one hand-off.
struct PluginHandOffResult {
    var heard: String
    var intent: String
    var ok: Bool
    var note: String
    var ms: Double
    /// The time of the read of "document" and "selection", if the plugin named one of them.
    var contextMs: Double?
}

extension CommandPipeline {
    /// Gives the words after the lead to the plugin, and returns at once: earshot never waits for the answer (R-PL-5).
    /// The log gets the lead and a word count, never the words (the plugin keeps them, if it must).
    /// On a sign-in, code or payment page, the plugin gets no context.
    /// The keys "document" and "selection" need a read of the front window. earshot reads them only if the plugin
    /// names them, and never on a sign-in, code or payment page. The values never go to the log.
    func handOffToPlugin(pluginID: String, lead: String, text: String, context: RouteContext) async -> PluginHandOffResult {
        let clock = Stopwatch()
        let count = text.split(whereSeparator: { $0.isWhitespace }).count
        let heard = "\(lead) (\(count) word\(count == 1 ? "" : "s"))"
        guard let plugins else {
            return PluginHandOffResult(heard: heard, intent: "plugin \(pluginID)", ok: false, note: "plugins are off", ms: clock.ms)
        }
        let name = plugins.name(of: pluginID)
        var available = Self.pluginContext(context)
        var contextMs: Double?
        let wants = Set(plugins.contextKeys(of: pluginID)).intersection(PluginContract.focusKeys)
        if !wants.isEmpty, !Self.sensitive(context) {
            let read = Stopwatch()
            let focus = await actions.pluginFocus(document: wants.contains("document"), selection: wants.contains("selection"))
            contextMs = read.ms
            if let d = focus.document { available["document"] = d }
            if let s = focus.selection { available["selection"] = s }
        }
        let why = plugins.handOff(pluginID: pluginID, lead: lead, text: text, available: available)
        return PluginHandOffResult(heard: heard, intent: "\(name) · \(lead)", ok: why == nil, note: why ?? "sent to \(name)",
                                   ms: clock.ms, contextMs: contextMs)
    }

    /// The context that earshot can give a plugin: the front app, the window title and the page address.
    /// Nothing on a sign-in, code or payment page (SafetyPolicy.sensitive).
    static func pluginContext(_ context: RouteContext) -> [String: String] {
        if sensitive(context) { return [:] }
        var out: [String: String] = [:]
        if let app = context.screen?.bundleID ?? context.frontBundleID { out["app"] = app }
        if let title = context.screen?.windowTitle, !title.isEmpty { out["windowTitle"] = title }
        if let url = context.screen?.url, !url.isEmpty { out["url"] = url }
        return out
    }

    /// True on a sign-in, code or payment page (SafetyPolicy.sensitive).
    static func sensitive(_ context: RouteContext) -> Bool {
        guard let screen = context.screen else { return false }
        return SafetyPolicy.sensitive(url: screen.url, elements: screen.elements) != nil
    }
}
