import EarshotCore
import EarshotInput
import Foundation

/// Joins the numbers of each always-on turn (`WakeTrigger.onRecord`) with the activity record of the same turn, and
/// keeps them in the turn store for 7 days (E7). It keeps no audio. Use it on the main thread.
final class TurnRecorder {
    private let folder: Store
    private(set) var store: TurnStore?
    /// The record of the turn that ends now, until the pipeline gives its activity record.
    private var pending: TurnRecord?

    init(store: Store, settings: EarshotSettings) {
        folder = store
        apply(settings)
    }

    /// Turns the recorder on or off. Off deletes the kept records.
    func apply(_ settings: EarshotSettings) {
        guard settings.recordTurns else {
            pending = nil
            (store ?? TurnStore(store: folder, keepsFrames: false)).removeAll()
            store = nil
            return
        }
        if store?.keepsFrames != settings.recordWakeFrames {
            store = TurnStore(store: folder, keepsFrames: settings.recordWakeFrames)
        }
    }

    /// The trigger gave the numbers of a turn. A turn with an activity record waits for it (`take`, `write`). The
    /// others go to the store now.
    func hold(_ record: TurnRecord) {
        if let old = pending { write(old, activity: nil) }
        if Self.waitsForActivity(record) { pending = record } else { write(record, activity: nil) }
    }

    /// The record that waits for its activity record, or nil.
    func take() -> TurnRecord? {
        defer { pending = nil }
        return pending
    }

    /// Adds the activity record, if there is one, and keeps the record.
    func write(_ record: TurnRecord?, activity: ActivityRecord?) {
        guard var record, let store else { return }
        if let activity { record.add(activity: activity) }
        store.append(record)
    }

    /// True if the pipeline makes an activity record for this turn: a turn that ended, a rejected wake, and a turn
    /// that the voice check dropped.
    static func waitsForActivity(_ record: TurnRecord) -> Bool {
        record.outcome == "end" || record.kind == .rejectedWake
            || record.outcome.hasPrefix(WakeTrigger.otherVoice) || record.outcome.hasPrefix(WakeTrigger.tooShort)
    }
}
