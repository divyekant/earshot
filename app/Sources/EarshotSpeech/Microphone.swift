import AVFoundation
import Foundation

/// Reads the microphone, converts the audio to the format of one engine, and passes it on
/// only between `begin` and `end`. No audio is saved, and no audio leaves the Mac (R-MD-1).
/// It gives the last 450 ms before `begin`, so that the first word is not lost (E0). Hex measured 450 ms: a key press
/// often comes after the first sound of the word.
/// It keeps the last 3 s in memory, for a turn that the wake phrase opens: that turn starts at the phrase (D-11).
/// In hold mode, it closes the microphone `MicIdle.holdSeconds` after each turn (0: at once), so that the macOS
/// microphone indicator is on only while the key is down. The next `begin` opens it again, with no preroll.
final class MicrophoneFeed: @unchecked Sendable {
    let format: AVAudioFormat
    /// The usual audio before `begin`.
    let prerollSeconds: Double
    /// The audio that the feed keeps in memory, and the longest preroll.
    static let keepSeconds = 3.0
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var deliver: ((AVAudioPCMBuffer) -> Void)?
    private var preroll: Preroll<AVAudioPCMBuffer>
    private var nextPreroll: Double?
    private var nextCapture: Double?
    private var running = false
    /// True if the idle timer closed the microphone. `begin` then opens it again.
    private var closedForIdle = false
    private let idle = MicIdleTimer()

    init(format: AVAudioFormat, prerollSeconds: Double = 0.45) {
        self.format = format
        self.prerollSeconds = prerollSeconds
        preroll = Preroll(limitFrames: Int64(format.sampleRate * max(prerollSeconds, Self.keepSeconds)))
    }

    /// The next `begin` gives this much audio from before it (at most `keepSeconds`). Then the usual preroll again.
    func setNextPreroll(seconds: Double) {
        lock.withLock { nextPreroll = min(max(seconds, prerollSeconds), Self.keepSeconds) }
    }

    /// The next `end(captureSeconds:)` waits this long instead (always-on: 0). Then the usual value again.
    func setNextCapture(seconds: Double) {
        lock.withLock { nextCapture = max(0, seconds) }
    }

    /// Closes the microphone after this time with no turn. Nil keeps it open: always-on needs the audio before the
    /// wake phrase. If the microphone is closed for idle and the value is nil, the microphone opens again.
    func setIdleClose(seconds: Double?) {
        idle.seconds = seconds
        if seconds == nil {
            if lock.withLock({ closedForIdle }) { try? start() }
        } else {
            armIdle()
        }
    }

    /// Opens the microphone. macOS shows the microphone indicator while it is open.
    func start() throws {
        try open()
        armIdle()
    }

    private func open() throws {
        lock.lock(); defer { lock.unlock() }
        try openLocked()
    }

    /// Call with the lock held.
    private func openLocked() throws {
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
        closedForIdle = false
    }

    func stop() {
        idle.cancel()
        lock.lock(); defer { lock.unlock() }
        closedForIdle = false
        guard running else { return }
        close()
    }

    /// Call with the lock held.
    private func close() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        running = false
        deliver = nil
        _ = preroll.drain()
    }

    /// True if the microphone is open, or closed for idle (then `begin` opens it again).
    var isRunning: Bool { lock.withLock { running || closedForIdle } }

    /// Starts the idle timer if the feed is open and passes no audio.
    private func armIdle() {
        guard lock.withLock({ running && deliver == nil }) else { return }
        idle.arm { [weak self] in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            guard self.running, self.deliver == nil else { return }
            self.close()
            self.closedForIdle = true
            NSLog("earshot mic: closed (hold mode)")
        }
    }

    /// Starts to pass audio to `sink`, first the preroll.
    /// - Returns: the length of the preroll that the sink got, in seconds. It can be a little longer than asked,
    ///   because the feed keeps whole audio blocks.
    /// - Throws: if the microphone was closed for idle and does not open again.
    @discardableResult
    func begin(_ sink: @escaping (AVAudioPCMBuffer) -> Void) throws -> Double {
        idle.cancel()
        lock.lock(); defer { lock.unlock() }
        // In the same lock as `deliver`, so that a late idle timer cannot close the microphone of this turn.
        if closedForIdle {
            let t0 = SpeechClock.nowNs()
            try openLocked()
            NSLog("earshot mic: opened again after idle in %.1f ms (no preroll for this command)", SpeechClock.ms(since: t0))
        }
        let seconds = nextPreroll ?? prerollSeconds
        nextPreroll = nil
        nextCapture = nil
        var frames: AVAudioFrameCount = 0
        for b in preroll.drainLast(frames: Int64(format.sampleRate * seconds)) {
            frames += b.frameLength
            sink(b)
        }
        deliver = sink
        return Double(frames) / format.sampleRate
    }

    /// Waits `captureSeconds` so that the last audio block arrives, then calls `end()`.
    func end(captureSeconds: Double) async {
        let captureSeconds = lock.withLock { () -> Double in
            defer { nextCapture = nil }
            return nextCapture ?? captureSeconds
        }
        if captureSeconds > 0 { try? await Task.sleep(nanoseconds: UInt64(captureSeconds * 1e9)) }
        end()
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
        armIdle()
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

/// Runs one action after `seconds` with no new `arm` or `cancel`. A late run of an old timer does nothing.
final class MicIdleTimer: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "earshot.mic.idle")
    private var stored: Double?
    private var generation = 0

    /// The idle time. Nil turns the timer off and cancels a timer that runs.
    var seconds: Double? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue; generation += 1 } }
    }

    /// Starts the timer again. It does nothing if `seconds` is nil.
    func arm(_ action: @escaping @Sendable () -> Void) {
        let (gen, wait) = lock.withLock { () -> (Int, Double?) in generation += 1; return (generation, stored) }
        guard let wait else { return }
        queue.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.lock.withLock({ self.generation == gen }) else { return }
            action()
        }
    }

    /// Stops the timer that runs.
    func cancel() { lock.withLock { generation += 1 } }
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
