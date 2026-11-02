import AppKit
import SwiftUI

/// Brings the management window to the front, on the Space that the owner looks at now.
/// earshot is a menu-bar app. A menu-bar app does not become the front app by itself, and a window that
/// opened on another Space stays there. So "Manage…" opened the window behind other windows (live feedback, 2026-11-02).
@MainActor
public enum ManageWindow {
    /// The window of ManageView. ManageView sets it when the view goes into a window.
    static weak var window: NSWindow?

    /// Call after `openWindow(id:)`. The call waits one run-loop turn, so a new window exists first.
    public static func bringToFront() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            guard let w = window else { return }
            prepare(w)
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
        }
    }

    /// Lets the window move to the current Space, and keeps it in the window list for Mission Control.
    static func prepare(_ w: NSWindow) {
        w.collectionBehavior.insert(.moveToActiveSpace)
        w.collectionBehavior.remove(.canJoinAllSpaces)
    }

    static func attach(_ w: NSWindow) {
        let first = window !== w
        window = w
        prepare(w)
        if first { bringToFront() }
    }
}

/// An empty view that tells ManageWindow which NSWindow holds the management window.
struct WindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let w = window { MainActor.assumeIsolated { ManageWindow.attach(w) } }
        }
    }
}
