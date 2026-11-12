import AppKit
import EarshotCore
@testable import EarshotActions
import XCTest

/// The probes of PA phase 4, package W1 (spec `phase4-build-spec.md`, section 6): can earshot read the text of the
/// web page in front through the Accessibility interface? It compares two read methods (A: the tree walk,
/// B: the text range) on made-up local pages in `Tests/Fixtures/pageprobe`.
///
/// It runs only on the owner's Mac, with `EARSHOT_LIVE_PAGES=1`, from a terminal that has the Accessibility
/// permission, and only after the owner's go. CI skips it. It opens the made-up pages in the browser, and it closes
/// only the tabs that it opened: before Command-W, it checks that the front window of the browser shows the title
/// of the probe page. It reads no other page.
///
/// Environment:
/// - `EARSHOT_LIVE_PAGES=1`: run the bench.
/// - `EARSHOT_PAGE_BROWSERS`: bundle ids, separated by commas (default: the default browser, then Safari).
/// - `EARSHOT_PAGE_PROBES`: probes to run, for example `1,2,5` (default: all, 1 to 6).
/// - `EARSHOT_PAGE_ELECTRON`: the bundle id of a running Electron app for P6. The bench reads its front window
///   and prints numbers only, because that window holds the owner's data.
/// - `EARSHOT_PAGE_OUT`: a file for the results as JSON lines.
@MainActor
final class PageReadBench: XCTestCase {
    static let normalPages = ["news", "blog", "docs", "cookie", "editor"]
    var rows: [[String: Any]] = []

    func testPageProbes() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["EARSHOT_LIVE_PAGES"] == "1" else { throw XCTSkip("live bench: set EARSHOT_LIVE_PAGES=1 on the owner's Mac") }
        guard AXIsProcessTrusted() else { throw XCTSkip("this process has no Accessibility permission") }
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/pageprobe")
        let probes = Set((env["EARSHOT_PAGE_PROBES"] ?? "1,2,3,4,5,6").split(separator: ",").compactMap { Int($0) })
        var browsers: [String] = []
        if let list = env["EARSHOT_PAGE_BROWSERS"] {
            browsers = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            let def = Self.defaultBrowser() ?? "com.apple.Safari"
            browsers = [def]
            if def != "com.apple.Safari" { browsers.append("com.apple.Safari") }
        }
        log("start", ["default": Self.defaultBrowser() ?? "-", "browsers": browsers.joined(separator: ","), "probes": probes.sorted().map(String.init).joined(separator: ",")])

