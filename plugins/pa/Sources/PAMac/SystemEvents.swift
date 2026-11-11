import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// The events of the system that make the clock of the PA check again: a wake from sleep, a change of the
/// system clock, a change of the time zone (build spec 10.1).
public final class SystemEvents {
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    public init(_ handler: @escaping (String) -> Void) {
        let center = NotificationCenter.default
        tokens.append((center, center.addObserver(forName: Notification.Name("NSSystemClockDidChangeNotification"), object: nil, queue: nil) { _ in handler("clock") }))
        tokens.append((center, center.addObserver(forName: Notification.Name("NSSystemTimeZoneDidChangeNotification"), object: nil, queue: nil) { _ in handler("timezone") }))
        #if canImport(AppKit)
        let ws = NSWorkspace.shared.notificationCenter
        tokens.append((ws, ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { _ in handler("wake") }))
        #endif
    }

    deinit { for (c, t) in tokens { c.removeObserver(t) } }
}
