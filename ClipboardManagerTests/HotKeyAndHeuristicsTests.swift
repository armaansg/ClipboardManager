import Carbon.HIToolbox
import XCTest
@testable import ClipboardManager

final class HotKeyDefinitionTests: XCTestCase {
    func testDisplayStringOrdersModifiersLikeMacOS() {
        let def = HotKeyDefinition(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .shift])
        XCTAssertEqual(def.displayString, "⇧⌘V")
        XCTAssertEqual(def.keyEquivalent, "v")
    }

    func testCarbonModifierBits() {
        let def = HotKeyDefinition(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .control, .option, .shift])
        XCTAssertEqual(def.carbonModifiers, UInt32(cmdKey | controlKey | optionKey | shiftKey))
    }

    func testShiftAloneIsNotUsable() {
        XCTAssertFalse(HotKeyDefinition(keyCode: UInt32(kVK_ANSI_V), modifiers: [.shift]).isUsableAsGlobalShortcut)
        XCTAssertFalse(HotKeyDefinition(keyCode: UInt32(kVK_ANSI_V), modifiers: []).isUsableAsGlobalShortcut)
        XCTAssertTrue(HotKeyDefinition(keyCode: UInt32(kVK_ANSI_V), modifiers: [.control]).isUsableAsGlobalShortcut)
        XCTAssertTrue(HotKeyDefinition(keyCode: UInt32(kVK_F5), modifiers: []).isUsableAsGlobalShortcut)
    }

    func testIrrelevantModifierBitsAreDropped() {
        let def = HotKeyDefinition(keyCode: 9, modifiers: [.command, .capsLock, .numericPad, .function])
        XCTAssertEqual(def.modifiers, [.command])
    }

    func testFunctionKeyDisplay() {
        XCTAssertEqual(HotKeyDefinition(keyCode: UInt32(kVK_F12), modifiers: [.option]).displayString, "⌥F12")
        XCTAssertEqual(HotKeyDefinition(keyCode: UInt32(kVK_F12), modifiers: [.option]).keyEquivalent,
                       String(UnicodeScalar(NSF12FunctionKey)!))
    }

    func testKeyEquivalentForEveryKeyCodeDoesNotCrash() {
        for code in 0...127 {
            _ = HotKeyDefinition(keyCode: UInt32(code), modifiers: [.command]).keyEquivalent
            _ = HotKeyDefinition(keyCode: UInt32(code), modifiers: [.command]).displayString
        }
    }
}

final class TextHeuristicsTests: XCTestCase {
    func testProseIsNotCode() {
        XCTAssertFalse(TextHeuristics.looksLikeCode("The quick brown fox jumps over the lazy dog. It was a sunny day."))
    }

    func testIndentedBlockIsCode() {
        XCTAssertTrue(TextHeuristics.looksLikeCode("func hello() {\n    let x = 1\n    return x + 2\n}"))
    }

    func testSymbolDenseLineIsCode() {
        XCTAssertTrue(TextHeuristics.looksLikeCode("const f = (a, b) => ({ x: a[0], y: b[1] });"))
    }

    func testEmptyIsNotCode() {
        XCTAssertFalse(TextHeuristics.looksLikeCode(""))
        XCTAssertFalse(TextHeuristics.looksLikeCode("   \n  "))
    }
}

final class FormattersTests: XCTestCase {
    func testRelativeJustNow() {
        XCTAssertEqual(Formatters.relative(Date(), now: Date()), "just now")
    }

    func testRelativeMinutesAgo() {
        let now = Date()
        XCTAssertTrue(Formatters.relative(now.addingTimeInterval(-300), now: now).contains("5"))
    }
}
