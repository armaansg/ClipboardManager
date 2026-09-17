import AppKit

/// Borderless, non-activating floating panel. It can become key (so typing, arrow keys, Return and Esc work)
/// without activating the app, which keeps the user's frontmost app frontmost.
final class ClipboardPanel: NSPanel {
    enum KeyCommand {
        case escape
        case left, right
        /// Return. `plain` is true when ⌥ is held (copy text without formatting).
        case confirm(plain: Bool)
        /// Delete key: edits the search if one is active, otherwise deletes the selected card.
        case deleteBackward
        /// ⌘Delete / forward delete: always deletes the selected card.
        case deleteItem
        /// ⌘1 … ⌘9 (with ⌥ for plain text).
        case quickSelect(index: Int, plain: Bool)
        /// Printable characters: type-to-search.
        case insertText(String)
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
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let plain = modifiers.contains(.option)

        if modifiers.contains(.command) {
            if let chars = event.charactersIgnoringModifiers, let digit = Int(chars), (1...9).contains(digit) {
                return .quickSelect(index: digit - 1, plain: plain)
            }
            if event.keyCode == 51 { return .deleteItem }
            return nil // leave other ⌘ shortcuts alone
        }

        switch event.keyCode {
        case 53: return .escape
        case 123: return .left
        case 124: return .right
        case 36, 76: return .confirm(plain: plain)
        case 51: return .deleteBackward
        case 117: return .deleteItem
        default: break
        }

        // Type-to-search: plain or shifted printable characters only.
        guard modifiers.subtracting(.shift).isEmpty, let text = event.characters, !text.isEmpty else { return nil }
        let printable = text.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
        }
        return printable ? .insertText(text) : nil
    }
}
