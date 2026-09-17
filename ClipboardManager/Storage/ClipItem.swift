import Foundation

enum ClipItemType: String, CaseIterable {
    case text
    case image
    case link
    case file

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .link: return "Link"
        case .file: return "File"
        }
    }

    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .link: return "link"
        case .file: return "doc"
        }
    }
}

/// One row of clipboard history. Large payloads (images, RTF) live on disk in the blob store.
struct ClipItem: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var type: ClipItemType
    var contentHash: String
    /// Short text shown on the card (first ~2000 characters for text; dimensions for images; names for files).
    var previewText: String
    /// Full text, URL string, or JSON array of file paths, depending on `type`.
    var content: String
    /// Link page title if the pasteboard offered one; first filename for file items.
    var title: String?
    var isRich = false
    var sourceBundleID: String?
    var sourceAppName: String?
    var createdAt = Date()
    var pinned = false
    var pinnedAt: Date?
    var byteSize: Int64 = 0
    var imageWidth: Int?
    var imageHeight: Int?
    /// Paths are relative to the blob directory.
    var blobPath: String?
    var thumbPath: String?
    /// Original pasteboard type identifier so the item can be written back in the same form.
    var uti: String?

    var filePaths: [String] {
        guard type == .file, let data = content.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    var url: URL? {
        guard type == .link else { return nil }
        return URL(string: content)
    }

    static func encodeFilePaths(_ paths: [String]) -> String {
        guard let data = try? JSONEncoder().encode(paths) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
