import EarshotCore

// Item 10 of the gap list (2026-11-11): the follow-up window must not talk back to speech that was not for earshot.

extension CommandPipeline {
    /// True if a turn that is "not a command" stays quiet: an always-on follow-up turn, which the owner's voice opened
    /// with no wake phrase, and whose words have no command word. The owner often talks on after a command, and that
    /// talk is not for earshot. So the turn shows no note and plays no sound. The log keeps the record.
    /// These turns still get the note and the fail sound, because the owner spoke to earshot on purpose:
    /// - a wake turn, also a follow-up turn in which the owner said the phrase again (`wake` is not nil),
    /// - a hold-key turn,
    /// - a turn with a command word that earshot did not do, for example a blocked press or a label that is not there.
    static func isFollowUpMiss(mode: InputMode, wake: WakeHit?, commandWord: Bool) -> Bool {
        mode == .alwaysOn && wake == nil && !commandWord
    }
}
