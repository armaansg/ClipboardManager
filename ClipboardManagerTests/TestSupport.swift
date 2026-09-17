import AppKit
import XCTest
@testable import ClipboardManager

/// Shared helpers: temporary stores, synthetic pasteboards, generated images.
enum TestSupport {
    static func temporaryDirectory(_ name: String = #function) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeStore() throws -> (HistoryStore, URL) {
        let dir = try temporaryDirectory()
        return (try HistoryStore(rootDirectory: dir), dir)
    }

    /// A private pasteboard so tests never touch the user's real clipboard.
    static func pasteboard() -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("dev.armaan.ClipboardManagerTests.\(UUID().uuidString)"))
        pb.clearContents()
        return pb
    }

    static func pngData(width: Int, height: Int, transparent: Bool) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            if transparent {
                NSColor.systemGreen.setFill()
                NSBezierPath(ovalIn: rect).fill()
            } else {
                NSGradient(starting: .red, ending: .blue)!.draw(in: rect, angle: 45)
            }
            return true
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if !transparent {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
        }
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    static func textItem(_ text: String, hash: String? = nil, pinned: Bool = false, createdAt: Date = Date(),
                         app: String? = "TestApp", bundleID: String? = "com.example.test") -> ClipItem {
        var item = ClipItem(type: .text, contentHash: hash ?? CaptureProcessor.sha256(Data(text.utf8)),
                            previewText: text, content: text)
        item.pinned = pinned
        item.pinnedAt = pinned ? createdAt : nil
        item.createdAt = createdAt
        item.byteSize = Int64(text.utf8.count)
        item.sourceAppName = app
        item.sourceBundleID = bundleID
        return item
    }
}
