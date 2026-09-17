import Foundation

/// Flat directory of binary payloads (image data, thumbnails, RTF), named by item id.
final class BlobStore {
    let directory: URL

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(for relativePath: String) -> URL {
        directory.appendingPathComponent(relativePath)
    }

    @discardableResult
    func write(_ data: Data, name: String) throws -> String {
        try data.write(to: url(for: name), options: .atomic)
        return name
    }

    func data(for relativePath: String?) -> Data? {
        guard let relativePath else { return nil }
        return try? Data(contentsOf: url(for: relativePath))
    }

    func delete(_ relativePath: String?) {
        guard let relativePath else { return }
        try? FileManager.default.removeItem(at: url(for: relativePath))
    }

    func deleteAll() {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func totalSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}
