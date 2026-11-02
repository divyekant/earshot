import EarshotCore

/// The parts of earshot that must start again after a settings change.
/// AppController compares the new settings with the settings that the running parts use (R-ON-1, R-ON-4).
struct SettingsRestart: OptionSet, Equatable {
    let rawValue: Int

    /// The router and the screenshot picker (Jev).
    static let jev = SettingsRestart(rawValue: 1 << 0)
    /// The speech engine. Its microphone closes and a new engine loads.
    static let engine = SettingsRestart(rawValue: 1 << 1)
    /// The input triggers: the hold key, and the wake phrase listener of always-on mode.
    static let input = SettingsRestart(rawValue: 1 << 2)

    /// The parts to start again for the change from `old` to `new`.
    static func needed(from old: EarshotSettings, to new: EarshotSettings) -> SettingsRestart {
        var parts: SettingsRestart = []
        if new.tier2 != old.tier2 || new.tier2BudgetMs != old.tier2BudgetMs || new.jevSeesScreen != old.jevSeesScreen
            || new.jevScreenBudgetMs != old.jevScreenBudgetMs {
            parts.insert(.jev)
        }
        if new.engine != old.engine || new.parakeetModelPath != old.parakeetModelPath || new.locale != old.locale {
            parts.insert(.engine)
        }
        if new.mode != old.mode || new.holdKeyCode != old.holdKeyCode || new.holdKeyIsModifierOnly != old.holdKeyIsModifierOnly
            || new.holdKeyModifiers != old.holdKeyModifiers || new.wakePhrase != old.wakePhrase
            || new.voiceThreshold != old.voiceThreshold {
            parts.insert(.input)
        }
        return parts
    }
}
