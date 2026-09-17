import AppKit
import SwiftUI
import os

/// Owns the bottom-anchored clipboard panel: sizing on the active display, slide animation,
/// key handling, all dismissal paths, and the hover preview.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private static let log = Logger(subsystem: AppConfig.bundleID, category: "panel")

    let panel: ClipboardPanel
    let viewModel: PanelViewModel
    private let hostingView: NSHostingView<AnyView>
    private let hoverPreview = HoverPreviewController()
    private(set) var isVisible = false
    private var lastResignHide = Date.distantPast

    /// Invoked when the user picks an item (click or Return). The panel hides itself afterwards.
    var onItemSelected: ((ClipItem) -> Void)?

    init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
        panel = ClipboardPanel()

        let background = GlassBackgroundView(cornerRadius: AppConfig.panelCornerRadius, roundsBottomCorners: false)
        background.frame = panel.contentView?.bounds ?? .zero
        background.autoresizingMask = [.width, .height]

        hostingView = NSHostingView(rootView: AnyView(PanelView().environmentObject(viewModel)))
        hostingView.frame = background.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        background.addSubview(hostingView)
        panel.contentView = background

        super.init()

        panel.delegate = self
        panel.keyCommandHandler = { [weak self] command in
            self?.handle(command) ?? false
        }
        viewModel.onSelect = { [weak self] item in
            guard let self else { return }
            self.onItemSelected?(item)
            self.hide()
        }
        viewModel.onHover = { [weak self] item, frame in
            self?.hoverChanged(item: item, frame: frame)
        }
    }

    // MARK: - Show / hide

    func toggle() {
        if isVisible {
            hide()
        } else {
            // A status-item click can make the panel resign key (hiding it) right before this toggle fires.
            guard Date().timeIntervalSince(lastResignHide) > 0.3 else { return }
            show()
        }
    }

    func show() {
        guard !isVisible else { return }
        let screen = Self.activeScreen()
        let target = Self.panelFrame(on: screen)
        var start = target
        start.origin.y -= target.height

        viewModel.prepareForPresentation()
        isVisible = true
        panel.setFrame(start, display: false)
        // makeKeyAndOrderFront on a .nonactivatingPanel gives us key events without activating the app.
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = AppConfig.panelAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }

        let front = NSWorkspace.shared.frontmostApplication
        Self.log.info("Panel shown on \(screen.localizedName, privacy: .public); appActive=\(NSApp.isActive) frontmost=\(front?.bundleIdentifier ?? "nil", privacy: .public)")
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        hoverPreview.dismiss()
        var end = panel.frame
        end.origin.y -= end.height

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AppConfig.panelAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(end, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isVisible else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    // MARK: - NSWindowDelegate

    /// Clicking anywhere outside the panel makes another window key; treat that as dismissal.
    func windowDidResignKey(_ notification: Notification) {
        guard isVisible else { return }
        lastResignHide = Date()
        hide()
    }

    // MARK: - Keyboard

    private func handle(_ command: ClipboardPanel.KeyCommand) -> Bool {
        switch command {
        case .escape:
            hide()
        case .left:
            viewModel.moveSelection(by: -1)
        case .right:
            viewModel.moveSelection(by: 1)
        case .confirm:
            viewModel.activateSelection()
        case .delete:
            viewModel.deleteSelection()
        }
        return true
    }

    // MARK: - Hover preview

    private func hoverChanged(item: ClipItem?, frame: CGRect) {
        guard let item, isVisible else {
            hoverPreview.cancel()
            return
        }
        let anchor = screenRect(fromSwiftUIGlobal: frame)
        hoverPreview.schedule(item: item, anchor: anchor, parent: panel)
    }

    /// SwiftUI's global space is the hosting view with a top-left origin; convert to AppKit screen coordinates.
    private func screenRect(fromSwiftUIGlobal rect: CGRect) -> NSRect {
        let height = hostingView.bounds.height
        let windowRect = NSRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        return panel.convertToScreen(windowRect)
    }

    // MARK: - Geometry

    /// The display currently containing the mouse cursor.
    static func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Full visible width, 20% of the visible height, anchored to the bottom of the visible frame.
    static func panelFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let height = (visible.height * AppConfig.panelHeightFraction).rounded()
        return NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: height)
    }
}
