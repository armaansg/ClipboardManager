import AppKit
import UniformTypeIdentifiers

/// Thumbnails for cards, decoded off the main thread and cached in memory.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 400
    }

    func image(for relativePath: String?, in blobs: BlobStore) async -> NSImage? {
        guard let relativePath else { return nil }
        if let cached = cache.object(forKey: relativePath as NSString) { return cached }
        let url = blobs.url(for: relativePath)
        let loaded = await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value
        if let loaded { cache.setObject(loaded, forKey: relativePath as NSString) }
        return loaded
    }
}

/// Source application icons keyed by bundle identifier.
final class AppIconCache {
    static let shared = AppIconCache()
    private var icons: [String: NSImage] = [:]
    private let lock = NSLock()

    func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        icons[bundleID] = icon
        return icon
    }
}

/// File icons keyed by path; falls back to a generic document icon for files that no longer exist.
final class FileIconCache {
    static let shared = FileIconCache()
    private var icons: [String: NSImage] = [:]
    private let lock = NSLock()

    func icon(forPath path: String?) -> NSImage {
        let key = path ?? ""
        lock.lock()
        defer { lock.unlock() }
        if let cached = icons[key] { return cached }
        let icon: NSImage
        if let path, FileManager.default.fileExists(atPath: path) {
            icon = NSWorkspace.shared.icon(forFile: path)
        } else if let path, let type = UTType(filenameExtension: (path as NSString).pathExtension) {
            icon = NSWorkspace.shared.icon(for: type)
        } else {
            icon = NSWorkspace.shared.icon(for: .data)
        }
        icon.size = NSSize(width: 64, height: 64)
        icons[key] = icon
        return icon
    }
}

/// Sizes of referenced files, read from disk once per path set.
final class FileSizeCache {
    static let shared = FileSizeCache()
    private var sizes: [String: String] = [:]
    private let lock = NSLock()

    func description(forPaths paths: [String]) -> String {
        let key = paths.joined(separator: "\u{0}")
        lock.lock()
        defer { lock.unlock() }
        if let cached = sizes[key] { return cached }
        var total: Int64 = 0
        var missing = 0
        for path in paths {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path), let size = attrs[.size] as? Int64 {
                total += size
            } else {
                missing += 1
            }
        }
        let text = missing == paths.count ? "Missing" : Formatters.bytes(total) + (missing > 0 ? " (some missing)" : "")
        sizes[key] = text
        return text
    }
}

enum Formatters {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()

    static func bytes(_ count: Int64) -> String {
        byteFormatter.string(fromByteCount: count)
    }
}

enum TextHeuristics {
    private static let codeSymbols: Set<Character> = ["{", "}", "(", ")", ";", "=", "<", ">", "[", "]", "/", "#", "$", "\\", "|", "&", "*"]
    private static let codeKeywords = ["func ", "def ", "import ", "class ", "struct ", "return ", "const ", "let ", "var ", "#include", "public ", "private ", "SELECT ", "fn ", "=> ", "->", "</", "/>"]

    /// Cheap heuristic: indented lines, symbol density, or common keywords.
    static func looksLikeCode(_ text: String) -> Bool {
        let sample = text.prefix(1_500)
        let lines = sample.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return false }

        let indented = lines.filter { $0.first == " " || $0.first == "\t" }.count
        if lines.count >= 3, Double(indented) / Double(lines.count) >= 0.3 { return true }

        let nonSpace = sample.filter { !$0.isWhitespace }
        guard !nonSpace.isEmpty else { return false }
        let symbols = nonSpace.filter { codeSymbols.contains($0) }.count
        if Double(symbols) / Double(nonSpace.count) >= 0.10 { return true }

        let lower = String(sample)
        return codeKeywords.contains { lower.contains($0) } && lines.count >= 2
    }
}
