import XCTest
@testable import ClipboardManager

@MainActor
final class StatusMenuTests: XCTestCase {
    private func makeController() -> StatusItemController {
        StatusItemController(actions: .init(
            togglePanel: {}, isPanelVisible: { false }, isPaused: { false }, setPaused: { _ in },
            clearHistory: { _ in }, storageDescription: { "12 MB" }, openStorageFolder: {},
            openSettings: {}, checkForUpdates: {},
            currentHotKey: { AppSettings.shared.hotKey }
        ))
    }

    func testRightClickMenuBuildsWithExpectedItems() {
        let menu = makeController().buildMenu()
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(titles, [
            "Show Clipboard Panel", "Pause Recording", "Clear History…", "Storage Used: 12 MB",
            "Launch at Login", "Open Storage Folder", "Settings…", "Check for Updates…",
            "Quit Clipboard Manager",
        ])
        XCTAssertEqual(menu.items.first?.keyEquivalent, AppSettings.shared.hotKey.keyEquivalent)
        XCTAssertEqual(menu.items.first?.keyEquivalentModifierMask, AppSettings.shared.hotKey.modifiers)
        XCTAssertFalse(menu.items.first(where: { $0.title.hasPrefix("Storage Used") })?.isEnabled ?? true)
    }

    func testMenuBuildsForEveryPossibleShortcut() {
        // The menu shows the current shortcut as a key equivalent; it must never trap for any key code.
        let controller = StatusItemController(actions: .init(
            togglePanel: {}, isPanelVisible: { true }, isPaused: { true }, setPaused: { _ in },
            clearHistory: { _ in }, storageDescription: { "" }, openStorageFolder: {},
            openSettings: {}, checkForUpdates: {},
            currentHotKey: { HotKeyDefinition(keyCode: 0x6F /* kVK_F12 */, modifiers: [.command]) }
        ))
        let menu = controller.buildMenu()
        XCTAssertEqual(menu.items.first?.title, "Hide Clipboard Panel")
        XCTAssertEqual(menu.items[1].title, "Resume Recording")
        for code in 0...127 {
            let hotKey = HotKeyDefinition(keyCode: UInt32(code), modifiers: [.control])
            let item = NSMenuItem(title: "t", action: nil, keyEquivalent: hotKey.keyEquivalent)
            item.keyEquivalentModifierMask = hotKey.modifiers
        }
    }
}
