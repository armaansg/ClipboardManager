import AppKit
import Carbon.HIToolbox

/// Central place for tunables. Everything a user might reasonably want to change lives here.
enum AppConfig {
    static let appName = "ClipboardManager"
    static let displayName = "Clipboard Manager"
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "dev.armaan.ClipboardManager" }

    // MARK: Global shortcut
    //
    // Change the shortcut by editing this single constant.
    //   keyCode:   a Carbon virtual key code (kVK_ANSI_A ... kVK_Space, kVK_F1 ...). See Carbon.HIToolbox/Events.h.
    //   modifiers: any combination of .command, .shift, .option, .control.
    // Default is Command-Shift-V. Note: many apps bind this to "Paste and Match Style"; a global hot key wins while this app runs.
    // The change takes effect on next launch (or rebuild). The menu bar item shows the current binding.
    static let toggleHotKey = HotKeyDefinition(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .shift])

    // MARK: Capture
    static let pollInterval: TimeInterval = 0.3
    static let pollLeeway: DispatchTimeInterval = .milliseconds(100)

    // MARK: Retention
    static let retentionDays = 7
    static let retentionInterval: TimeInterval = 60 * 60
    static let storeCapBytes: Int64 = 500 * 1024 * 1024
    static let maxItemBytes: Int64 = 10 * 1024 * 1024

    // MARK: Images
    static let maxImageEdge: CGFloat = 2048
    static let thumbnailEdge: CGFloat = 256
    static let jpegQuality: CGFloat = 0.7

    // MARK: Panel
    static let panelHeightFraction: CGFloat = 0.20
    static let panelCornerRadius: CGFloat = 26
    static let panelAnimationDuration: TimeInterval = 0.2
    static let hoverPreviewDelay: TimeInterval = 0.4
    static let hoverPreviewMaxLines = 40
    static let cardWidth: CGFloat = 250
    static let previewTextCharacterLimit = 2_000
    static let hoverTextCharacterLimit = 12_000

    // MARK: Storage locations
    static var storageRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appName, isDirectory: true)
    }
}

/// A global keyboard shortcut, expressed in Carbon terms so it can be registered with RegisterEventHotKey.
struct HotKeyDefinition {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }

    /// Key equivalent string usable for NSMenuItem.keyEquivalent.
    var keyEquivalent: String {
        switch Int(keyCode) {
        case kVK_Space: return " "
        case kVK_Return: return "\r"
        case kVK_Tab: return "\t"
        case kVK_Escape: return "\u{1B}"
        case kVK_Delete: return "\u{08}"
        case kVK_LeftArrow: return String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case kVK_RightArrow: return String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case kVK_UpArrow: return String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case kVK_DownArrow: return String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case kVK_F1...kVK_F12 where fKeyIndex != nil:
            return String(UnicodeScalar(NSF1FunctionKey + fKeyIndex!)!)
        default:
            return HotKeyDefinition.character(forKeyCode: keyCode).lowercased()
        }
    }

    private var fKeyIndex: Int? {
        let table: [Int: Int] = [kVK_F1: 0, kVK_F2: 1, kVK_F3: 2, kVK_F4: 3, kVK_F5: 4, kVK_F6: 5,
                                 kVK_F7: 6, kVK_F8: 7, kVK_F9: 8, kVK_F10: 9, kVK_F11: 10, kVK_F12: 11]
        return table[Int(keyCode)]
    }

    /// Human readable form, e.g. "⌃⇧V".
    var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        switch Int(keyCode) {
        case kVK_Space: s += "Space"
        case kVK_Return: s += "↩"
        case kVK_Tab: s += "⇥"
        case kVK_Escape: s += "⎋"
        case kVK_Delete: s += "⌫"
        case kVK_LeftArrow: s += "←"
        case kVK_RightArrow: s += "→"
        case kVK_UpArrow: s += "↑"
        case kVK_DownArrow: s += "↓"
        default:
            if let f = fKeyIndex { s += "F\(f + 1)" } else { s += HotKeyDefinition.character(forKeyCode: keyCode).uppercased() }
        }
        return s
    }

    /// Translates a virtual key code to the character it produces on the current ASCII-capable layout.
    static func character(forKeyCode keyCode: UInt32) -> String {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return ""
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysMask),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "" }
        return String(utf16CodeUnits: chars, count: length)
    }
}
