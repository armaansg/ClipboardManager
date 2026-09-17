import AppKit
import SwiftUI

/// Floating, click-through preview of a text card, shown above the panel after a short hover delay.
@MainActor
final class HoverPreviewController {
    private var window: NSPanel?
    private var pending: DispatchWorkItem?
    private var currentItemID: String?

    func schedule(item: ClipItem, anchor: NSRect, parent: NSWindow) {
        if currentItemID == item.id, window != nil { return }
        cancel()
        currentItemID = item.id
        let work = DispatchWorkItem { [weak self] in
            self?.present(item: item, anchor: anchor, parent: parent)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConfig.hoverPreviewDelay, execute: work)
    }

    /// Cancels a pending presentation and hides any visible preview.
    func cancel() {
        pending?.cancel()
        pending = nil
        currentItemID = nil
        dismiss()
    }

    func dismiss() {
        pending?.cancel()
        pending = nil
        guard let window else { return }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        self.window = nil
    }

    private func present(item: ClipItem, anchor: NSRect, parent: NSWindow) {
        dismiss()
        guard let screen = parent.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width: CGFloat = 520
        let gap: CGFloat = 8
        let bottom = parent.frame.maxY + gap
        let maxHeight = max(80, visible.maxY - bottom - gap)

        let hosting = NSHostingView(rootView: HoverPreviewView(item: item, width: width))
        hosting.sizingOptions = []
        var size = hosting.fittingSize
        size.width = width
        size.height = min(size.height, maxHeight)

        var x = anchor.midX - width / 2
        x = min(max(x, visible.minX + gap), visible.maxX - width - gap)
        let frame = NSRect(x: x.rounded(), y: bottom.rounded(), width: width, height: size.height.rounded())

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = parent.level
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        let background = GlassBackgroundView(cornerRadius: 16, roundsBottomCorners: true)
        background.frame = NSRect(origin: .zero, size: frame.size)
        background.autoresizingMask = [.width, .height]
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        panel.contentView = background

        panel.alphaValue = 0
        parent.addChildWindow(panel, ordered: .above)
        window = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }
}

struct HoverPreviewView: View {
    let item: ClipItem
    let width: CGFloat

    private var text: String {
        String(item.content.prefix(AppConfig.hoverTextCharacterLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: item.type.symbolName)
                Text(TextHeuristics.looksLikeCode(item.content) ? "Code" : (item.isRich ? "Rich Text" : "Text"))
                Text("·")
                Text("\(item.content.count.formatted()) characters")
                Spacer()
                if let name = item.sourceAppName {
                    Text(name)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            Text(text)
                .font(TextHeuristics.looksLikeCode(item.content) ? .system(.body, design: .monospaced) : .body)
                .lineLimit(AppConfig.hoverPreviewMaxLines)
                .truncationMode(.tail)
                .textSelection(.disabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .frame(width: width)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}
