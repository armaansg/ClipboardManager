import Foundation
import os

extension Notification.Name {
    /// Posted on the main queue whenever history rows change.
    static let clipboardHistoryDidChange = Notification.Name("dev.armaan.ClipboardManager.historyDidChange")
}

/// SQLite-backed history with blob sidecar files. All database access is serialized on a private queue,
/// so every method is safe to call from any thread. Methods are synchronous; keep calls off hot paths.
final class HistoryStore: @unchecked Sendable {
    private static let log = Logger(subsystem: AppConfig.bundleID, category: "store")

    let rootDirectory: URL
    let databaseURL: URL
    let blobs: BlobStore
    private let db: SQLiteDatabase
    private let queue = DispatchQueue(label: "dev.armaan.ClipboardManager.store", qos: .userInitiated)

    init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        blobs = try BlobStore(directory: rootDirectory.appendingPathComponent("blobs", isDirectory: true))
        databaseURL = rootDirectory.appendingPathComponent("history.sqlite")
        db = try SQLiteDatabase(path: databaseURL.path)
        try queue.sync { try migrate() }
        Self.log.info("Opened history store at \(rootDirectory.path, privacy: .public)")
    }

    private func migrate() throws {
        try db.exec("PRAGMA journal_mode=WAL;")
        try db.exec("""
        CREATE TABLE IF NOT EXISTS items (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            preview_text TEXT NOT NULL,
            content TEXT NOT NULL,
            title TEXT,
            is_rich INTEGER NOT NULL DEFAULT 0,
            source_bundle_id TEXT,
            source_app_name TEXT,
            created_at REAL NOT NULL,
            pinned INTEGER NOT NULL DEFAULT 0,
            pinned_at REAL,
            byte_size INTEGER NOT NULL DEFAULT 0,
            image_width INTEGER,
            image_height INTEGER,
            blob_path TEXT,
            thumb_path TEXT,
            uti TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_items_hash ON items(content_hash);
        CREATE INDEX IF NOT EXISTS idx_items_created ON items(created_at);
        CREATE INDEX IF NOT EXISTS idx_items_pinned ON items(pinned, pinned_at);
        PRAGMA user_version = 1;
        """)
    }

    // MARK: - Row mapping

    private static let columns = """
    id, type, content_hash, preview_text, content, title, is_rich, source_bundle_id, source_app_name,
    created_at, pinned, pinned_at, byte_size, image_width, image_height, blob_path, thumb_path, uti
    """

    private static func mapRow(_ row: SQLRow) -> ClipItem {
        ClipItem(
            id: row.text(0) ?? "",
            type: ClipItemType(rawValue: row.text(1) ?? "") ?? .text,
            contentHash: row.text(2) ?? "",
            previewText: row.text(3) ?? "",
            content: row.text(4) ?? "",
            title: row.text(5),
            isRich: row.bool(6),
            sourceBundleID: row.text(7),
            sourceAppName: row.text(8),
            createdAt: row.date(9),
            pinned: row.bool(10),
            pinnedAt: row.optionalDate(11),
            byteSize: row.int(12),
            imageWidth: row.optionalInt(13),
            imageHeight: row.optionalInt(14),
            blobPath: row.text(15),
            thumbPath: row.text(16),
            uti: row.text(17)
        )
    }

    private func values(for item: ClipItem) -> [SQLValue] {
        [
            .text(item.id), .text(item.type.rawValue), .text(item.contentHash), .text(item.previewText),
            .text(item.content), .optionalText(item.title), .bool(item.isRich),
            .optionalText(item.sourceBundleID), .optionalText(item.sourceAppName),
            .date(item.createdAt), .bool(item.pinned), .optionalDate(item.pinnedAt), .int(item.byteSize),
            .optionalInt(item.imageWidth), .optionalInt(item.imageHeight),
            .optionalText(item.blobPath), .optionalText(item.thumbPath), .optionalText(item.uti),
        ]
    }

    // MARK: - Reads

    /// Every item, newest first.
    func allItems() -> [ClipItem] {
        queue.sync {
            (try? db.query("SELECT \(Self.columns) FROM items ORDER BY created_at DESC", [], Self.mapRow)) ?? []
        }
    }

    func item(id: String) -> ClipItem? {
        queue.sync {
            (try? db.query("SELECT \(Self.columns) FROM items WHERE id = ?", [.text(id)], Self.mapRow))?.first
        }
    }

    func count() -> Int {
        queue.sync { Int((try? db.scalarInt("SELECT COUNT(*) FROM items")) ?? 0) }
    }

    func storageUsage() -> (database: Int64, blobs: Int64) {
        let dbFiles = [databaseURL, URL(fileURLWithPath: databaseURL.path + "-wal"), URL(fileURLWithPath: databaseURL.path + "-shm")]
        let dbBytes = dbFiles.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
        return (dbBytes, blobs.totalSize())
    }

    // MARK: - Writes

    /// Inserts a freshly captured item. If an item with the same content hash already exists, the older row
    /// (and its blobs) is removed first so history stays strictly chronological; pinned state carries over.
    @discardableResult
    func save(_ incoming: ClipItem) -> ClipItem {
        var item = incoming
        queue.sync {
            do {
                try db.exec("BEGIN IMMEDIATE")
                let duplicates = try db.query("SELECT \(Self.columns) FROM items WHERE content_hash = ?",
                                              [.text(item.contentHash)], Self.mapRow)
                for old in duplicates {
                    if old.pinned {
                        item.pinned = true
                        item.pinnedAt = old.pinnedAt ?? Date()
                    }
                    try deleteRowLocked(old)
                }
                try db.run("""
                INSERT INTO items (\(Self.columns)) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, values(for: item))
                try db.exec("COMMIT")
                if !duplicates.isEmpty {
                    Self.log.info("Collapsed \(duplicates.count) duplicate(s) of \(item.type.rawValue, privacy: .public) item; moved to front")
                }
            } catch {
                try? db.exec("ROLLBACK")
                Self.log.error("save failed: \(String(describing: error), privacy: .public)")
            }
        }
        notifyChange()
        return item
    }

    /// Moves an existing item to the front (used when the user re-copies from the panel).
    func touch(id: String) {
        queue.sync {
            try? db.run("UPDATE items SET created_at = ? WHERE id = ?", [.date(Date()), .text(id)])
        }
        notifyChange()
    }

    func setPinned(id: String, _ pinned: Bool) {
        queue.sync {
            try? db.run("UPDATE items SET pinned = ?, pinned_at = ? WHERE id = ?",
                        [.bool(pinned), pinned ? .date(Date()) : .null, .text(id)])
        }
        notifyChange()
    }

    func delete(id: String) {
        queue.sync {
            guard let item = (try? db.query("SELECT \(Self.columns) FROM items WHERE id = ?", [.text(id)], Self.mapRow))?.first else { return }
            try? deleteRowLocked(item)
        }
        notifyChange()
    }

    func clear(includingPinned: Bool) {
        queue.sync {
            do {
                if includingPinned {
                    try db.run("DELETE FROM items")
                    blobs.deleteAll()
                } else {
                    let victims = try db.query("SELECT \(Self.columns) FROM items WHERE pinned = 0", [], Self.mapRow)
                    for item in victims { try deleteRowLocked(item) }
                }
                try db.exec("VACUUM")
            } catch {
                Self.log.error("clear failed: \(String(describing: error), privacy: .public)")
            }
        }
        Self.log.info("Cleared history (includingPinned=\(includingPinned))")
        notifyChange()
    }

    // MARK: - Retention

    /// Deletes unpinned items older than the retention window, then evicts oldest unpinned items until the
    /// store is under the global byte cap. Pinned items are never touched.
    func runRetention(maxAge: TimeInterval = Double(AppConfig.retentionDays) * 86_400,
                      capBytes: Int64 = AppConfig.storeCapBytes) {
        var expired = 0
        var evicted = 0
        queue.sync {
            do {
                let cutoff = Date().addingTimeInterval(-maxAge)
                let old = try db.query("SELECT \(Self.columns) FROM items WHERE pinned = 0 AND created_at < ?",
                                       [.date(cutoff)], Self.mapRow)
                for item in old {
                    try deleteRowLocked(item)
                    expired += 1
                }

                var total = try db.scalarInt("SELECT COALESCE(SUM(byte_size), 0) FROM items")
                if total > capBytes {
                    let candidates = try db.query("SELECT \(Self.columns) FROM items WHERE pinned = 0 ORDER BY created_at ASC",
                                                  [], Self.mapRow)
                    for item in candidates where total > capBytes {
                        try deleteRowLocked(item)
                        total -= item.byteSize
                        evicted += 1
                    }
                }
            } catch {
                Self.log.error("retention failed: \(String(describing: error), privacy: .public)")
            }
        }
        if expired > 0 || evicted > 0 {
            Self.log.info("Retention pass: expired \(expired), evicted \(evicted) for size cap")
            notifyChange()
        }
    }

    // MARK: - Helpers

    private func deleteRowLocked(_ item: ClipItem) throws {
        try db.run("DELETE FROM items WHERE id = ?", [.text(item.id)])
        blobs.delete(item.blobPath)
        blobs.delete(item.thumbPath)
    }

    private func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
        }
    }
}
