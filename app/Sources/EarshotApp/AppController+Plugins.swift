import AppKit
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
        let feedback = self.feedback
        plugins.onAnswer = { [weak self] message, manifest in
            // An answer is text to show. earshot never runs it as a command (R-PL-3).
            guard let text = message.shownText else { return }
            let alert = message.isAlert
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
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
