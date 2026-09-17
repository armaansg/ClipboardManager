import AppKit
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
    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var viewModel: PanelViewModel!
    private var panelController: PanelController!
    private var statusItemController: StatusItemController!
    private var hotKeyManager: HotKeyManager!
    private var retentionTimer: Timer?

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

        viewModel = PanelViewModel(store: store)
        panelController = PanelController(viewModel: viewModel)
        monitor = ClipboardMonitor(store: store)

        panelController.onItemSelected = { [weak self] item in
            self?.copyBackToPasteboard(item)
        }

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
            }
        ))

        hotKeyManager = HotKeyManager(definition: AppConfig.toggleHotKey) { [weak self] in
            self?.panelController.toggle()
        }
        if let error = hotKeyManager.register() {
            Self.log.error("Hot key registration failed (\(AppConfig.toggleHotKey.displayString, privacy: .public)): OSStatus \(error)")
        } else {
            Self.log.info("Registered global shortcut \(AppConfig.toggleHotKey.displayString, privacy: .public)")
        }

        monitor.start()
        scheduleRetention()
        installDebugHooks()

        Self.log.info("\(AppConfig.displayName, privacy: .public) launched silently from \(Bundle.main.bundleURL.path, privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        hotKeyManager?.unregister()
    }

    // MARK: - Selection → pasteboard

    private func copyBackToPasteboard(_ item: ClipItem) {
        // Flag first so the poller can never observe the change before it knows it is ours.
        monitor.expectSelfWrite(itemID: item.id)
        guard PasteboardWriter.write(item, blobs: store.blobs) != nil else {
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
        DispatchQueue.global(qos: .utility).async {
            store.runRetention()
        }
    }

    private func storageDescription() -> String {
        let usage = store.storageUsage()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: usage.database + usage.blobs)
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
        case "snapshot":
            // Renders the panel's view hierarchy offscreen (layout check only; the glass blur is composited by the window server).
            guard let view = self.panelController.panel.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            let path = argument ?? NSTemporaryDirectory() + "ClipboardManager-snapshot.png"
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            Self.log.info("DEBUG snapshot written to \(path, privacy: .public)")
        case "pin-first":
            if let first = self.store.allItems().first { self.store.setPinned(id: first.id, !first.pinned) }
        case "filter":
            self.viewModel.filter = FilterKind(rawValue: argument ?? "All") ?? .all
        case "select-right": self.viewModel.moveSelection(by: 1)
        case "select-left": self.viewModel.moveSelection(by: -1)
        case "confirm": self.viewModel.activateSelection()
        case "toggle": self.panelController.toggle()
        case "show": self.panelController.show()
        case "hide": self.panelController.hide()
        case "status":
            let front = NSWorkspace.shared.frontmostApplication
            Self.log.info("DEBUG status: panelVisible=\(self.panelController.isVisible) panelIsKey=\(self.panelController.panel.isKeyWindow) appActive=\(NSApp.isActive) frontmost=\(front?.bundleIdentifier ?? "nil", privacy: .public) items=\(self.store.count()) paused=\(self.monitor.isPaused)")
        case "retention": self.runRetention()
        case "pause": self.monitor.isPaused = true; self.statusItemController.refreshAppearance()
        case "resume": self.monitor.isPaused = false; self.statusItemController.refreshAppearance()
        case "clear": self.store.clear(includingPinned: argument == "all")
        default: Self.log.info("DEBUG unknown command \(command, privacy: .public)")
        }
    }
    #endif
}
