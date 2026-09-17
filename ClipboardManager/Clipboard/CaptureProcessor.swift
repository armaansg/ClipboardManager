import AppKit
import CryptoKit
import Foundation
import os

struct SourceApp {
    var bundleID: String?
    var name: String?

    static func frontmost() -> SourceApp {
        let app = NSWorkspace.shared.frontmostApplication
        return SourceApp(bundleID: app?.bundleIdentifier, name: app?.localizedName)
    }
}

/// Converts a captured payload into a persisted ClipItem: hashing, image compression, blob writes, size gate.
/// Runs on a background queue; safe to call from anywhere.
enum CaptureProcessor {
    private static let log = Logger(subsystem: AppConfig.bundleID, category: "capture")

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func makeItem(from payload: CapturedPayload, source: SourceApp, blobs: BlobStore) -> ClipItem? {
        let hash = sha256(payload.hashInput)
        var item = ClipItem(type: .text, contentHash: hash, previewText: "", content: "")
        item.sourceBundleID = source.bundleID
        item.sourceAppName = source.name

        switch payload.content {
        case .text(let text, let rtf, let isRich):
            item.type = .text
            item.content = text
            item.previewText = makePreview(text)
            item.isRich = isRich
            item.byteSize = Int64(text.utf8.count)
            if let rtf, Int64(rtf.count) <= AppConfig.maxItemBytes {
                if let path = try? blobs.write(rtf, name: "\(item.id).rtf") {
                    item.blobPath = path
                    item.byteSize += Int64(rtf.count)
                }
            }
            item.uti = NSPasteboard.PasteboardType.string.rawValue

        case .image(let raw, let originalUTI):
            guard let processed = ImageProcessor.process(raw) else {
                log.error("Image decode failed (\(raw.count) bytes, \(originalUTI, privacy: .public))")
                return nil
            }
            let total = Int64(processed.data.count + processed.thumbnail.count)
            guard total <= AppConfig.maxItemBytes else {
                log.notice("Skipping image: \(total) bytes after compression exceeds cap")
                return nil
            }
            do {
                item.blobPath = try blobs.write(processed.data, name: "\(item.id).\(processed.fileExtension)")
                item.thumbPath = try blobs.write(processed.thumbnail, name: "\(item.id)_thumb.\(processed.thumbnailExtension)")
            } catch {
                log.error("Blob write failed: \(String(describing: error), privacy: .public)")
                blobs.delete(item.blobPath)
                return nil
            }
            item.type = .image
            item.imageWidth = processed.width
            item.imageHeight = processed.height
            item.byteSize = total
            item.uti = processed.uti
            item.previewText = "\(processed.width) × \(processed.height)"
            item.content = ""

        case .link(let url, let title):
            item.type = .link
            item.content = url.absoluteString
            item.title = title
            item.previewText = url.absoluteString
            item.byteSize = Int64(url.absoluteString.utf8.count)
            item.uti = NSPasteboard.PasteboardType.URL.rawValue

        case .files(let urls):
            item.type = .file
            let paths = urls.map(\.path)
            item.content = ClipItem.encodeFilePaths(paths)
            item.title = urls.first?.lastPathComponent
            item.previewText = urls.map(\.lastPathComponent).joined(separator: "\n")
            item.byteSize = urls.reduce(Int64(0)) { total, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return total + Int64(size)
            }
            item.uti = NSPasteboard.PasteboardType.fileURL.rawValue
        }
        return item
    }

    private static func makePreview(_ text: String) -> String {
        let trimmedLeading = text.drop(while: { $0 == "\n" || $0 == "\r" })
        return String(trimmedLeading.prefix(AppConfig.previewTextCharacterLimit))
    }
}
