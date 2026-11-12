import AppKit
import EarshotActions
import EarshotCore
import Foundation
import UserNotifications

// The plugins of the app (R-PL-1 to R-PL-5, docs/PLUGINS.md). In its own file, so that AppController changes by a
// few lines only.

extension AppController {
    /// How long a plugin answer stays on screen. A list needs more time than the 2 s of a command note.
    static let pluginAnswerSeconds: Double = 6

    /// Reads the plugins folder and the approvals, and connects the hand-off and the answers. An approved plugin
    /// starts on its first command, not here.
    func startPlugins() {
        plugins.reload()
        pipeline.plugins = plugins
        connectPageText()
        let feedback = self.feedback
        plugins.onAnswer = { [weak self] message, manifest in
            // An answer is text to show. earshot never runs it as a command (R-PL-3).
            guard let text = message.shownText else { return }
            let alert = message.isAlert
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.control?.collect("\(manifest.name): \(text)")
                    if self.settings.showFeedback || alert {
                        feedback.show("\(manifest.name): \(text)", ok: true, seconds: Self.pluginAnswerSeconds)
                    }
                    if alert, self.settings.playSounds {
                        NSSound(named: FeedbackSound.done.systemName).map { $0.volume = FeedbackSound.done.volume; $0.play() }
                    }
                    // The note goes after some seconds. An alert also goes to the Notification Center, so that the
                    // owner sees it after time away from the Mac.
                    if alert { Self.notify(title: manifest.name, body: text) }
                }
            }
        }
    }

    /// Page reads run here, one at a time, off the main thread: a read does not slow a command (R-PL-5).
    nonisolated static let pageReads = DispatchQueue(label: "earshot.plugin.page-text", qos: .utility)

    /// Connects the asks for page text (docs/PLUGINS.md 5.3). Each read shows the note "→ <plugin> · reads this page",
    /// also with the notes off: the owner always sees that a plugin gets the text of the page.
    /// The page text goes only to the plugin. It never goes to the activity log or to Jev.
    func connectPageText() {
        let feedback = self.feedback
        plugins.onPageTextAsk = { [weak self] command, manifest, reply in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.control?.collect("→ \(manifest.name) · reads this page")
                    feedback.show("→ \(manifest.name) · reads this page", ok: true, seconds: 2)
                }
            }
            let re = command.id
            Self.pageReads.async {
                let result = PageTextReader.read(expectURL: command.url)
                if let error = result.error {
                    reply([PageText.errorLine(re: re, error)])
                } else {
                    reply(PageText.lines(re: re, url: result.url, title: result.title, blocks: result.blocks,
                                         complete: result.complete))
                }
            }
        }
    }

    /// Posts one alert to the Notification Center. The first alert asks the owner for the permission once.
    /// The text stays on the Mac.
    nonisolated static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
