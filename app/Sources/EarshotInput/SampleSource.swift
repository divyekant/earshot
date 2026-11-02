import AVFoundation
import Foundation

/// Gives 16 kHz mono float samples from the microphone. The wake trigger uses it (R-ON-1).
public protocol SampleSource: AnyObject {
    /// Starts. `onSamples` gets the samples in order, on any thread.
    func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws
    func stop()
}

/// Reads the microphone and converts the audio to 16 kHz mono. It saves no audio, and no audio leaves the Mac (R-MD-1).
/// The speech engine reads the microphone on its own. macOS lets two readers share the input device.
public final class MicrophoneSamples: SampleSource, @unchecked Sendable {
    public static let sampleRate = 16000.0
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var running = false
    // Used only on the audio thread.
    private var converter: AVAudioConverter?
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: MicrophoneSamples.sampleRate,
                                       channels: 1, interleaved: false)!

    public init() {}

    public func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        if running { return }
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw InputError("no microphone input (check the Microphone permission and the input device)")
        }
        // About 100 ms for each block.
        let block = AVAudioFrameCount(max(256, inFormat.sampleRate / 10))
        input.installTap(onBus: 0, bufferSize: block, format: inFormat) { [weak self] buffer, _ in
            guard let self, let samples = self.convert(buffer), !samples.isEmpty else { return }
            onSamples(samples)
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
        running = false
    }

    /// Converts one block to 16 kHz mono. The converter keeps its state between blocks.
    private func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        if buffer.format == format { return Self.floats(buffer) }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var given = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if given {
                inputStatus.pointee = .noDataNow
                return nil
            }
            given = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : Self.floats(out)
    }

    private static func floats(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    }
}
