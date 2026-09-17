import XCTest
@testable import ClipboardManager

final class HistoryStoreTests: XCTestCase {
    private var store: HistoryStore!
    private var directory: URL!

    override func setUpWithError() throws {
        (store, directory) = try TestSupport.makeStore()
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveAndReadBackNewestFirst() {
        store.save(TestSupport.textItem("first", createdAt: Date(timeIntervalSinceNow: -10)))
        store.save(TestSupport.textItem("second"))
        XCTAssertEqual(store.allItems().map(\.content), ["second", "first"])
        XCTAssertEqual(store.count(), 2)
    }

    func testDuplicateCollapsesToFrontAndKeepsPinnedState() {
        let old = TestSupport.textItem("dup", pinned: true, createdAt: Date(timeIntervalSinceNow: -100))
        store.save(old)
        store.save(TestSupport.textItem("other", createdAt: Date(timeIntervalSinceNow: -50)))
        let fresh = TestSupport.textItem("dup")
        let saved = store.save(fresh)

        let items = store.allItems()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.id, fresh.id)
        XCTAssertNil(items.first(where: { $0.id == old.id }))
        XCTAssertTrue(saved.pinned)
        XCTAssertNotNil(saved.pinnedAt)
    }

    func testDuplicateDeletesOldBlobs() throws {
        var old = TestSupport.textItem("rich", createdAt: Date(timeIntervalSinceNow: -100))
        old.blobPath = try store.blobs.write(Data("old".utf8), name: "\(old.id).rtf")
        store.save(old)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.blobs.url(for: old.blobPath!).path))
        store.save(TestSupport.textItem("rich"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.blobs.url(for: old.blobPath!).path))
    }

    func testTouchMovesToFront() {
        let a = TestSupport.textItem("a", createdAt: Date(timeIntervalSinceNow: -20))
        store.save(a)
        store.save(TestSupport.textItem("b", createdAt: Date(timeIntervalSinceNow: -10)))
        store.touch(id: a.id)
        XCTAssertEqual(store.allItems().first?.id, a.id)
    }

    func testPinAndDelete() {
        let item = TestSupport.textItem("pin me")
        store.save(item)
        store.setPinned(id: item.id, true)
        XCTAssertTrue(store.item(id: item.id)?.pinned ?? false)
        store.setPinned(id: item.id, false)
        XCTAssertFalse(store.item(id: item.id)?.pinned ?? true)
        store.delete(id: item.id)
        XCTAssertNil(store.item(id: item.id))
    }

    func testRetentionExpiresOldUnpinnedOnly() {
        let eightDays: TimeInterval = 8 * 86_400
        store.save(TestSupport.textItem("old", createdAt: Date(timeIntervalSinceNow: -eightDays)))
        store.save(TestSupport.textItem("old pinned", pinned: true, createdAt: Date(timeIntervalSinceNow: -eightDays)))
        store.save(TestSupport.textItem("new"))
        store.runRetention(maxAge: 7 * 86_400, capBytes: .max)
        XCTAssertEqual(Set(store.allItems().map(\.content)), ["old pinned", "new"])
    }

    func testRetentionEvictsOldestUnpinnedUntilUnderCap() {
        for (index, size) in [100, 100, 100, 100].enumerated() {
            var item = TestSupport.textItem("item\(index)", createdAt: Date(timeIntervalSinceNow: Double(index)))
            item.byteSize = Int64(size)
            item.pinned = index == 0 // the oldest is pinned and must survive
            store.save(item)
        }
        store.runRetention(maxAge: .infinity, capBytes: 250)
        let remaining = store.allItems().map(\.content)
        XCTAssertEqual(Set(remaining), ["item0", "item3"])
    }

    func testClearUnpinnedKeepsPinned() {
        store.save(TestSupport.textItem("keep", pinned: true))
        store.save(TestSupport.textItem("drop"))
        store.clear(includingPinned: false)
        XCTAssertEqual(store.allItems().map(\.content), ["keep"])
        store.clear(includingPinned: true)
        XCTAssertEqual(store.count(), 0)
    }

    func testStorageUsageCountsDatabaseAndBlobs() throws {
        try store.blobs.write(Data(count: 4_096), name: "blob.bin")
        let usage = store.storageUsage()
        XCTAssertGreaterThan(usage.database, 0)
        XCTAssertEqual(usage.blobs, 4_096)
    }

    func testChangeNotificationIsPosted() {
        let expectation = expectation(forNotification: .clipboardHistoryDidChange, object: nil)
        store.save(TestSupport.textItem("notify"))
        wait(for: [expectation], timeout: 2)
    }

    func testReopenPersists() throws {
        store.save(TestSupport.textItem("persisted"))
        store = nil
        let reopened = try HistoryStore(rootDirectory: directory)
        XCTAssertEqual(reopened.allItems().map(\.content), ["persisted"])
    }
}
