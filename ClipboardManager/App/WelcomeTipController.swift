import AppKit
import SwiftUI

/// One-time first-run window: tells the user the app lives in the menu bar and which shortcut opens it.
@MainActor
final class WelcomeTipController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: AppSettings
    private let openSettings: () -> Void
    private let showPanel: () -> Void

    init(settings: AppSettings, openSettings: @escaping () -> Void, showPanel: @escaping () -> Void) {
        self.settings = settings
        self.openSettings = openSettings
        self.showPanel = showPanel
    }

    func showIfNeeded() {
        guard !settings.hasShownWelcome else { return }
        show()
    }

    func show() {
        settings.hasShownWelcome = true
        let root = WelcomeTipView(
            onTryIt: { [weak self] in self?.close(); self?.showPanel() },
            onSettings: { [weak self] in self?.close(); self?.openSettings() },
            onDone: { [weak self] in self?.close() }
        ).environmentObject(settings)
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.title = "Welcome"
        window.styleMask = [.titled, .closable]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.setContentSize(controller.view.fittingSize)
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.hide(nil)
    }
}

private struct WelcomeTipView: View {
    @EnvironmentObject private var settings: AppSettings
    let onTryIt: () -> Void
    let onSettings: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            VStack(spacing: 6) {
                Text("\(AppConfig.displayName) is running")
                    .font(.title2.weight(.semibold))
                Text("Look for the clipboard icon in your menu bar. There is no window and no Dock icon.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("Press")
                Text(settings.hotKey.displayString)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.15)))
                Text("to open your clipboard history")
            }
            VStack(alignment: .leading, spacing: 4) {
                Label("Type to search, ← → to browse, Return to copy, ⌘1–9 to grab a card", systemImage: "keyboard")
                Label("Passwords flagged by password managers are never recorded", systemImage: "lock.shield")
                Label("Everything stays on this Mac", systemImage: "internaldrive")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            HStack {
                Button("Settings…", action: onSettings)
                Spacer()
                Button("Try It", action: onTryIt)
                Button("Got It", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 440)
    }
}
