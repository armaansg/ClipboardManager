import AppKit
import ServiceManagement
import os

/// Owns the persistent NSStatusItem. Left-click toggles the panel; right-click (or control-click) shows the menu.
/// The menu is the app's only settings surface.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var togglePanel: () -> Void
        var isPanelVisible: () -> Bool
        var isPaused: () -> Bool
        var setPaused: (Bool) -> Void
        var clearHistory: (_ includingPinned: Bool) -> Void
        var storageDescription: () -> String
        var openStorageFolder: () -> Void
    }

    private static let log = Logger(subsystem: AppConfig.bundleID, category: "menubar")
    private let actions: Actions
    /// Strong reference is mandatory: a released NSStatusItem vanishes from the menu bar.
    private let statusItem: NSStatusItem

    init(actions: Actions) {
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: AppConfig.displayName)
            image?.isTemplate = true
            button.image = image
            button.toolTip = "\(AppConfig.displayName) (\(AppConfig.toggleHotKey.displayString))"
            button.target = self
            button.action = #selector(handleClick(_:))
            // Assigning `statusItem.menu` directly would swallow left clicks, so both buttons are routed
            // through the action and the menu is attached only for the duration of a right-click.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshAppearance()
    }

    /// Dims the icon while recording is paused.
    func refreshAppearance() {
        let paused = actions.isPaused()
        statusItem.button?.appearsDisabled = paused
        statusItem.button?.toolTip = paused
            ? "\(AppConfig.displayName) — recording paused"
            : "\(AppConfig.displayName) (\(AppConfig.toggleHotKey.displayString))"
    }

    // MARK: - Click routing

    @objc private func handleClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isSecondary {
            showMenu()
        } else {
            actions.togglePanel()
        }
    }

    private func showMenu() {
        let menu = buildMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Detach again so the next left click reaches handleClick.
        statusItem.menu = nil
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let toggle = NSMenuItem(title: actions.isPanelVisible() ? "Hide Clipboard Panel" : "Show Clipboard Panel",
                                action: #selector(togglePanel), keyEquivalent: AppConfig.toggleHotKey.keyEquivalent)
        toggle.keyEquivalentModifierMask = AppConfig.toggleHotKey.modifiers
        toggle.target = self
        menu.addItem(toggle)

        let pause = NSMenuItem(title: actions.isPaused() ? "Resume Recording" : "Pause Recording",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let storage = NSMenuItem(title: "Storage Used: \(actions.storageDescription())", action: nil, keyEquivalent: "")
        storage.isEnabled = false
        menu.addItem(storage)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)

        let openFolder = NSMenuItem(title: "Open Storage Folder", action: #selector(openStorageFolder), keyEquivalent: "")
        openFolder.target = self
        menu.addItem(openFolder)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit \(AppConfig.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        return menu
    }

    // MARK: - Menu actions

    @objc private func togglePanel() { actions.togglePanel() }

    @objc private func togglePause() {
        actions.setPaused(!actions.isPaused())
        refreshAppearance()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "This permanently deletes stored clipboard items and their files. Pinned items can be kept."
        alert.alertStyle = .warning
        let clearAll = alert.addButton(withTitle: "Clear All")
        clearAll.hasDestructiveAction = true
        alert.addButton(withTitle: "Clear Unpinned Only")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: actions.clearHistory(true)
        case .alertSecondButtonReturn: actions.clearHistory(false)
        default: break
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
        } catch {
            Self.log.error("Launch at login change failed: \(String(describing: error), privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func openStorageFolder() { actions.openStorageFolder() }
}

/// Thin wrapper over SMAppService.mainApp. Registration always targets the running bundle,
/// so it is refused unless that bundle lives in /Applications (never a DerivedData path).
enum LaunchAtLogin {
    struct NotInstalledError: LocalizedError {
        var errorDescription: String? {
            "The app must be installed in /Applications before it can launch at login. Run Scripts/build-release.sh, then try again from the installed copy."
        }
    }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var isInstalledInApplications: Bool {
        Bundle.main.bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard isInstalledInApplications else { throw NotInstalledError() }
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
