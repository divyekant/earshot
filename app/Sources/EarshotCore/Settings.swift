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
    /// The screenshot fallback for clicks (D-10). Off by default. When it is on, and a hold-key click finds no target,
    /// earshot sends one picture of the front window, with numbers drawn on it, to Jev. Never on a sign-in, code
    /// or payment page, and never in always-on mode. It needs the Jev key and the Screen Recording permission.
    public var jevSeesScreen: Bool = false
    /// The longest wait for the screenshot fallback. After it, earshot does nothing.
    public var jevScreenBudgetMs: Int = 1500
    /// Type the dictated text into any chat (R-NV-4). Typing is not Send. The own-chats-only rule is for live tests.
    public var typeIntoOthers: Bool = true
    public var showFeedback: Bool = true
    /// A short system sound for each result: done, sent, or failed (not sure, blocked).
    public var playSounds: Bool = true
    /// The phrase that starts a command in always-on mode (R-ON-1, D-11). Known words work best.
    public var wakePhrase: String = WakePhrase.defaultPhrase
    /// The lowest voice score (cosine similarity to the owner's enrolled voice) of a turn with 1 s of speech or less,
    /// for example "send" alone (R-ON-3, E6). The live trial of 2026-11-02 gave 0.50 to 0.73 for the owner and 0.06
    /// for another voice. Tune it from the voice scores in the activity log.
    public var voiceThreshold: Double = 0.35
    /// The lowest voice score of the wake phrase alone that starts an always-on turn (E6). At the end of the turn,
    /// the voice of the whole turn decides. A lower score is another voice, and nothing starts. The E6 bench found
    /// 0.10 best, but in the live run of 2026-11-03 room sounds matched the phrase every 4 to 6 s with scores up to
    /// 0.29. Lower it only if such matches stop.
    public var voiceGate: Double = 0.35
    /// The lowest voice score of a whole turn with 2 s of speech or more (E6). A longer clip gives a surer score,
    /// so this limit is higher than `voiceThreshold`, which is the limit for 1 s of speech or less. Between 1 s and
    /// 2 s, the limit goes up in a line. An always-on "send" needs a turn that passed (D-12).
    public var turnVoiceThreshold: Double = 0.42
    /// The turn recorder (E7): for each always-on turn and each rejected wake, earshot keeps the numbers of the turn
    /// for 7 days in the `turns` folder of the store folder. No audio. Turning it off deletes the kept numbers.
    public var recordTurns: Bool = true
    /// The turn recorder also keeps the wake frames: the encoder frames of the spotter around each match, as the
    /// templates in `voice.json`. earshot cannot play them back.
    public var recordWakeFrames: Bool = true

    public init() {}

    /// The limits of the owner voice check, from these settings.
    public var voiceRule: VoiceRule { VoiceRule(gate: voiceGate, short: voiceThreshold, turn: turnVoiceThreshold) }

    /// Reads each setting if it is in the file, else keeps the default. So a new setting does not reset the old ones.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ value: inout T) {
            if let v = try? c.decodeIfPresent(T.self, forKey: key) { value = v }
        }
        read(.mode, &mode)
        read(.holdKeyCode, &holdKeyCode)
        read(.holdKeyIsModifierOnly, &holdKeyIsModifierOnly)
        read(.holdKeyModifiers, &holdKeyModifiers)
        read(.engine, &engine)
        read(.parakeetModelPath, &parakeetModelPath)
        read(.locale, &locale)
        read(.tier2, &tier2)
        read(.tier2BudgetMs, &tier2BudgetMs)
        read(.jevSeesScreen, &jevSeesScreen)
        read(.jevScreenBudgetMs, &jevScreenBudgetMs)
        read(.typeIntoOthers, &typeIntoOthers)
        read(.showFeedback, &showFeedback)
        read(.playSounds, &playSounds)
        read(.wakePhrase, &wakePhrase)
        read(.voiceThreshold, &voiceThreshold)
        read(.voiceGate, &voiceGate)
        read(.turnVoiceThreshold, &turnVoiceThreshold)
        read(.recordTurns, &recordTurns)
        read(.recordWakeFrames, &recordWakeFrames)
    }
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
