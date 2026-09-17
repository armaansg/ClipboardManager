import AppKit
import SwiftUI

/// Brief "Copied" confirmation that appears near the bottom of the screen after an item is selected,
/// in the spirit of the system volume HUD. Click-through and non-activating.
@MainActor
final class CopiedHUDController {
    private var window: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(for item: ClipItem, plainText: Bool, on screen: NSScreen) {
        dismiss(animated: false)

        let hosting = NSHostingView(rootView: CopiedHUDView(item: item, plainText: plainText))
        hosting.sizingOptions = []
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        let frame = NSRect(x: (visible.midX - size.width / 2).rounded(),
                           y: (visible.minY + 48).rounded(),
                           width: size.width.rounded(), height: size.height.rounded())

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        let background = GlassBackgroundView(cornerRadius: 14, roundsBottomCorners: true)
        background.frame = NSRect(origin: .zero, size: frame.size)
        background.autoresizingMask = [.width, .height]
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        panel.contentView = background

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        window = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in self?.dismiss(animated: true) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func dismiss(animated: Bool) {
        hideWork?.cancel()
        hideWork = nil
        guard let panel = window else { return }
        window = nil
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }
}

private struct CopiedHUDView: View {
    let item: ClipItem
    let plainText: Bool

    private var detail: String {
        switch item.type {
        case .text: return plainText && item.isRich ? "Plain text" : (item.isRich ? "Rich text" : "Text")
        case .image: return "Image"
        case .link: return "Link"
        case .file: return item.filePaths.count > 1 ? "\(item.filePaths.count) files" : "File"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Copied")
                    .font(.headline)
                Text("\(detail) · press ⌘V to paste")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }
}
