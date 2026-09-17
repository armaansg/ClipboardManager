import AppKit
import SwiftUI

/// Standard titled settings window. Shown on demand from the menu bar; the app activates so it can take focus.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: AppSettings
    private let updates: UpdateManager
    private let onClearHistory: (_ includingPinned: Bool) -> Void
    private let storageDescription: () -> String

    init(settings: AppSettings, updates: UpdateManager,
         onClearHistory: @escaping (_ includingPinned: Bool) -> Void,
         storageDescription: @escaping () -> String) {
        self.settings = settings
        self.updates = updates
        self.onClearHistory = onClearHistory
        self.storageDescription = storageDescription
    }

    func show() {
        if window == nil {
            let root = SettingsView(onClearHistory: onClearHistory, storageDescription: storageDescription)
                .environmentObject(settings)
                .environmentObject(updates)
            let controller = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: controller)
            window.title = "\(AppConfig.displayName) Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(controller.view.fittingSize)
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Give focus back to whatever the user was doing; an accessory app has nothing else to show.
        NSApp.hide(nil)
    }
}
