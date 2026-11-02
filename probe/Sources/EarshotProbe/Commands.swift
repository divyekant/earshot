import AppKit
import AVFoundation
import Foundation

/// The command-line verbs. Each returns an exit code, or nil to keep running.
@MainActor
enum Commands {
    static let usage = """
    earshot-probe: the E0 viability probe. See docs/experiments/E0-viability.md.

    swift run earshot-probe check                 Check permissions, apps, links and speech
    swift run earshot-probe inspect [app...]      Read menus and text fields of the apps (read only)
    swift run earshot-probe setup                 Write probe/people.json (your test chats)
    swift run earshot-probe route "<words>"       Show how the router reads a command (no action)
    swift run earshot-probe run "<words>"         Run one typed command
    swift run earshot-probe bench [app] [runs]    Part A: typed commands into your own chats
    swift run earshot-probe listen                Part B: hold Control-Option-E and speak
    swift run earshot-probe transcribe <file>     Transcribe an audio file and time it
    swift run earshot-probe report [log]          Summary of the newest log, or of [log]

    E1 (docs/experiments/E1-generic-router.md):
    swift run earshot-probe catalogue             Build the app catalogue from the menu bars (read only)
    swift run earshot-probe index [--front]       Read the chat names in each chat app's sidebar (read only)
    swift run earshot-probe e1-make               Make the test commands from the index
    swift run earshot-probe e1-try "<words>"      Show the short list, the rules answer and the Jev answer
    swift run earshot-probe e1-run [--no-jev]     Route all test commands with rules, Jev, and rules then Jev
    swift run earshot-probe e1-open [app] [runs]  Open your own chat with the generated rows (types nothing)
    swift run earshot-probe e1-search [app...]    Type names into each app's own search and read the results (no Return)

    E2 (docs/experiments/E2-web-and-speech.md):
    swift run earshot-probe e2-page [site...]     Open the test pages in Chrome as new tabs and read them (no click)
    swift run earshot-probe e2-make               Make the web test commands from the page reads
    swift run earshot-probe e2-try <site> "<words>"  Show the short list, the rules answer and the Jev answer
    swift run earshot-probe e2-run [--no-jev]     Route all web test commands with rules, Jev, and rules then Jev
    swift run earshot-probe e2-act [site...]      Live: press links, type into search fields, scroll (no Return)
    swift run earshot-probe e2-press [site] [--label "<text>"] [--mouse]
                                                  Live: try each way to press one link (no Return)
    swift run earshot-probe e2-say [--voices a,b] Make WAV files of the E1 commands with `say`
    swift run earshot-probe e2-asr                Transcribe the WAV files with Apple speech
    swift run earshot-probe e2-asr-score          Compare Apple speech and Parakeet (run probe/parakeet first)

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
            case "inspect": return try await inspect(args)
            case "setup": try Config.interactiveSetup(); return 0
            case "route": return try route(args)
            case "run": return try await runOne(args)
            case "bench": return try await bench(args)
            case "listen": return try await listen(args)
            case "transcribe": return try await transcribe(args)
            case "report": return try Report.run(positional(args).first)
            case "catalogue": return try await E1.catalogue(args)
            case "index": return try await E1.index(args)
            case "e1-make": return try E1.make(args)
            case "e1-try": return try await E1.tryOne(args)
            case "e1-run": return try await E1.runAll(args)
            case "e1-open": return try await E1.open(args)
            case "e1-search": return try await E1.search(args)
            case "e1-recheck": return try E1.recheck(args)
            case "e2-page": return try await E2.page(args)
            case "e2-make": return try E2.make(args)
            case "e2-try": return try await E2.tryOne(args)
            case "e2-run": return try await E2.runAll(args)
            case "e2-act": return try await E2.act(args)
            case "e2-press": return try await E2Press.run(args)
            case "e2-say": return try E2Speech.say(args)
            case "e2-asr": return try await E2Speech.asr(args)
            case "e2-asr-score": return try E2Speech.score(args)
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
                let names = apps.map { row in "\(row.id) \"\(p.handle(for: row) ?? "skip")\"" }
                print("  \(p.me ? "me (\(p.name))" : p.name): \(names.joined(separator: ", "))")
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

    // MARK: - inspect (read only)

    /// Reads the shortcuts, windows and text fields of each app. It presses no key and types nothing.
    /// --launch opens an app that is not running, in the background. --all shows every shortcut.
    /// --front brings each app to the front first, so that macOS shows its window. At the end it
    /// brings back the app that was in front before.
    static func inspect(_ args: [String]) async throws -> Int32 {
        guard AX.trusted(prompt: false) else { throw ProbeError("Accessibility is off for this terminal") }
        let apps = try Config.loadApps()
        let wanted = positional(args)
        let launch = args.contains("--launch"), all = args.contains("--all"), front = args.contains("--front")
        let before = NSWorkspace.shared.frontmostApplication
        defer { if front { before?.activate() } }
        let words = ["search", "find", "new", "chat", "conversation", "go to", "jump", "switch", "message", "compose", "quick"]
        for row in apps where wanted.isEmpty || wanted.contains(row.id) {
            print("== \(row.name) (\(row.bundleID))")
            var running = NSRunningApplication.runningApplications(withBundleIdentifier: row.bundleID).first
            if running == nil, launch, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: row.bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
                _ = await waitUntil(timeoutMs: 8000) {
                    NSRunningApplication.runningApplications(withBundleIdentifier: row.bundleID).first != nil
                }
                running = NSRunningApplication.runningApplications(withBundleIdentifier: row.bundleID).first
                print("   started in the background")
            }
            guard let app = running else {
                print("   not running (add --launch to start it in the background)\n")
                continue
            }
            let el = AX.appElement(app.processIdentifier)
            if row.electron == true { AX.set(el, "AXManualAccessibility", kCFBooleanTrue) }
            if front {
                let ok = await Pipeline(apps: apps).bringToFront(bundleID: row.bundleID)
                print("   brought to the front: \(ok ? "yes" : "no")")
            }
            _ = await waitUntil(timeoutMs: 3000) { !AX.elements(el, "AXWindows").isEmpty }
            await sleepMs(front ? 500 : 0)

            let shortcuts = AX.menuShortcuts(el).filter { s in all || words.contains { s.path.lowercased().contains($0) } }
            print("   Shortcuts\(all ? "" : " (search, chat and message items)"):")
            if shortcuts.isEmpty { print("     none found") }
            for s in shortcuts { print("     \(s.keys.padding(toLength: 14, withPad: " ", startingAt: 0)) \(s.path)") }

            for (i, win) in AX.elements(el, "AXWindows").prefix(3).enumerated() {
                guard let f = AX.frame(win) else { continue }
                print("   Window \(i + 1): \(Int(f.w)) x \(Int(f.h)), title \"\(AX.string(win, "AXTitle") ?? "")\"")
                if let search = AX.findSearchField(in: win), let sf = AX.frame(search) {
                    let label = AX.string(search, "AXPlaceholderValue") ?? AX.string(search, "AXDescription") ?? ""
                    print("     search field for the probe: \"\(label.prefix(40))\" at y \(Int(((sf.midY - f.y) / max(f.h, 1) * 100).rounded()))%")
                } else {
                    print("     search field for the probe: none found")
                }
                for field in AX.textFields(in: win) {
                    let x = Int(((field.frame.x - f.x) / max(f.w, 1) * 100).rounded())
                    let y = Int(((field.frame.midY - f.y) / max(f.h, 1) * 100).rounded())
                    let w = Int((field.frame.w / max(f.w, 1) * 100).rounded())
                    let sub = field.subrole.isEmpty ? "" : "/\(field.subrole)"
                    print("     \(field.kind): \(field.role)\(sub) \"\(field.label)\" at x \(x)%, y \(y)%, width \(w)%\(field.hasText ? ", holds text" : "")")
                }
                let (box, _) = AX.findComposer(in: win)
                let column = box.flatMap { AX.frame($0) }
                let header = AX.headerHits(app: el, window: win, column: column, skip: nil)
                    + AX.headerTexts(in: win, column: column)
                print("     header for the chat check: \(header.prefix(8).joined(separator: " | "))")
                let own = AX.ownChatNames(in: win)
                if !own.isEmpty { print("     Your own chat shows as: \(own.joined(separator: " | "))") }
            }
            print("")
        }
        return 0
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
                var clearNote = ""
                if last, out.typed, let typed = out.typedText, row.typeIntoPrefilled != true,
                   let pid = pipeline.running(row)?.processIdentifier {
                    (cleared, clearNote) = await pipeline.clearTyped(app: pid, box: out.typedBox, expected: typed)
                    if !cleared { print("   test text NOT deleted: \(clearNote). Delete it by hand.") }
                }
                id += 1
                log.write(["event": "command", "id": id, "mode": "typed", "heard": cmd.describe, "route": cmd.describe,
                           "app": row.id, "person": me.name, "hearing": "unscored", "from_other_app": i % 2 == 1,
                           "stages": watch.dictionary, "outcome": out.dictionary, "cleared": cleared, "clear_note": clearNote])
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
