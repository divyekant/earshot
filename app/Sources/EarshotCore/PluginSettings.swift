import Foundation

/// One setting of a plugin that the owner can change in the earshot window (docs/PLUGINS.md 3.2).
/// Version 1 has one kind: a choice of fixed values, for example "alert", "list" or "off".
public struct PluginSetting: Codable, Hashable, Sendable, Identifiable {
    /// The place of the value in settings.json: names joined by ".", for example "rules.time".
    public var key: String
    /// The line in the window, for example "A reminder reaches its time".
    public var label: String
    /// The values that the owner can choose.
    public var choices: [String]
    /// The value if settings.json does not have the key.
    public var `default`: String
    /// An optional group heading, for example "When to tell you".
    public var group: String?

    public var id: String { key }

    public init(key: String, label: String, choices: [String], default value: String, group: String? = nil) {
        self.key = key; self.label = label; self.choices = choices; self.default = value; self.group = group
    }

    /// The most settings of one plugin.
    public static let maxCount = 30

    /// The parts of the key, or nil for a bad key. Each part uses only A-Z, a-z, 0-9 and "_".
    public var path: [String]? {
        let parts = key.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let ok = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_")
        guard !parts.isEmpty, parts.count <= 4,
              parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(ok.contains) }) else { return nil }
        return parts
    }

    /// The problems of a list of settings. A plugin with a problem does not start.
    public static func problems(_ list: [PluginSetting]) -> [String] {
        var out: [String] = []
        if list.count > maxCount { out.append("more than \(maxCount) settings") }
        var seen = Set<String>()
        for s in list {
            if s.path == nil { out.append("bad setting key \"\(s.key)\"") }
            if !seen.insert(s.key).inserted { out.append("the setting \"\(s.key)\" is there twice") }
            if s.choices.isEmpty { out.append("the setting \"\(s.key)\" has no choices") }
            if !s.choices.contains(s.default) { out.append("the default of \"\(s.key)\" is not one of its choices") }
            if s.label.isEmpty { out.append("the setting \"\(s.key)\" has no label") }
        }
        return out
    }
}

/// Reads and writes the values of plugin settings in settings.json in the data folder of the plugin.
/// A write changes only its key, and keeps all other keys of the file. The plugin reads the file again when it
/// changes.
public struct PluginSettingsFile: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// The file of one plugin: <store>/plugin-data/<id>/settings.json.
    public init(catalog: PluginCatalog, pluginID: String) {
        url = catalog.dataFolder.appendingPathComponent(pluginID, isDirectory: true).appendingPathComponent("settings.json")
    }

    private func object() -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    /// The value of the setting: the value in the file if it is one of the choices, else the default.
    public func value(_ s: PluginSetting) -> String {
        guard let path = s.path else { return s.default }
        var node: Any? = object()
        for part in path { node = (node as? [String: Any])?[part] }
        if let v = node as? String, s.choices.contains(v) { return v }
        return s.default
    }

    /// Writes one value. A value that is not one of the choices is refused.
    public func set(_ s: PluginSetting, to value: String) throws {
        guard let path = s.path else { throw SettingError.badKey }
        guard s.choices.contains(value) else { throw SettingError.notAChoice }
        func put(_ obj: [String: Any], _ rest: ArraySlice<String>) -> [String: Any] {
            var o = obj
            guard let first = rest.first else { return o }
            if rest.count == 1 { o[first] = value } else { o[first] = put(o[first] as? [String: Any] ?? [:], rest.dropFirst()) }
            return o
        }
        let new = put(object(), path[...])
        let data = try JSONSerialization.data(withJSONObject: new, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public enum SettingError: Error { case badKey, notAChoice }
}
