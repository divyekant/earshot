import AppKit
import AVFoundation
import Foundation

/// The command-line verbs. Each returns an exit code, or nil to keep running.
@MainActor
enum Commands {
    static let usage = """
    earshot-probe: the E0 viability probe. See docs/experiments/E0-viability.md.

    swift run earshot-probe check                 Check permissions, apps, links and speech
    swift run earshot-probe setup                 Write probe/people.json (your test chats)
    swift run earshot-probe route "<words>"       Show how the router reads a command (no action)
    swift run earshot-probe run "<words>"         Run one typed command
    swift run earshot-probe bench [app] [runs]    Part A: typed commands into your own chats
    swift run earshot-probe listen                Part B: hold Control-Option-E and speak
    swift run earshot-probe transcribe <file>     Transcribe an audio file and time it
    swift run earshot-probe report [log]          Summary of the newest log, or of [log]

    Options: --engine transcriber|dictation   --locale en-IN
    """

    static func option(_ args: [String], _ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func positional(_ args: [String]) -> [String] {
        var out: [String] = []
        var skip = false
        for a in args {
            if skip { skip = false; continue }
            if a.hasPrefix("--") { skip = true; continue }
            out.append(a)
        }
        return out
    }

    static func engine(_ args: [String]) -> EngineKind {
        EngineKind(rawValue: option(args, "--engine") ?? "") ?? .transcriber
    }

    static func wantedLocale(_ args: [String]) -> Locale {
        if let id = option(args, "--locale") { return Locale(identifier: id) }
        return Locale.current
    }

    static func run(_ argv: [String]) async -> Int32? {
        guard let verb = argv.first else {
            print(usage)
            return 0
        }
        let args = Array(argv.dropFirst())
        do {
            switch verb {
            case "check": return try await check(args)
            case "setup": try Config.interactiveSetup(); return 0
            case "route": return try route(args)
            case "run": return try await runOne(args)
            case "bench": return try await bench(args)
            case "listen": return try await listen(args)
            case "transcribe": return try await transcribe(args)
            case "report": return try Report.run(positional(args).first)
            default:
                print(usage)
                return 2
            }
        } catch {
            print("Error: \(error)")
            return 1
        }
    }

    // MARK: - check

    static func check(_ args: [String]) async throws -> Int32 {
        let prompt = !args.contains("--no-prompt")
        var problems = 0
        print("earshot-probe check\n")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

        let trusted = AX.trusted(prompt: prompt)
        print("Accessibility for this terminal: \(trusted ? "on" : "OFF")")
        if !trusted {
            problems += 1
            print("  Turn on your terminal app (for example Ghostty) in System Settings > Privacy & Security > Accessibility.")
            print("  Then quit and reopen the terminal, and run check again.")
            if prompt, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }

        var mic = AVCaptureDevice.authorizationStatus(for: .audio)
        if mic == .notDetermined && prompt {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            mic = AVCaptureDevice.authorizationStatus(for: .audio)
        }
        let micText: String
        switch mic {
        case .authorized: micText = "on"
        case .notDetermined: micText = "not asked yet"
        default: micText = "OFF"
        }
        print("Microphone for this terminal: \(micText)")
        if mic != .authorized { problems += 1 }

        let apps = try Config.loadApps()
        print("\nApps:")
        for row in apps {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: row.bundleID)
            let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: row.bundleID).isEmpty
            var line = "  \(row.name): \(url == nil ? "NOT INSTALLED" : "installed"), \(isRunning ? "running" : "not running")"
            if let template = row.openChat.template,
               let scheme = template.split(separator: ":").first,
               let probe = URL(string: "\(scheme):test") {
                let handler = NSWorkspace.shared.urlForApplication(toOpen: probe)?.lastPathComponent ?? "none"
                line += ", \(scheme): opens \(handler)"
            }
            if url == nil { problems += 1 }
            print(line)
        }

        print("\nTest chats:")
        if let people = try? Config.loadPeople() {
            for p in people {
                print("  \(p.me ? "me" : p.name): \(p.handles.keys.sorted().joined(separator: ", "))")
            }
        } else {
            problems += 1
            print("  probe/people.json is missing. Run: swift run earshot-probe setup")
        }

