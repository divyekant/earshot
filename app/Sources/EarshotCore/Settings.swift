import Foundation

/// How a command starts.
public enum InputMode: String, Codable, Sendable, CaseIterable { case hold, alwaysOn }

/// The router's tier 2.
public enum Tier2: String, Codable, Sendable, CaseIterable { case off, jev }

/// The speech engine. "auto" is Apple (PR #32: under memory pressure, Parakeet decodes took seconds).
/// "parakeet" runs Apple always, and Parakeet only when the memory pressure is normal and its warm-up ended in time.
public enum EngineChoice: String, Codable, Sendable, CaseIterable { case auto, apple, parakeet }

/// The owner's settings. The management window edits them. Secrets (the Jev key) go to the Keychain, not here.
public struct EarshotSettings: Codable, Equatable, Sendable {
    public var mode: InputMode = .hold
    /// The hold key as a virtual key code. Default: right Option alone (61). Every Mac keyboard has it,
    /// and with no other modifier there is no wait for held modifiers (E0).
    public var holdKeyCode: UInt32 = 61
    /// True if the hold key is a modifier key alone. The input module then reads it from flagsChanged events.
    public var holdKeyIsModifierOnly: Bool = true
    public var holdKeyModifiers: UInt32 = 0
    public var engine: EngineChoice = .auto
    /// Parakeet model file. Empty means: use Hex's model file if it exists.
    public var parakeetModelPath: String = ""
    public var locale: String = "en_US"
    /// The router's tier 2, used only when the rules are unsure. "off" keeps all decisions on the Mac.
    /// "jev" sends the command words and the short list of labels to Jev, as text (R-MD-1, D-9).
    public var tier2: Tier2 = .off
    /// The longest wait for tier 2. After it, the rules result wins.
    public var tier2BudgetMs: Int = 1000
    /// Type the dictated text into any chat (R-NV-4). Typing is not Send. The own-chats-only rule is for live tests.
    public var typeIntoOthers: Bool = true
    public var showFeedback: Bool = true

    public init() {}
}

/// Reads and writes EarshotSettings, the catalogue and the names as JSON in Application Support.
public struct Store: Sendable {
    public let folder: URL

    public init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("earshot", isDirectory: true)
    }

    public func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func save<T: Encodable>(_ value: T, _ name: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    public var settings: EarshotSettings { load(EarshotSettings.self, "settings.json") ?? EarshotSettings() }
    public var apps: [AppEntry] { load([AppEntry].self, "apps.json") ?? [] }
    public var names: [NameEntry] { load([NameEntry].self, "names.json") ?? [] }
}
