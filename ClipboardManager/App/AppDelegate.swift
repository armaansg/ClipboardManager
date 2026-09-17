import AppKit
import Combine
import os

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let log = Logger(subsystem: AppConfig.bundleID, category: "app")
    private static var shared: AppDelegate?

    /// Pure AppKit entry point: no SwiftUI `App`/`WindowGroup`, so nothing can open a window at launch.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // belt and braces alongside LSUIElement in Info.plist
        app.run()
    }

    // Everything below is retained for the lifetime of the app. NSStatusItem in particular
    // disappears from the menu bar the moment it is deallocated.
    private let settings = AppSettings.shared
    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var viewModel: PanelViewModel!
    private var panelController: PanelController!
    private var statusItemController: StatusItemController!
    private var hotKeyManager: HotKeyManager!
    private var updateManager: UpdateManager!
    private var settingsWindow: SettingsWindowController!
    private var welcomeTip: WelcomeTipController!
    private var retentionTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try HistoryStore(rootDirectory: AppConfig.storageRoot)
        } catch {
            Self.log.error("Failed to open history store: \(String(describing: error), privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "\(AppConfig.displayName) could not open its database."
            alert.informativeText = "\(error)"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        updateManager = UpdateManager()
        viewModel = PanelViewModel(store: store, settings: settings)
        panelController = PanelController(viewModel: viewModel, settings: settings)
        monitor = ClipboardMonitor(store: store)

        panelController.onItemSelected = { [weak self] item, plainText in
            self?.copyBackToPasteboard(item, plainText: plainText)
        }

        settingsWindow = SettingsWindowController(
            settings: settings, updates: updateManager,
            onClearHistory: { [weak self] includingPinned in self?.store.clear(includingPinned: includingPinned) },
            storageDescription: { [weak self] in self?.storageDescription() ?? "" }
        )
        welcomeTip = WelcomeTipController(
            settings: settings,
            openSettings: { [weak self] in self?.settingsWindow.show() },
            showPanel: { [weak self] in self?.panelController.show() }
        )

        statusItemController = StatusItemController(actions: .init(
            togglePanel: { [weak self] in self?.panelController.toggle() },
            isPanelVisible: { [weak self] in self?.panelController.isVisible ?? false },
            isPaused: { [weak self] in self?.monitor.isPaused ?? false },
            setPaused: { [weak self] paused in self?.monitor.isPaused = paused },
            clearHistory: { [weak self] includingPinned in self?.store.clear(includingPinned: includingPinned) },
            storageDescription: { [weak self] in self?.storageDescription() ?? "" },
            openStorageFolder: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.activateFileViewerSelecting([self.store.databaseURL])
            },
            openSettings: { [weak self] in self?.settingsWindow.show() },
            checkForUpdates: { [weak self] in self?.updateManager.checkForUpdates() },
            currentHotKey: { [weak self] in self?.settings.hotKey ?? AppConfig.toggleHotKey }
        ))

        hotKeyManager = HotKeyManager(definition: settings.hotKey) { [weak self] in
            self?.panelController.toggle()
        }
        reportHotKey(status: hotKeyManager.register())
        settings.$hotKey
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] definition in
                guard let self else { return }
                self.reportHotKey(status: self.hotKeyManager.rebind(to: definition))
                self.statusItemController.refreshAppearance()
            }
            .store(in: &cancellables)

        monitor.start()
        scheduleRetention()
        installDebugHooks()
        welcomeTip.showIfNeeded()

        Self.log.info("\(AppConfig.displayName, privacy: .public) launched silently from \(Bundle.main.bundleURL.path, privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        hotKeyManager?.unregister()
    }

    // MARK: - Hot key

    private func reportHotKey(status: OSStatus?) {
        let binding = settings.hotKey.displayString
        if let status {
            Self.log.error("Hot key registration failed (\(binding, privacy: .public)): OSStatus \(status)")
            settings.hotKeyError = "Couldn't register \(binding) (error \(status)). Another app may already use it; pick a different combination."
        } else {
            settings.hotKeyError = nil
            Self.log.info("Registered global shortcut \(binding, privacy: .public)")
        }
    }

    // MARK: - Selection → pasteboard

    private func copyBackToPasteboard(_ item: ClipItem, plainText: Bool) {
        // Flag first so the poller can never observe the change before it knows it is ours.
        monitor.expectSelfWrite(itemID: item.id)
        guard PasteboardWriter.write(item, blobs: store.blobs, plainText: plainText) != nil else {
            monitor.cancelSelfWrite()
            Self.log.error("Failed to write item \(item.id, privacy: .public) back to the pasteboard")
            return
        }
    }

    // MARK: - Retention

    private func scheduleRetention() {
        runRetention()
        let timer = Timer(timeInterval: AppConfig.retentionInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runRetention() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        retentionTimer = timer
    }

    private func runRetention() {
        let store = self.store!
        let maxAge = settings.retentionInterval
        let cap = settings.storeCapBytes
        DispatchQueue.global(qos: .utility).async {
            store.runRetention(maxAge: maxAge, capBytes: cap)
        }
    }

    private func storageDescription() -> String {
        let usage = store.storageUsage()
        return Formatters.bytes(usage.database + usage.blobs)
    }

    // MARK: - Debug hooks (not compiled into Release)

    private func installDebugHooks() {
        #if DEBUG
        // Lets a shell script drive the app during development without synthesizing key events:
        //   swift Scripts/debug-command.swift toggle
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("dev.armaan.ClipboardManager.debug"), object: nil, queue: .main
        ) { [weak self] note in
            let command = note.userInfo?["command"] as? String ?? note.object as? String ?? ""
            let argument = note.userInfo?["argument"] as? String
            Task { @MainActor in self?.handleDebugCommand(command, argument: argument) }
        }
        #endif
    }

    #if DEBUG
    private func handleDebugCommand(_ command: String, argument: String?) {
        switch command {
        case "toggle": panelController.toggle()
        case "show": panelController.show()
        case "hide": panelController.hide()
        case "status":
            let front = NSWorkspace.shared.frontmostApplication
            Self.log.info("DEBUG status: panelVisible=\(self.panelController.isVisible) panelIsKey=\(self.panelController.panel.isKeyWindow) appActive=\(NSApp.isActive) frontmost=\(front?.bundleIdentifier ?? "nil", privacy: .public) items=\(self.store.count()) paused=\(self.monitor.isPaused) search='\(self.viewModel.searchText, privacy: .public)' visible=\(self.viewModel.orderedVisible.count) selected=\(self.viewModel.selectedID ?? "nil", privacy: .public) hotkey=\(self.settings.hotKey.displayString, privacy: .public)")
        case "retention": runRetention()
        case "pause": monitor.isPaused = true; statusItemController.refreshAppearance()
        case "resume": monitor.isPaused = false; statusItemController.refreshAppearance()
        case "clear": store.clear(includingPinned: argument == "all")
        case "snapshot":
            guard let view = panelController.panel.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            let path = argument ?? NSTemporaryDirectory() + "ClipboardManager-snapshot.png"
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            Self.log.info("DEBUG snapshot written to \(path, privacy: .public)")
        case "pin-first":
            if let first = store.allItems().first { store.setPinned(id: first.id, !first.pinned) }
        case "filter": viewModel.filter = FilterKind(rawValue: argument ?? "All") ?? .all
        case "select-right": viewModel.moveSelection(by: 1)
        case "select-left": viewModel.moveSelection(by: -1)
        case "confirm": viewModel.activateSelection(optionHeld: argument == "plain")
        case "type": viewModel.appendSearch(argument ?? "")
        case "backspace": _ = viewModel.deleteSearchBackward()
        case "quick": viewModel.quickSelect(index: (Int(argument ?? "1") ?? 1) - 1, optionHeld: false)
        case "settings": settingsWindow.show()
        case "welcome": welcomeTip.show()
        case "exclude": if let argument { settings.addExclusion(argument) }
        case "unexclude": if let argument { settings.removeExclusion(argument) }
        case "hotkey":
            // e.g. "hotkey cmd,ctrl:9" → ⌃⌘9
            if let argument, let spec = Self.parseHotKey(argument) { settings.hotKey = spec }
        case "height": if let argument, let value = Double(argument) { settings.panelHeightFraction = value }
        default: Self.log.info("DEBUG unknown command \(command, privacy: .public)")
        }
    }

    private static func parseHotKey(_ spec: String) -> HotKeyDefinition? {
        let parts = spec.split(separator: ":")
        guard parts.count == 2, let keyCode = UInt32(parts[1]) else { return nil }
        var mods: NSEvent.ModifierFlags = []
        for m in parts[0].split(separator: ",") {
            switch m { case "cmd": mods.insert(.command); case "ctrl": mods.insert(.control)
            case "opt": mods.insert(.option); case "shift": mods.insert(.shift); default: break }
        }
        return HotKeyDefinition(keyCode: keyCode, modifiers: mods)
    }
    #endif
}
