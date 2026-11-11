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
}

extension CommandPipeline {
    /// Gives the words after the lead to the plugin, and returns at once: earshot never waits for the answer (R-PL-5).
    /// The log gets the lead and a word count, never the words (the plugin keeps them, if it must).
    /// On a sign-in, code or payment page, the plugin gets no context.
    func handOffToPlugin(pluginID: String, lead: String, text: String, context: RouteContext) -> PluginHandOffResult {
        let clock = Stopwatch()
        let count = text.split(whereSeparator: { $0.isWhitespace }).count
        let heard = "\(lead) (\(count) word\(count == 1 ? "" : "s"))"
        guard let plugins else {
            return PluginHandOffResult(heard: heard, intent: "plugin \(pluginID)", ok: false, note: "plugins are off", ms: clock.ms)
        }
        let name = plugins.name(of: pluginID)
        let why = plugins.handOff(pluginID: pluginID, lead: lead, text: text, available: Self.pluginContext(context))
        return PluginHandOffResult(heard: heard, intent: "\(name) · \(lead)", ok: why == nil, note: why ?? "sent to \(name)",
                                   ms: clock.ms)
    }

    /// The context that earshot can give a plugin: the front app, the window title and the page address.
    /// Nothing on a sign-in, code or payment page (SafetyPolicy.sensitive).
    static func pluginContext(_ context: RouteContext) -> [String: String] {
        if let screen = context.screen, SafetyPolicy.sensitive(url: screen.url, elements: screen.elements) != nil { return [:] }
        var out: [String: String] = [:]
        if let app = context.screen?.bundleID ?? context.frontBundleID { out["app"] = app }
        if let title = context.screen?.windowTitle, !title.isEmpty { out["windowTitle"] = title }
        if let url = context.screen?.url, !url.isEmpty { out["url"] = url }
        return out
    }
}
