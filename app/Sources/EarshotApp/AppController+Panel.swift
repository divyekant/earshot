import AppKit
import EarshotCore
import EarshotInput
import EarshotUI
import EarshotWake

// The facts that the menu bar icon, the panel and the window show (design canvas "Panel A", "Window: States").
// A problem never replaces the state: it is a notice with one key.

extension AppController {
    /// What earshot does now, as one value for the icon, the panel header and the window chip.
    var live: LiveState {
        LiveState(listen: listen, mode: settings.mode, wakePhrase: settings.wakePhrase,
                  holdKey: HoldKeys.capText(of: settings), pausedUntil: listenClock.pausedUntil,
                  followUntil: listenClock.followUpUntil, followSeconds: Self.followSeconds,
                  cloudOn: settings.tier2 == .jev || settings.jevSeesScreen,
                  needsYou: notices.contains { $0.kind == .needsYou })
    }

    /// The length of the follow-up window, for the ring of the orb.
    static var followSeconds: Double { WakeConfig().followUpSeconds }

    /// Reads the notices now, and again every 5 s.
    func startNotices() {
        refreshNotices()
        noticeTimer?.invalidate()
        noticeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNotices() }
        }
    }

    /// Reads the permissions, the plugins and the long jobs, and sets `notices` if they changed.
    func refreshNotices() {
        let new = Self.notices(
            access: Permissions.state(.accessibility), mic: Permissions.state(.microphone),
            plugins: plugins.all, approvals: PluginCatalog(store: store).approvals,
            stopped: { [plugins] id in plugins.status(of: id).stopped },
            wakeDownload: wakeLoad != nil && !WakeModels.isDownloaded(store: store.folder) ? Double(wakeProgress.value) / 100 : nil,
            speechProblem: status.hasPrefix("Speech did not load") ? status : nil)
        if new != notices { notices = new }
    }

    /// The notices of a moment, as a pure function for the tests. The order is the order of the banners.
    nonisolated static func notices(access: PermissionState, mic: PermissionState,
                                    plugins: [PluginEntry], approvals: [String: String],
                                    stopped: (String) -> String?, wakeDownload: Double?, speechProblem: String?) -> [Notice] {
        var out: [Notice] = []
        if mic == .denied {
            out.append(Notice(id: "mic", glyph: .micOff, title: "earshot cannot hear you",
                              detail: "Turn on the microphone for earshot in Privacy settings.", action: "Open", main: true))
        }
        if access != .granted {
            out.append(Notice(id: "access", title: "earshot cannot read the screen",
                              detail: "Allow Accessibility for earshot, so that it can click and type.", action: "Allow", main: out.isEmpty))
        }
        if let speechProblem {
            out.append(Notice(id: "speech", title: "Speech did not load",
                              detail: String(speechProblem.dropFirst("Speech did not load".count).drop { $0 == ":" || $0 == " " }),
                              action: "Settings"))
        }
        for p in plugins where p.problems.isEmpty && !p.approved {
            let changed = approvals[p.id] != nil
            out.append(Notice(id: "plugin-\(p.id)", glyph: .plugin,
                              title: changed ? "\(p.manifest.name) changed" : "\(p.manifest.name) waits for you",
                              detail: changed ? "It waits for a new approval. Until then it does not run."
                                  : "A new plugin. It does not run until you approve it.",
                              action: "Look"))
        }
        for p in plugins where p.usable {
            guard let why = stopped(p.id) else { continue }
            out.append(Notice(id: "stopped-\(p.id)", title: "\(p.manifest.name) stopped", detail: why, action: "Start again"))
        }
        if let wakeDownload {
            out.append(Notice(id: "wake-download", kind: .working, glyph: .download, title: "Downloading the wake phrase models",
                              detail: "About 35 MB, one time. The hold key works now.", progress: wakeDownload))
        }
        return out
    }

    /// The key of a notice.
    func act(_ notice: Notice, open: (WindowPage) -> Void) {
        switch notice.id {
        case "mic":
            NSWorkspace.shared.open(Permission.microphone.settingsURL)
        case "access":
            NSWorkspace.shared.open(Permission.accessibility.settingsURL)
        case "speech":
            open(.settings)
        default:
            if notice.id.hasPrefix("plugin-") {
                open(.plugins)
            } else if notice.id.hasPrefix("stopped-") {
                let id = String(notice.id.dropFirst("stopped-".count))
                if let why = plugins.restart(id) { feedback.show("✗ \(why)", ok: false) }
            }
        }
        refreshNotices()
    }
}
