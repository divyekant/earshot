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

/// An empty view that tells ManageWindow which NSWindow holds the management window. WindowChrome does the same.
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

/// Gives the window its own top bar (design canvas, window boards): no title, a clear title bar over the content,
/// the paper color, and the three window buttons in the middle of the 52 pt bar of earshot.
struct WindowChrome: NSViewRepresentable {
    /// The height of the top bar of the window.
    static let barHeight: CGFloat = 52

    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Probe: NSView {
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let w = window else { return }
            MainActor.assumeIsolated {
                ManageWindow.attach(w)
                WindowChrome.style(w)
            }
            // AppKit puts the buttons back at the top after a resize, a full screen change or a new key window.
            for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didExitFullScreenNotification,
                         NSWindow.didEndLiveResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { [weak w] _ in
                    guard let w else { return }
                    MainActor.assumeIsolated { WindowChrome.placeButtons(w) }
                })
            }
        }

        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }

    @MainActor static func style(_ w: NSWindow) {
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.styleMask.insert(.fullSizeContentView)
        w.backgroundColor = NSColor(srgbRed: 0x0C / 255, green: 0x0C / 255, blue: 0x0B / 255, alpha: 1)
        w.appearance = NSAppearance(named: .darkAqua)
        placeButtons(w)
    }

    /// Makes the title bar as high as the top bar of earshot, and puts the buttons in its middle, 20 pt from the left.
    @MainActor static func placeButtons(_ w: NSWindow) {
        guard !w.styleMask.contains(.fullScreen),
              let close = w.standardWindowButton(.closeButton), let bar = close.superview, let container = bar.superview else { return }
        var frame = container.frame
        frame.size.height = barHeight
        frame.origin.y = w.frame.height - barHeight
        container.frame = frame
        bar.frame = container.bounds
        var x: CGFloat = 20
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let b = w.standardWindowButton(kind) else { continue }
            b.setFrameOrigin(NSPoint(x: x, y: ((barHeight - b.frame.height) / 2).rounded()))
            x += b.frame.width + 8
        }
    }
}

/// An area that moves the window when the owner drags it, for the empty parts of the top bar.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Area() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Area: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
        }
    }
}
