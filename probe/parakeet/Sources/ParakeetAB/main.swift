import AVFoundation
import CTranscribe
import Foundation

// parakeet-ab: transcribes the E2 audio files with Parakeet, through transcribe.cpp.
// It reads the model file of Hex and does not change it. It sends nothing over the network.
// Output: probe/logs/e2-asr-parakeet-<time>.jsonl, for `earshot-probe e2-asr-score`.
//
// swift run -c release parakeet-ab [--model <file.gguf>]

struct AudioItem: Codable {
    let file: String
    let id: Int
    let kind: String
    let voice: String
    let words: String
}

struct AudioManifest: Codable {
    let builtAt: String
    let items: [AudioItem]
}

/// probe/parakeet/Sources/ParakeetAB/main.swift: four levels up is probe/.
let probeDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let logs = probeDir.appendingPathComponent("logs")
let audioDir = logs.appendingPathComponent("e2-audio")
let hexModels = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/hex/models")

func option(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

func fail(_ text: String) -> Never {
    print("Error: \(text)")
    exit(1)
}

func ms(since t0: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000 }

/// The Parakeet GGUF file in the model folder of Hex, unless --model names a file.
func findModel() -> String? {
    if let m = option("--model") { return m }
    guard let walk = FileManager.default.enumerator(atPath: hexModels.path) else { return nil }
    while let f = walk.nextObject() as? String {
        let name = f.lowercased()
        if name.contains("parakeet"), name.hasSuffix(".gguf") { return hexModels.appendingPathComponent(f).path }
    }
    return nil
}

/// The memory that this process uses, in MB.
func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}

/// Mono float samples at 16 kHz, in -1...1.
func samples(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let src = file.processingFormat
    guard let buf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
    try file.read(into: buf)
    if src.sampleRate == 16000, src.channelCount == 1, src.commonFormat == .pcmFormatFloat32, let data = buf.floatChannelData {
        return Array(UnsafeBufferPointer(start: data[0], count: Int(buf.frameLength)))
    }
    guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
          let converter = AVAudioConverter(from: src, to: target),
          let out = AVAudioPCMBuffer(pcmFormat: target,
                                     frameCapacity: AVAudioFrameCount(Double(buf.frameLength) * 16000 / src.sampleRate + 1024))
    else { return [] }
    var given = false
    var error: NSError?
    converter.convert(to: out, error: &error) { _, status in
        if given {
            status.pointee = .endOfStream
            return nil
        }
        given = true
        status.pointee = .haveData
        return buf
    }
    guard let data = out.floatChannelData else { return [] }
    return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
}

func statusText(_ s: transcribe_status) -> String {
    String(cString: transcribe_status_string(Int32(truncatingIfNeeded: s.rawValue)))
}

// MARK: - Main

guard let data = try? Data(contentsOf: audioDir.appendingPathComponent("manifest.json")),
      let manifest = try? JSONDecoder().decode(AudioManifest.self, from: data) else {
    fail("probe/logs/e2-audio/manifest.json does not exist. Run: swift run earshot-probe e2-say")
}
guard let modelPath = findModel() else {
    fail("no Parakeet .gguf file in \(hexModels.path). Give one with --model <file>.")
}

transcribe_log_set(nil, nil)
let before = footprintMB()
let tLoad = DispatchTime.now().uptimeNanoseconds
var opened: OpaquePointer?
let openStatus = transcribe_open(modelPath, nil, nil, &opened)
guard openStatus == TRANSCRIBE_OK, let session = opened else {
    fail("transcribe.cpp could not load \(modelPath): \(statusText(openStatus))")
}
let loadMs = ms(since: tLoad)
let model = transcribe_get_model(session)
let arch = model.flatMap { transcribe_model_arch_string($0) }.map { String(cString: $0) } ?? "?"
let backend = model.flatMap { transcribe_model_backend($0) }.map { String(cString: $0) } ?? "?"
print("Model: \(URL(fileURLWithPath: modelPath).lastPathComponent) (\(arch), backend \(backend)), transcribe.cpp \(String(cString: transcribe_version()))")
print("Load: \(Int(loadMs.rounded())) ms. Memory: \(Int(before.rounded())) MB before, \(Int(footprintMB().rounded())) MB after.")

func run(_ pcm: [Float]) -> (String, Double, transcribe_status) {
    let t0 = DispatchTime.now().uptimeNanoseconds
    let status = pcm.withUnsafeBufferPointer { transcribe_run(session, $0.baseAddress, Int32($0.count), nil) }
    let elapsed = ms(since: t0)
    guard status == TRANSCRIBE_OK, let c = transcribe_full_text(session) else { return ("", elapsed, status) }
    return (String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines), elapsed, status)
}

// Warm-up, not logged: the first run prepares the GPU code.
if let first = manifest.items.first, let pcm = try? samples(audioDir.appendingPathComponent(first.file)) {
    let (_, warm, _) = run(pcm)
    print("Warm-up run: \(Int(warm.rounded())) ms")
}

let stamp: String = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd-HHmmss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f.string(from: Date())
}()
let logURL = logs.appendingPathComponent("e2-asr-parakeet-\(stamp).jsonl")
FileManager.default.createFile(atPath: logURL.path, contents: nil)
guard let log = try? FileHandle(forWritingTo: logURL) else { fail("cannot write \(logURL.path)") }

var times: [Double] = []
var failures = 0
for item in manifest.items {
    let url = audioDir.appendingPathComponent(item.file)
    guard let pcm = try? samples(url), !pcm.isEmpty else {
        print("  cannot read \(item.file)")
        continue
    }
    let (text, elapsed, status) = run(pcm)
    if status != TRANSCRIBE_OK {
        failures += 1
        print("  \(item.file): \(statusText(status))")
    }
    times.append(elapsed)
    let entry: [String: Any] = [
        "event": "asr", "engine": "parakeet", "file": item.file, "id": item.id, "voice": item.voice,
        "text": text, "ms": elapsed, "audio_ms": Double(pcm.count) / 16.0,
        "at": ISO8601DateFormatter().string(from: Date()),
    ]
    if var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) {
        line.append(0x0A)
        log.write(line)
    }
}
transcribe_session_free(session)

let sorted = times.sorted()
let median = sorted.isEmpty ? 0 : sorted[(sorted.count - 1) / 2]
let p90 = sorted.isEmpty ? 0 : sorted[max(0, Int((0.9 * Double(sorted.count)).rounded(.up)) - 1)]
print("Parakeet: \(times.count) files, \(failures) failures. Median \(Int(median.rounded())) ms, slowest 1 in 10 \(Int(p90.rounded())) ms.")
print("Peak memory now: \(Int(footprintMB().rounded())) MB. Log: \(logURL.path)")
