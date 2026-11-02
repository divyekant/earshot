import AVFoundation
import Foundation

/// Gives the level of each audio frame in dB full scale. The always-on trigger uses it.
public protocol LevelSource: AnyObject {
    /// Starts. `onLevel` gets one value for each frame, on any thread, in order.
    func start(frameMs: Double, onLevel: @escaping @Sendable (Double) -> Void) throws
    func stop()
}

/// Reads the levels from the microphone. It keeps no audio, and no audio leaves the Mac (R-MD-1).
/// It computes one number for each frame and drops the samples at once.
/// The speech engine reads the microphone on its own; macOS lets two readers share the input device.
public final class MicrophoneLevels: LevelSource, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var running = false
    private var pending: [Float] = []

    public init() {}

    public func start(frameMs: Double, onLevel: @escaping @Sendable (Double) -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        if running { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw InputError("no microphone input (check the Microphone permission and the input device)")
        }
        let frame = max(1, Int(format.sampleRate * frameMs / 1000))
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(frame * 4), format: format) { [weak self] buffer, _ in
            self?.push(buffer, frame: frame, onLevel: onLevel)
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            throw InputError("the microphone did not start: \(error.localizedDescription)")
        }
        running = true
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard running else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        pending.removeAll()
        running = false
    }

    private func push(_ buffer: AVAudioPCMBuffer, frame: Int, onLevel: @Sendable (Double) -> Void) {
        // The audio thread calls this. Only the first channel counts.
        guard let data = buffer.floatChannelData else { return }
        let samples = UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))
        var levels: [Double] = []
        lock.lock()
        pending.append(contentsOf: samples)
        while pending.count >= frame {
            levels.append(SpeechDetector.db(pending[0..<frame]))
            pending.removeFirst(frame)
        }
        lock.unlock()
        for l in levels { onLevel(l) }
    }
}