        print("\nSpeech (on this Mac):")
        for kind in [EngineKind.transcriber, .dictation] {
            if let loc = await SpeechSetup.locale(for: kind, wanted: wantedLocale(args)) {
                let status = await SpeechSetup.status(kind, locale: loc)
                print("  \(kind.rawValue): \(loc.identifier), \(status)")
            } else {
                print("  \(kind.rawValue): no model for \(wantedLocale(args).identifier)")
            }
        }

        print(problems == 0 ? "\nAll checks passed." : "\n\(problems) item(s) need attention.")
        return problems == 0 ? 0 : 1
    }

    // MARK: - route and run

    static func makeRouter() throws -> Router {
        Router(apps: try Config.loadApps(), people: try Config.loadPeople())
    }

    static func route(_ args: [String]) throws -> Int32 {
        let router = try makeRouter()
        let words = positional(args).joined(separator: " ")
        if let cmd = router.route(words) {
            print("\"\(words)\" → \(cmd.describe)  (name score \(String(format: "%.2f", cmd.nameScore)))")
        } else {
            print("\"\(words)\" → not a command")
        }
        return 0
    }

    static func runOne(_ args: [String]) async throws -> Int32 {
        guard AX.trusted(prompt: true) else { throw ProbeError("Accessibility is off. Run: swift run earshot-probe check") }
        let router = try makeRouter()
        let pipeline = Pipeline(apps: router.apps)
        pipeline.prime()
        let words = positional(args).joined(separator: " ")
        guard let cmd = router.route(words) else { throw ProbeError("not a command: \(words)") }
        let log = try RunLog(kind: "run")
        let watch = Stopwatch()
        let out = await pipeline.execute(cmd, watch: watch, typing: .selfOnly)
        log.write(["event": "command", "id": 1, "mode": "typed", "heard": words, "route": cmd.describe,
                   "app": cmd.app.id, "person": cmd.person?.name ?? "", "hearing": "unscored",
                   "stages": watch.dictionary, "outcome": out.dictionary])
        print("\(out.ok ? "✓" : "✗") \(cmd.describe) · \(watch.summary)\(out.reason.map { " · \($0)" } ?? "")")
        print("  open=\(out.openMethod) focus=\(out.focusMethod) nodes=\(out.nodes) chat=\(out.chatCheck) typed=\(out.typed)")
        if !out.notes.isEmpty { print("  notes: \(out.notes.joined(separator: "; "))") }
        print("  window title: \"\(out.windowTitle)\"")
        if !out.header.isEmpty { print("  header: \(out.header.prefix(8).joined(separator: " | "))") }
        return out.ok ? 0 : 1
    }

    // MARK: - bench (Part A)

    static func bench(_ args: [String]) async throws -> Int32 {
        guard AX.trusted(prompt: true) else { throw ProbeError("Accessibility is off. Run: swift run earshot-probe check") }
        let apps = try Config.loadApps()
        let people = try Config.loadPeople()
        guard let me = people.first(where: { $0.me }) else { throw ProbeError("people.json has no entry with \"self\": true") }
        let pos = positional(args)
        let only = pos.first
        let runsOverride = pos.count > 1 ? Int(pos[1]) : nil
        let pipeline = Pipeline(apps: apps)
        pipeline.prime()
        let log = try RunLog(kind: "bench")
        print("Part A: typed commands into your own chats. Do not touch the keyboard or mouse.")
        print("Log: \(log.url.path)\n")
        var id = 0
        for row in apps where only == nil || row.id == only {
            guard pipeline.handle(row, me) != nil else {
                print("\(row.name): skipped, no \(row.id) handle for you in people.json")
                continue
            }
            let runs = runsOverride ?? row.benchRuns ?? 10
            for i in 0..<runs {
                if i % 2 == 1 { _ = await pipeline.bringToFront(bundleID: "com.apple.finder") }
                await sleepMs(300)
                let last = i == runs - 1
                let cmd = Command(app: row, person: me, unmatchedName: nil, text: last ? "typing check" : nil, nameScore: 1)
                let watch = Stopwatch()
                let out = await pipeline.execute(cmd, watch: watch, typing: .selfOnly)
                var cleared = false
                if last, out.typed, let typed = out.typedText, row.typeIntoPrefilled != true,
                   let pid = pipeline.running(row)?.processIdentifier {
                    cleared = await pipeline.clearTyped(app: pid, expected: typed)
                }
                id += 1
                log.write(["event": "command", "id": id, "mode": "typed", "heard": cmd.describe, "route": cmd.describe,
                           "app": row.id, "person": me.name, "hearing": "unscored", "from_other_app": i % 2 == 1,
                           "stages": watch.dictionary, "outcome": out.dictionary, "cleared": cleared])
                let mark = out.ok ? "✓" : "✗"
                print("\(row.name) \(i + 1)/\(runs) \(mark) \(watch.summary) · open=\(out.openMethod) focus=\(out.focusMethod) chat=\(out.chatCheck)\(out.typed ? " typed" : "")\(out.reason.map { " · \($0)" } ?? "")")
                if i == 0 {
                    print("   window title: \"\(out.windowTitle)\"")
                    if !out.header.isEmpty { print("   header: \(out.header.prefix(6).joined(separator: " | "))") }
                }
                await sleepMs(500)
            }
        }
        print("")
        _ = try Report.run(log.url.path)
        return 0
    }

    // MARK: - listen (Part B)

    static func listen(_ args: [String]) async throws -> Int32? {
        guard AX.trusted(prompt: true) else { throw ProbeError("Accessibility is off. Run: swift run earshot-probe check") }
        let router = try makeRouter()
        let pipeline = Pipeline(apps: router.apps)
        pipeline.prime()
        let kind = engine(args)
        guard let locale = await SpeechSetup.locale(for: kind, wanted: wantedLocale(args)) else {
            throw ProbeError("no \(kind.rawValue) model for \(wantedLocale(args).identifier). Try --locale en-US")
        }
        try await SpeechSetup.ensureAssets(kind, locale: locale)
        let listener = Listener(kind: kind, locale: locale)
        // Name hints help the engine with names (risk 3 in the plan).
        var hints = router.people.flatMap { [$0.name] + ($0.aliases ?? []) }
        hints += router.apps.flatMap { [$0.name, $0.spoken] }
        listener.hints = Array(Set(hints)).sorted()
        print("Speech engine: \(kind.rawValue), \(locale.identifier). Loading the model...")
        try await listener.start()
        let log = try RunLog(kind: "listen")
        log.write(["event": "session", "engine": kind.rawValue, "locale": locale.identifier])
        let session = ListenSession(router: router, pipeline: pipeline, listener: listener, log: log,
                                    script: ScriptLine.make(apps: router.apps, people: router.people))
        session.start()
        Retainer.keep(session)
        return nil
    }

    // MARK: - transcribe

    static func transcribe(_ args: [String]) async throws -> Int32 {
        guard let path = positional(args).first else { throw ProbeError("give an audio file") }
        let kind = engine(args)
        guard let locale = await SpeechSetup.locale(for: kind, wanted: wantedLocale(args)) else {
            throw ProbeError("no \(kind.rawValue) model for \(wantedLocale(args).identifier)")
        }
        try await SpeechSetup.ensureAssets(kind, locale: locale)
        let hints = (try? Config.loadPeople())?.flatMap { [$0.name] + ($0.aliases ?? []) } ?? []
        let (text, ms) = try await SpeechSetup.transcribe(file: path, kind: kind, locale: locale, hints: hints)
        print("\(kind.rawValue) \(locale.identifier): \"\(text)\" in \(Int(ms.rounded())) ms")
        if let router = try? makeRouter() {
            print("route: \(router.route(text)?.describe ?? "not a command")")
        }
        return 0
    }
}

/// Keeps long-lived objects alive while the run loop runs.
@MainActor
enum Retainer {
    static var objects: [AnyObject] = []
    static func keep(_ o: AnyObject) { objects.append(o) }
}
