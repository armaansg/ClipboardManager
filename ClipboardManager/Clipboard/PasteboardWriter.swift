import AppKit
import UniformTypeIdentifiers

/// Writes a stored item back to the general pasteboard in its original representation.
/// Never simulates a paste keystroke.
enum PasteboardWriter {
    /// Returns the pasteboard changeCount after writing, or nil if nothing could be written.
    static func write(_ item: ClipItem, blobs: BlobStore, plainText: Bool = false) -> Int? {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.type {
        case .text:
            let pbItem = NSPasteboardItem()
            pbItem.setString(item.content, forType: .string)
            if item.isRich, !plainText, let rtf = blobs.data(for: item.blobPath) {
                pbItem.setData(rtf, forType: .rtf)
            }
            guard pasteboard.writeObjects([pbItem]) else { return nil }

        case .link:
            let pbItem = NSPasteboardItem()
            pbItem.setString(item.content, forType: .URL)
            pbItem.setString(item.content, forType: .string)
            if let title = item.title {
                pbItem.setString(title, forType: PasteboardReader.urlNameType)
            }
            guard pasteboard.writeObjects([pbItem]) else { return nil }

        case .file:
            let urls = item.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
            guard !urls.isEmpty, pasteboard.writeObjects(urls) else { return nil }

        case .image:
            guard let data = blobs.data(for: item.blobPath) else { return nil }
            let pbItem = NSPasteboardItem()
            let isPNG = item.uti == UTType.png.identifier
            pbItem.setData(data, forType: isPNG ? .png : PasteboardReader.jpegType)
            // Many apps only read TIFF/PNG, so always offer a TIFF alongside the stored representation.
            if let tiff = NSImage(data: data)?.tiffRepresentation {
                pbItem.setData(tiff, forType: .tiff)
            }
            guard pasteboard.writeObjects([pbItem]) else { return nil }
        }
        return pasteboard.changeCount
    }
}
