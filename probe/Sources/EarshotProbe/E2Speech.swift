import AVFoundation
import Foundation

// E2, question 4: Apple SpeechTranscriber against Parakeet (the model file of Hex) on the same audio.
// e2-say makes the audio with the macOS `say` command. e2-asr runs the Apple engine.
// The separate package probe/parakeet runs Parakeet. e2-asr-score compares the engines.
// All audio stays on the Mac in probe/logs/e2-audio/. Git ignores it.

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

@MainActor
enum E2Speech {
    static var audioDir: URL { Paths.logs.appendingPathComponent("e2-audio") }
    static var manifestURL: URL { audioDir.appendingPathComponent("manifest.json") }

    static func loadManifest() throws -> AudioManifest {
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw ProbeError("probe/logs/e2-audio/manifest.json does not exist. Run: swift run earshot-probe e2-say")
        }
        return try JSONDecoder().decode(AudioManifest.self, from: data)
    }

    // MARK: - e2-say

    /// The English voices of `say`, with their locale. Lines look like "Rishi   en_IN   # Hello! ...".
    static func voices() -> [(name: String, locale: String)] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", "?"]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        var out: [(name: String, locale: String)] = []
        for line in text.split(separator: "\n") {
            let head = line.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
            guard let r = head.range(of: #"\s(en_[A-Z]{2})\s*$"#, options: .regularExpression) else { continue }
            let locale = head[r].trimmingCharacters(in: .whitespaces)
            let name = head[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { out.append((name: name, locale: locale)) }
        }
        return out
    }

    /// Up to 3 voices: Indian English first, then US and UK English.
    static func pickVoices() -> [String] {
        let all = voices()
        var picked: [String] = []
        for (locale, preferred) in [("en_IN", ["Rishi", "Isha", "Veena", "Sangeeta"]), ("en_US", ["Samantha", "Alex", "Fred"]),
                                    ("en_GB", ["Daniel", "Kate", "Serena"])] {
            let inLocale = all.filter { $0.locale == locale }.map(\.name)
            if let v = preferred.first(where: { inLocale.contains($0) }) ?? inLocale.first { picked.append(v) }
        }
        return picked
    }

    static func say(_ args: [String]) throws -> Int32 {
        let set = try E1.loadCommands()
        let chosen = Commands.option(args, "--voices")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            ?? pickVoices()
        guard !chosen.isEmpty else { throw ProbeError("no English voice found. See: say -v '?'") }
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        print("Voices: \(chosen.joined(separator: ", ")). Commands: \(set.commands.count).")
        var items: [AudioItem] = []
        for voice in chosen {
            let safe = voice.replacingOccurrences(of: #"[^A-Za-z0-9]"#, with: "", options: .regularExpression)
            for c in set.commands {
                let name = "\(safe)-\(c.id).wav"
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                p.arguments = ["-v", voice, "-o", audioDir.appendingPathComponent(name).path,
                               "--file-format=WAVE", "--data-format=LEI16@16000", c.words]
                try p.run()
                p.waitUntilExit()
                guard p.terminationStatus == 0 else {
                    print("  say failed for \(voice), command \(c.id)")
                    continue
                }
                items.append(AudioItem(file: name, id: c.id, kind: c.kind, voice: voice, words: c.words))
            }
        }
        let manifest = AudioManifest(builtAt: ISO8601DateFormatter().string(from: Date()), items: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL)
        print("Made \(items.count) files (16 kHz, mono) in \(audioDir.path)")
        return 0
    }

    static func audioMs(_ url: URL) -> Double {
        guard let f = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(f.length) / f.fileFormat.sampleRate * 1000
    }

    // MARK: - e2-asr: Apple SpeechTranscriber

    static func asr(_ args: [String]) async throws -> Int32 {
        let manifest = try loadManifest()
        let kind = Commands.engine(args)
        guard let locale = await SpeechSetup.locale(for: kind, wanted: Commands.wantedLocale(args)) else {
            throw ProbeError("this speech engine does not support the locale")
        }
        try await SpeechSetup.ensureAssets(kind, locale: locale)
        // The same hints as E0: the names that the owner can say.
        var hints: [String] = []
        if let idx = try? NameIndex.load() { hints = Array(Set(idx.entries.map(\.name))).sorted() }
        let log = try RunLog(kind: "asr-apple", experiment: "e2")
        print("Apple \(kind.rawValue), \(locale.identifier). Files: \(manifest.items.count). Hints: \(hints.count) names.")
        print("Log: \(log.url.path)\n")
        guard let first = manifest.items.first else { return 0 }
        // Warm-up, not logged: the first run loads the model.
        _ = try await SpeechSetup.transcribe(file: audioDir.appendingPathComponent(first.file).path, kind: kind, locale: locale, hints: [])
        for (engine, h) in [("apple", [String]()), ("apple+hints", hints)] {
            var times: [Double] = []
            for item in manifest.items {
                let url = audioDir.appendingPathComponent(item.file)
                let (text, ms) = try await SpeechSetup.transcribe(file: url.path, kind: kind, locale: locale, hints: h)
                times.append(ms)
                log.write(["event": "asr", "engine": engine, "file": item.file, "id": item.id, "voice": item.voice,
                           "text": text, "ms": ms, "audio_ms": audioMs(url)])
            }
            print("\(engine): median \(Stats.ms(Stats.median(times))), slowest 1 in 10 \(Stats.ms(Stats.percentile(times, 0.9)))")
        }
        return 0
    }

    // MARK: - e2-asr-score

    static func wordErrors(_ ref: [String], _ hyp: [String]) -> Int {
        if ref.isEmpty { return hyp.count }
        if hyp.isEmpty { return ref.count }
        var prev = Array(0...hyp.count)
        var cur = Array(repeating: 0, count: hyp.count + 1)
        for i in 1...ref.count {
            cur[0] = i
            for j in 1...hyp.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[hyp.count]
    }

    /// Reads every e2-asr-*.jsonl log. For each engine and file, the newest log wins.
    static func loadResults() -> [String: [String: (text: String, ms: Double)]] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Paths.logs.path)) ?? []
        var out: [String: [String: (text: String, ms: Double)]] = [:]
        for name in files.filter({ $0.hasPrefix("e2-asr-") && $0.hasSuffix(".jsonl") }).sorted() {
            guard let text = try? String(contentsOf: Paths.logs.appendingPathComponent(name), encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      o["event"] as? String == "asr", let engine = o["engine"] as? String, let file = o["file"] as? String
                else { continue }
                out[engine, default: [:]][file] = (o["text"] as? String ?? "", (o["ms"] as? NSNumber)?.doubleValue ?? 0)
            }
        }
        return out
    }

    static func score(_ args: [String]) throws -> Int32 {
        let manifest = try loadManifest()
        let set = try E1.loadCommands()
        let world = try E1.world()
        let results = loadResults()
        guard !results.isEmpty else { throw ProbeError("no e2-asr-*.jsonl logs. Run e2-asr and the Parakeet tool first.") }
        let byID = Dictionary(uniqueKeysWithValues: set.commands.map { ($0.id, $0) })
        func routeOK(_ words: String, _ cmd: TestCommand) -> (Bool, Bool) {
            let r = E1Router.rules(E1Router.retrieve(words, world: world))
            let ok = cmd.expected.contains { r.choice.matches($0) }
            return (ok, r.choice.action == "open_chat" && !ok)
        }
        // The rules on the words as written: the best that an engine can reach.
        let base = manifest.items.compactMap { item in byID[item.id].map { routeOK(item.words, $0).0 } }
        print("E2 speech: \(manifest.items.count) files, voices: \(Array(Set(manifest.items.map(\.voice))).sorted().joined(separator: ", ")).")
        print("Route = the E1 rules (on the Mac, no Jev) on the text. Rules on the written words: \(base.filter { $0 }.count) of \(base.count) correct.\n")
        print(E1.pad("Engine", 14) + E1.pad("Files", 7) + E1.pad("Word errors", 13) + E1.pad("Route OK", 14) + E1.pad("Wrong chat", 12)
              + E1.pad("Median", 9) + "Slowest 1 in 10")
        var misses: [String: [String]] = [:]
        for engine in results.keys.sorted() {
            let r = results[engine]!
            var errors = 0, refWords = 0, ok = 0, wrongChat = 0, n = 0
            var times: [Double] = []
            var perVoice: [String: (Int, Int)] = [:]
            for item in manifest.items {
                guard let hyp = r[item.file], let cmd = byID[item.id] else { continue }
                n += 1
                times.append(hyp.ms)
                // Misheard commands have a wrong spelling on purpose, so they do not count for word errors.
                if item.kind != "misheard" {
                    let ref = Text.normalize(item.words).split(separator: " ").map(String.init)
                    errors += wordErrors(ref, Text.normalize(hyp.text).split(separator: " ").map(String.init))
                    refWords += ref.count
                }
                let (good, wrong) = routeOK(hyp.text, cmd)
                if good { ok += 1 } else { misses[engine, default: []].append("[\(item.voice) \(item.id)] \"\(item.words)\" → \"\(hyp.text)\"") }
                if wrong { wrongChat += 1 }
                let v = perVoice[item.voice] ?? (0, 0)
                perVoice[item.voice] = (v.0 + (good ? 1 : 0), v.1 + 1)
            }
            let wer = refWords == 0 ? "-" : String(format: "%.1f %%", Double(errors) / Double(refWords) * 100)
            print(E1.pad(engine, 14) + E1.pad("\(n)", 7) + E1.pad(wer, 13) + E1.pad("\(ok)/\(n)", 14) + E1.pad("\(wrongChat)", 12)
                  + E1.pad(Stats.ms(Stats.median(times)), 9) + Stats.ms(Stats.percentile(times, 0.9)))
            print("    by voice: " + perVoice.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.0)/\($0.value.1)" }.joined(separator: ", "))
        }
        if args.contains("--misses") {
            for engine in misses.keys.sorted() {
                print("\nRoute misses, \(engine):")
                for m in misses[engine]!.prefix(30) { print("  \(m)") }
            }
        }
        return 0
    }
}
