import AVFoundation
import Foundation

/// Reads the microphone, converts the audio to the format of one engine, and passes it on
/// only between `begin` and `end`. No audio is saved, and no audio leaves the Mac (R-MD-1).
/// It keeps the last 250 ms before `begin`, so that the first word is not lost (E0).
final class MicrophoneFeed: @unchecked Sendable {
    let format: AVAudioFormat
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var deliver: ((AVAudioPCMBuffer) -> Void)?
    private var preroll: Preroll<AVAudioPCMBuffer>
    private var running = false

    init(format: AVAudioFormat, prerollSeconds: Double = 0.25) {
        self.format = format
        preroll = Preroll(limitFrames: Int64(format.sampleRate * prerollSeconds))
    }

    /// Opens the microphone. macOS shows the microphone indicator while it is open.
    func start() throws {
        lock.lock(); defer { lock.unlock() }
        if running { return }
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw SpeechError("no microphone input (check the Microphone permission and the input device)")
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            self?.push(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            throw SpeechError("the microphone did not start: \(error.localizedDescription)")
        }
        running = true
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard running else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        running = false
        deliver = nil
        _ = preroll.drain()
    }

    var isRunning: Bool { lock.withLock { running } }

    /// Starts to pass audio to `sink`, first the preroll.
    func begin(_ sink: @escaping (AVAudioPCMBuffer) -> Void) {
        lock.lock(); defer { lock.unlock() }
        for b in preroll.drain() { sink(b) }
        deliver = sink
    }

    /// Stops to pass audio. Gives `TailPad.seconds` of silence to the sink as the last buffer.
    func end() {
        let sink = lock.withLock {
            let s = deliver
            deliver = nil
            return s
        }
        if let sink, let pad = AudioUtil.silence(format: format, frames: TailPad.frames(sampleRate: format.sampleRate)) {
            sink(pad)
        }
    }

    private func push(_ buffer: AVAudioPCMBuffer) {
        // The audio thread calls this. The converter is used only here.
        guard let out = convert(buffer), out.frameLength > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        if let deliver { deliver(out) } else { preroll.add(out, frames: Int64(out.frameLength)) }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return nil }
        return AudioUtil.convert(buffer, with: converter, to: format, endOfStream: false)
    }
}

enum AudioUtil {
    /// 16 kHz mono 32-bit float: the input of Parakeet.
    static let parakeetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    static func silence(format: AVAudioFormat, frames: Int) -> AVAudioPCMBuffer? {
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        for b in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            if let data = b.mData { memset(data, 0, Int(b.mDataByteSize)) }
        }
        return buffer
    }

    /// Converts one buffer. For a stream, `endOfStream` is false, so that the converter keeps its state.
    static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat,
                        endOfStream: Bool) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var given = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if given {
                inputStatus.pointee = endOfStream ? .endOfStream : .noDataNow
                return nil
            }
            given = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : out
    }

    /// The first channel of a float buffer, as an array.
    static func floats(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    }

    /// Reads an audio file as 16 kHz mono float samples, for Parakeet.
    static func readSamples16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let src = file.processingFormat
        guard let buf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
        try file.read(into: buf)
        if src == parakeetFormat { return floats(buf) }
        guard let converter = AVAudioConverter(from: src, to: parakeetFormat),
              let out = convert(buf, with: converter, to: parakeetFormat, endOfStream: true) else {
            throw SpeechError("cannot convert \(url.lastPathComponent) to 16 kHz mono")
        }
        return floats(out)
    }
}