        for browser in browsers {
            if probes.contains(2) { try await probe2(browser, dir) }
            if probes.contains(1) { try await probe1(browser, dir) }
            if probes.contains(3) { try await probe3(browser, dir) }
            if probes.contains(4) { try await probe4(browser) }
            if probes.contains(5) { try await probe5(browser, dir) }
            if probes.contains(6) { try await probe6(browser, dir) }
        }
        if probes.contains(6), let electron = env["EARSHOT_PAGE_ELECTRON"] { probe6Electron(electron) }
        if let out = env["EARSHOT_PAGE_OUT"] {
            let lines = rows.compactMap { row -> String? in
                guard let d = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return nil }
                return String(data: d, encoding: .utf8)
            }
            try (lines.joined(separator: "\n") + "\n").write(to: URL(fileURLWithPath: out), atomically: true, encoding: .utf8)
        }
    }

    // MARK: - P1 The read

    func probe1(_ browser: String, _ dir: URL) async throws {
        for page in Self.normalPages + ["long"] {
            guard let tab = try await open(dir.appendingPathComponent("\(page).html"), browser: browser, marker: "Probe ") else {
                log("P1", ["browser": browser, "page": page, "error": "the page did not open"]); continue
            }
            await sleepMs(1500)
            let labels = Self.labels(dir.appendingPathComponent("\(page).labels.tsv"))
            for read in [PageProbeReader.readA(area: tab.area, url: tab.url), PageProbeReader.readB(area: tab.area, url: tab.url)] {
                var row = score(read, labels)
                row["browser"] = browser; row["page"] = page
                if read.method == "A" { row["roles"] = Self.top(read.roles, 40) }
                row["kinds"] = Dictionary(grouping: read.blocks, by: \.k).mapValues(\.count)
                row["zonesSeen"] = Array(Set(read.blocks.compactMap(\.zone))).sorted()
                log("P1", row)
            }
            await close(tab)
        }
    }

    // MARK: - P2 The first read

    func probe2(_ browser: String, _ dir: URL) async throws {
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: browser).isEmpty
        let labels = Self.labels(dir.appendingPathComponent("news.labels.tsv"))
        guard let tab = try await open(dir.appendingPathComponent("news.html"), browser: browser, marker: "Probe news") else {
            log("P2", ["browser": browser, "error": "the page did not open"]); return
        }
        var row: [String: Any] = ["browser": browser, "wasRunning": wasRunning, "titleAfterMs": tab.titleMs]
        for (name, wait) in [("first", 0), ("after5s", 5000)] {
            if wait > 0 { await sleepMs(wait) }
            let a = PageProbeReader.readA(area: tab.area, url: tab.url)
            let b = PageProbeReader.readB(area: tab.area, url: tab.url)
            row["\(name)A"] = Self.found(a.text, labels.main)
            row["\(name)B"] = Self.found(b.text, labels.main)
            row["\(name)Aelements"] = a.elements
        }
        log("P2", row)
        await close(tab)
    }

    // MARK: - P3 No change

    final class Box: @unchecked Sendable {
        var read: ProbeRead?
    }

    func probe3(_ browser: String, _ dir: URL) async throws {
        guard let tab = try await open(dir.appendingPathComponent("long.html"), browser: browser, marker: "Probe long") else {
            log("P3", ["browser": browser, "error": "the page did not open"]); return
        }
        await sleepMs(1500)
        for method in ["A", "B"] {
            let before = state(tab)
            let box = Box()
            let area = tab.area, url = tab.url
            DispatchQueue.global(qos: .userInitiated).async {
                box.read = method == "A" ? PageProbeReader.readA(area: area, url: url) : PageProbeReader.readB(area: area, url: url)
            }
            var other: [Double] = []
            while box.read == nil {
                await sleepMs(150)
                let t = Clock.nowNs()
                _ = AX.copy(tab.window, "AXTitle")
                other.append(Clock.ms(since: t))
            }
            let after = state(tab)
            log("P3", ["browser": browser, "method": method, "readMs": box.read?.ms ?? -1,
                       "otherCallMaxMs": other.max() ?? -1, "otherCalls": other.count,
                       "scrollSame": before.scroll == after.scroll, "selectionSame": before.selection == after.selection,
                       "focusSame": before.focus == after.focus, "scrollBefore": before.scroll ?? -1])
        }
        await close(tab)
    }

    /// The scroll position, the selected text and the focused element, as values that compare.
    func state(_ tab: Tab) -> (scroll: Double?, selection: String, focus: String) {
        var scroll: Double?
        if let parent = AX.element(tab.area, "AXParent"), let bar = AX.element(parent, "AXVerticalScrollBar") {
            scroll = (AX.copy(bar, "AXValue") as? NSNumber)?.doubleValue
        }
        let sel = AX.copy(tab.area, "AXSelectedTextMarkerRange")
        let selText = sel.flatMap { AX.text(PageProbeReader.param(tab.area, "AXStringForTextMarkerRange", $0)) } ?? ""
        let app = AX.appElement(tab.pid)
        let focus = AX.focused(app).map { "\(AX.role($0))/\(AX.subrole($0))/\(AX.frame($0).map { "\(Int($0.x)),\(Int($0.y))" } ?? "-")" } ?? "-"
        return (scroll, selText, focus)
    }

    // MARK: - P4 A page that loads

    func probe4(_ browser: String) async throws {
        // A load probe, not labeled data: a large table of made-up row numbers, written at run time.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("earshot-probe-table.html")
        var html = "<!doctype html><html><head><meta charset=\"utf-8\"><title>Probe table · large</title></head><body><h1>Probe table</h1><table>"
        for i in 1...40_000 { html += "<tr><td>Row \(i)</td><td>\(i * 7 % 1000)</td><td>\(i * 13 % 997)</td></tr>" }
        html += "</table><p>End of the probe table.</p></body></html>"
        try html.write(to: url, atomically: true, encoding: .utf8)
        guard let tab = try await open(url, browser: browser, marker: "Probe table", settleArea: false) else {
            log("P4", ["browser": browser, "error": "the page did not open"]); return
        }
        var timeline: [String] = []
        let t0 = Clock.nowNs()
        var loadedAt: Double?
        while Clock.ms(since: t0) < 3000 {
            let area = ScreenReader.visibleWebArea(tab.window) ?? tab.area
            let loaded = AX.bool(area, "AXLoaded").map { $0 ? "1" : "0" } ?? "-"
            let progress = (AX.copy(area, "AXLoadingProgress") as? NSNumber).map { String(format: "%.2f", $0.doubleValue) } ?? "-"
            let busy = AX.bool(area, "AXElementBusy").map { $0 ? "1" : "0" } ?? "-"
            timeline.append("\(Int(Clock.ms(since: t0))):\(loaded)/\(progress)/\(busy)")
            if loaded == "1" && busy != "1" { loadedAt = Clock.ms(since: t0); break }
            await sleepMs(100)
        }
        let area = ScreenReader.visibleWebArea(tab.window) ?? tab.area
        let a = PageProbeReader.readA(area: area, url: tab.url)
        let b = PageProbeReader.readB(area: area, url: tab.url)
        log("P4", ["browser": browser, "titleAfterMs": tab.titleMs, "loadedAfterMs": loadedAt ?? -1, "timeline": timeline,
                   "attributes": AX.attributeNames(area).filter { $0.lowercased().contains("load") || $0.lowercased().contains("busy") },
                   "A_ms": a.ms, "A_elements": a.elements, "A_complete": a.complete, "A_lastRow": a.text.contains("End of the probe table"),
                   "B_ms": b.ms, "B_complete": b.complete, "B_lastRow": b.text.contains("End of the probe table")])
        await close(tab)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - P5 Protected pages

    func probe5(_ browser: String, _ dir: URL) async throws {
        for (page, marker) in [("welcome-back", "Probe protected"), ("fields", "Probe fields")] {
            guard let tab = try await open(dir.appendingPathComponent("\(page).html"), browser: browser, marker: marker) else {
                log("P5", ["browser": browser, "page": page, "error": "the page did not open"]); continue
            }
            await sleepMs(1000)
            for read in [PageProbeReader.readA(area: tab.area, url: tab.url), PageProbeReader.readB(area: tab.area, url: tab.url)] {
                let text = read.text
                let oneLine = ["PROBE-SEARCH-VALUE", "PROBE-LINE-VALUE", "PROBE-COMBO-VALUE", "PROBE-MEMBER-4471", "PROBE-SECRET-VALUE"]
                log("P5", ["browser": browser, "page": page, "method": read.method, "sensitive": read.sensitive ?? "-",
                           "blocks": read.blocks.count, "oneLineValues": oneLine.filter { text.contains($0) },
                           "textAreaLines": ["PROBE-AREA-LINE-ONE", "PROBE-AREA-LINE-TWO"].filter { text.contains($0) }.count])
            }
            await close(tab)
        }
    }

    // MARK: - P6 Other content

    func probe6(_ browser: String, _ dir: URL) async throws {
        if let tab = try await open(dir.appendingPathComponent("minutes.pdf"), browser: browser, marker: "minutes") {
            await sleepMs(1500)
            let pdfWords = Self.words("Probe PDF - Minutes of the Quarry Lane residents group Meeting of 3 February. Nine residents came. 1. The group agreed to ask the council for a crossing near the school gate. 2. The spring clean of the lane is on Saturday 12 April, from 10:00. 3. Next meeting: 7 April, in the hall of St Brannoc's church.")
            for read in [PageProbeReader.readA(area: tab.area, url: tab.url), PageProbeReader.readB(area: tab.area, url: tab.url)] {
                log("P6", ["browser": browser, "page": "pdf", "method": read.method, "ms": read.ms, "blocks": read.blocks.count,
                           "words": Self.words(read.text).values.reduce(0, +), "found": Self.share(Self.words(read.text), pdfWords)])
            }
            await close(tab)
        } else {
            log("P6", ["browser": browser, "page": "pdf", "error": "no web area or the page did not open"])
        }
        if let tab = try await open(dir.appendingPathComponent("frame.html"), browser: browser, marker: "Probe frame") {
            await sleepMs(1000)
            for read in [PageProbeReader.readA(area: tab.area, url: tab.url), PageProbeReader.readB(area: tab.area, url: tab.url)] {
                log("P6", ["browser": browser, "page": "frame", "method": read.method, "ms": read.ms,
                           "outerText": read.text.contains("first Monday of each month"),
                           "frameText": read.text.contains("Lane swimming from 06:30")])
            }
            await close(tab)
        }
    }

    /// An Electron app that runs now. It holds the owner's data: numbers only, no text.
    func probe6Electron(_ bundle: String) {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
            log("P6", ["app": bundle, "error": "not running"]); return
        }
        let app = AX.appElement(running.processIdentifier)
        AX.set(app, "AXManualAccessibility", kCFBooleanTrue)
        guard let win = AX.window(app) ?? AX.elements(app, "AXWindows").first,
              let area = ScreenReader.findWebArea(in: win)?.0 else {
            log("P6", ["app": bundle, "error": "no web area"]); return
        }
        for read in [PageProbeReader.readA(area: area, url: nil), PageProbeReader.readB(area: area, url: nil)] {
            log("P6", ["app": bundle, "method": read.method, "ms": read.ms, "elements": read.elements, "blocks": read.blocks.count,
                       "words": Self.words(read.text).values.reduce(0, +), "landmarks": read.landmarks, "headings": read.headings])
        }
    }

    // MARK: - Open and close

    struct Tab {
        let pid: pid_t
        let window: AXUIElement
        let area: AXUIElement
        let url: String?
        let marker: String
        let titleMs: Double
    }

    static func defaultBrowser() -> String? {
        guard let probe = URL(string: "https://example.org/"),
              let app = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return nil }
        return Bundle(url: app)?.bundleIdentifier
    }

    /// Opens a made-up page in the browser and waits up to 8 s until the front window shows the marker in its title.
    func open(_ file: URL, browser: String, marker: String, settleArea: Bool = true) async throws -> Tab? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser) else { return nil }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let t0 = Clock.nowNs()
        let running = try await NSWorkspace.shared.open([file], withApplicationAt: appURL, configuration: config)
        let pid = running.processIdentifier
        let app = AX.appElement(pid)
        var window: AXUIElement?
        while Clock.ms(since: t0) < 8000 {
            if let w = AX.window(app), (AX.string(w, "AXTitle") ?? "").contains(marker) { window = w; break }
            await sleepMs(50)
        }
        let titleMs = Clock.ms(since: t0)
        guard let window else { return nil }
        var area: AXUIElement?
        while Clock.ms(since: t0) < 8000 {
            area = ScreenReader.visibleWebArea(window) ?? ScreenReader.findWebArea(in: window)?.0
            if area != nil || !settleArea { break }
            await sleepMs(50)
        }
        guard let area = area ?? ScreenReader.findWebArea(in: window)?.0 else {
            log("open", ["browser": browser, "marker": marker, "error": "no web area"])
            await close(Tab(pid: pid, window: window, area: window, url: nil, marker: marker, titleMs: titleMs))
            return nil
        }
        return Tab(pid: pid, window: window, area: area, url: ScreenReader.address(area), marker: marker, titleMs: titleMs)
    }

    /// Closes the tab of the probe page with Command-W, only if the browser is in front and its front window shows
    /// the title of the probe page.
    func close(_ tab: Tab) async {
        let app = AX.appElement(tab.pid)
        guard AX.frontPid() == tab.pid, let w = AX.window(app), (AX.string(w, "AXTitle") ?? "").contains(tab.marker),
              let cmdW = Keys.parse("cmd+w") else {
            log("close", ["marker": tab.marker, "closed": false])
            return
        }
        Keys.press(cmdW)
        await sleepMs(400)
    }

    // MARK: - Scores (spec section 7.3)

    struct Labels { var main: [String: Int]; var neutral: [String: Int] }

    static func labels(_ file: URL) -> Labels {
        var l = Labels(main: [:], neutral: [:])
        for line in ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0] == "main" { l.main.merge(words(parts[1]), uniquingKeysWith: +) }
            if parts[0] == "neutral" { l.neutral.merge(words(parts[1]), uniquingKeysWith: +) }
        }
        return l
    }

    /// Lower case, letters and digits only, as a multiset.
    static func words(_ s: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for w in s.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }) { out[String(w), default: 0] += 1 }
        return out
    }

    /// The share of the words of `want` that `have` has (multiset).
    static func share(_ have: [String: Int], _ want: [String: Int]) -> Double {
        let total = want.values.reduce(0, +)
        guard total > 0 else { return 0 }
        let hit = want.reduce(0) { $0 + min($1.value, have[$1.key] ?? 0) }
        return (Double(hit) / Double(total) * 1000).rounded() / 1000
    }

    static func found(_ text: String, _ main: [String: Int]) -> Double { share(words(text), main) }

    /// The kept words that are not main words and not neutral words, divided by all kept words.
    static func noise(_ text: String, _ l: Labels) -> Double {
        var kept = words(text)
        let total = kept.values.reduce(0, +)
        guard total > 0 else { return 0 }
        for (w, n) in l.main.merging(l.neutral, uniquingKeysWith: +) { kept[w] = max(0, (kept[w] ?? 0) - n) }
        return (Double(kept.values.reduce(0, +)) / Double(total) * 1000).rounded() / 1000
    }

    func score(_ read: ProbeRead, _ l: Labels) -> [String: Any] {
        ["method": read.method, "ms": (read.ms * 10).rounded() / 10, "elements": read.elements, "blocks": read.blocks.count,
         "found": Self.found(read.text, l.main), "noise": Self.noise(read.text, l), "complete": read.complete,
         "zones": read.blocks.contains { $0.zone != nil }, "links": read.blocks.contains { ($0.links ?? 0) > 0 },
         "landmarks": read.landmarks, "headings": read.headings, "sensitive": read.sensitive ?? "-", "note": read.note]
    }

    static func top(_ counts: [String: Int], _ n: Int) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: counts.sorted { $0.value > $1.value }.prefix(n).map { ($0.key, $0.value) })
    }

    func log(_ probe: String, _ row: [String: Any]) {
        var r = row
        r["probe"] = probe
        rows.append(r)
        let flat = r.filter { !($0.value is [String: Int]) && !($0.value is [String: Any]) }
            .sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("PAGEPROBE \(probe) \(flat)")
    }
}

extension AX {
    /// The names of the attributes of an element (for the probe report).
    static func attributeNames(_ el: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(el, &names) == .success, let list = names as? [String] else { return [] }
        return list
    }
}
