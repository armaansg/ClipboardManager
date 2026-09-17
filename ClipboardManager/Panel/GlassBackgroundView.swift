import AppKit

/// Translucent "glass" backdrop. Uses NSGlassEffectView on macOS 26 (Liquid Glass) and falls back to
/// NSVisualEffectView (.hudWindow, behind-window blending) on macOS 14/15.
/// When `roundsBottomCorners` is false the effect view is extended below the window edge so only the top corners show.
final class GlassBackgroundView: NSView {
    private let effectView: NSView
    private let cornerRadius: CGFloat
    private let roundsBottomCorners: Bool

    init(cornerRadius: CGFloat, roundsBottomCorners: Bool) {
        self.cornerRadius = cornerRadius
        self.roundsBottomCorners = roundsBottomCorners
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            effectView = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = GlassBackgroundView.roundedMask(radius: cornerRadius)
            effectView = effect
        }
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(effectView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        var frame = bounds
        if !roundsBottomCorners {
            frame.origin.y -= cornerRadius
            frame.size.height += cornerRadius
        }
        effectView.frame = frame
    }

    /// Resizable mask with rounded corners; stretchable center keeps the corners crisp at any size.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
