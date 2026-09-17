import AppKit

/// Borderless, non-activating floating panel. It can become key (so arrow keys / Return / Esc work)
/// without activating the app, which keeps the user's frontmost app frontmost.
final class ClipboardPanel: NSPanel {
    enum KeyCommand {
        case escape, left, right, confirm, delete
    }

    /// Return true to consume the event.
    var keyCommandHandler: ((KeyCommand) -> Bool)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 800, height: 240),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        // Transparent window: required for the glass material to show through.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let command = Self.command(for: event), keyCommandHandler?(command) == true {
            return
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        _ = keyCommandHandler?(.escape)
    }

    private static func command(for event: NSEvent) -> KeyCommand? {
        switch event.keyCode {
        case 53: return .escape
        case 123: return .left
        case 124: return .right
        case 36, 76: return .confirm
        case 51, 117: return .delete
        default: return nil
        }
    }
}
