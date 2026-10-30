import AppKit
import SwiftUI

final class MainWindowController: NSWindowController, NSWindowDelegate {
    var onHide: (() -> Void)?

    init<Content: View>(rootView: Content) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Grab Pic"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.gpCanvas
        window.minSize = NSSize(width: 900, height: 640)
        window.appearance = NSAppearance(named: .darkAqua)
        window.tabbingMode = .disallowed
        // Never bring the window back by itself (state restoration or a remembered full-screen
        // space); it opens only when the user asks for it.
        window.isRestorable = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = NSHostingView(rootView: rootView)
        super.init(window: window)
        window.delegate = self

        window.setFrameAutosaveName("GrabpicMainWindow")
        if !window.setFrameUsingName("GrabpicMainWindow") {
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        onHide?()
        return false
    }
}
