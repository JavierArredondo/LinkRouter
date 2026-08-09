import AppKit
import SwiftUI

/// Owns an ordinary `NSWindow` hosting SwiftUI content.
///
/// The app deliberately does not use SwiftUI `Settings` / `WindowGroup` scenes: in an `.accessory`
/// (menu-bar) app they proved unreliable — `showSettingsWindow:` reports the action as handled while
/// no window is ever created, leaving no way to reach settings at all. An AppKit-owned window is
/// explicit, testable by inspection, and behaves the same across macOS versions.
@MainActor
final class HostedWindowController {
    private var window: NSWindow?

    func show<Content: View>(title: String, content: () -> Content) {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingView(rootView: content())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
        // Without this the window is deallocated on close while this controller still holds a
        // reference, so reopening it would use freed memory.
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}
