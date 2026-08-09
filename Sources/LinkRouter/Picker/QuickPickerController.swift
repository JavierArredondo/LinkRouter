import AppKit
import SwiftUI

@MainActor
final class QuickPickerController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    /// Non-nil exactly while a selection is outstanding. Nilling it before calling is what guarantees
    /// the coordinator is resumed once and only once — if any dismissal path failed to report back,
    /// `isProcessing` would stay true and every later link would queue forever.
    private var completion: ((Destination?, Bool) -> Void)?
    private var hasBeenKey = false

    func show(url: URL, destinations: [Destination], message: String?, selection: @escaping (Destination?, Bool) -> Void) {
        // The coordinator routes serially, so this should not happen; resolve rather than drop the
        // pending callback if it ever does.
        if completion != nil { finish(nil, remember: false) }

        completion = selection
        hasBeenKey = false

        let sections = PickerLayout.sections(for: destinations)
        let view = QuickPickerView(url: url, sections: sections, message: message) { [weak self] destination, remember in
            self?.finish(destination, remember: remember)
        }

        let panel = QuickPickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        // Links are often clicked from a full-screen app; without this the picker would never show there.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        // Measure before positioning: sizing afterwards leaves the panel visibly off-centre.
        panel.setContentSize(hosting.fittingSize)
        position(panel)

        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func finish(_ destination: Destination?, remember: Bool) {
        guard let completion else { return }
        self.completion = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        completion(destination, remember)
    }

    private func position(_ panel: NSPanel) {
        // `NSScreen.main` follows the key window, which is unreliable for a background app, so
        // prefer the screen the pointer is on.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return panel.center() }
        let size = panel.frame.size
        // Slightly above centre reads as a launcher rather than an alert.
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2 + frame.height * 0.08
        ))
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) { finish(nil, remember: false) }

    func windowDidBecomeKey(_ notification: Notification) { hasBeenKey = true }

    /// Clicking away dismisses an ephemeral panel. Gated on having been key at least once, so a
    /// panel that never took focus cannot cancel itself the instant it appears.
    func windowDidResignKey(_ notification: Notification) {
        guard hasBeenKey else { return }
        finish(nil, remember: false)
    }
}

/// A borderless window refuses key status by default, which would kill every keyboard shortcut.
private final class QuickPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
