import EarshotCore
import Foundation

/// The result of an enrolment, for the management window.
public struct Enrolment: Sendable {
    public let profile: VoiceProfile
    /// For each take, the lowest score of the other takes on it (E5). A take above the wake limit is left out.
    public let takeScores: [Double]
    /// The number of takes that give a template.
    public let templatesKept: Int

    /// One line for the management window.
    public var summary: String {
        var text = "earshot knows your voice and the sound of your phrase (\(templatesKept) of \(takeScores.count) phrases)."
        let left = takeScores.count - templatesKept
        if left > 0 {
            text += " It left out \(left) phrase\(left == 1 ? "" : "s") that sounded different from the others."
        }
        if profile.selfScore < 0.5 {
            text += " The phrases differ a lot. Teach it again in a quiet room for a better match."
        }
        return text
    }
}
