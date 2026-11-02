// T1 owns this module. See docs/BUILD-PLAN.md.
// This file holds the logic with no audio device and no model, so that unit tests can check it.
import Foundation

/// Monotonic time in milliseconds.
enum SpeechClock {
    static func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    static func ms(since t0: UInt64) -> Double { Double(nowNs() &- t0) / 1_000_000 }
}

/// Errors of the speech module. The text goes to the activity log and the management window.
public struct SpeechError: Error, CustomStringConvertible, Equatable {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// Keeps the last part of the audio before the key press, so that the first word is not lost (E0).
/// `T` is one audio chunk. The caller gives the frame count of each chunk.
struct Preroll<T> {
    let limitFrames: Int64
    private(set) var items: [(T, Int64)] = []
    private(set) var frames: Int64 = 0

    init(limitFrames: Int64) { self.limitFrames = max(0, limitFrames) }

    mutating func add(_ item: T, frames count: Int64) {
        guard limitFrames > 0 else { return }
        items.append((item, count))
        frames += count
        // Remove old chunks while the rest still covers the limit.
        while items.count > 1, let first = items.first, frames - first.1 >= limitFrames {
            frames -= first.1
            items.removeFirst()
        }
    }

    /// Returns the chunks, oldest first, and empties the queue.
    mutating func drain() -> [T] {
        let out = items.map(\.0)
        items.removeAll()
        frames = 0
        return out
    }

    /// Returns the newest chunks that cover `wanted` frames, oldest first, and empties the queue.
    /// The older chunks are dropped.
    mutating func drainLast(frames wanted: Int64) -> [T] {
        var out: [T] = []
        var got: Int64 = 0
        for (item, count) in items.reversed() {
            if got >= wanted { break }
            out.append(item)
            got += count
        }
        items.removeAll()
        frames = 0
        return out.reversed()
    }
}

/// Silence at the end of the audio. The engines can drop the last word when the audio stops
/// right after the speech (E0; E2 section 6, item 6: "Udita's ch"). Silence costs no wait,
/// because the engines do not read it in real time.
enum TailPad {
    static let seconds = 0.3
    /// Real audio that the microphone still records after key release, before the silence. The microphone gives
    /// audio in blocks of up to about 100 ms, and people often release the key on the last sound of a word.
    /// Live test 2026-11-02: one command was heard as "Open up", with the end lost.
    static let captureSeconds = 0.1

    static func frames(sampleRate: Double, seconds: Double = TailPad.seconds) -> Int {
        max(0, Int((sampleRate * seconds).rounded()))
    }
}

/// Joins the final and the volatile results of Apple SpeechTranscriber.
/// A final result replaces the volatile text that came before it.
struct TranscriptJoin {
    private(set) var finalText = ""
    private(set) var pending = ""

    /// Adds one result and returns the text so far (final plus volatile).
    mutating func add(_ text: String, isFinal: Bool) -> String {
        if isFinal { finalText += text; pending = "" } else { pending = text }
        return finalText + pending
    }

    /// If the engine sends no final result for the last words, the volatile text stays.
    var text: String { finalText + pending }
}

enum TextClean {
    /// Removes the space at the two ends and joins runs of white space into one space.
    static func clean(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// Decides when the Parakeet engine makes a new partial text. Parakeet has no stream mode in this
/// build, so the engine runs the model again on all the audio so far. A run takes about 35 ms (E2).
struct PartialSchedule {
    /// The engine makes a partial only after this much new audio.
    var minNewSeconds = 0.4
    /// No partial for audio shorter than this: one word gives poor text.
    var minTotalSeconds = 0.6
    /// No partials for long audio, so that each run stays short. The final run still reads all audio.
    var maxTotalSeconds = 30.0

    func due(totalFrames: Int, lastFrames: Int, sampleRate: Double) -> Bool {
        let total = Double(totalFrames) / sampleRate
        let added = Double(totalFrames - lastFrames) / sampleRate
        return total >= minTotalSeconds && total <= maxTotalSeconds && added >= minNewSeconds
    }
}
