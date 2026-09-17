import AppKit
import Foundation
import os

/// Polls NSPasteboard.general.changeCount on a background timer and persists new content.
/// macOS offers no clipboard-change notification, so polling is the standard approach.
final class ClipboardMonitor {
    private static let log = Logger(subsystem: AppConfig.bundleID, category: "monitor")

    private let store: HistoryStore
    private let pollQueue = DispatchQueue(label: "dev.armaan.ClipboardManager.poll", qos: .utility)
    private let processingQueue = DispatchQueue(label: "dev.armaan.ClipboardManager.process", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var timerSuspended = false
    private var lastChangeCount: Int
    private var expectedSelfWriteItemID: String?
    private let stateLock = NSLock()

    /// When true the poll timer is suspended entirely; nothing is read from the pasteboard.
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            isPaused ? suspend() : resume()
        }
    }

    init(store: HistoryStore) {
        self.store = store
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now() + AppConfig.pollInterval, repeating: AppConfig.pollInterval, leeway: AppConfig.pollLeeway)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
        Self.log.info("Polling started (every \(AppConfig.pollInterval, privacy: .public)s)")
    }

    func stop() {
        guard let timer else { return }
        if timerSuspended {
            timer.resume()
            timerSuspended = false
        }
        timer.cancel()
        self.timer = nil
    }

    /// Call *before* writing to the pasteboard: the next change is then treated as the app's own write and the
    /// existing row is moved to the front instead of being captured again.
    func expectSelfWrite(itemID: String) {
        stateLock.lock()
        expectedSelfWriteItemID = itemID
        stateLock.unlock()
    }

    /// Clears a pending self-write expectation (when the write failed).
    func cancelSelfWrite() {
        stateLock.lock()
        expectedSelfWriteItemID = nil
        stateLock.unlock()
    }

    // MARK: - Pause / resume

    private func suspend() {
        guard let timer, !timerSuspended else { return }
        timer.suspend()
        timerSuspended = true
        Self.log.info("Recording paused")
    }

    private func resume() {
        guard let timer, timerSuspended else { return }
        // Anything copied while paused stays unrecorded.
        stateLock.lock()
        lastChangeCount = NSPasteboard.general.changeCount
        stateLock.unlock()
        timer.resume()
        timerSuspended = false
        Self.log.info("Recording resumed")
    }

    // MARK: - Polling

    private func tick() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        stateLock.lock()
        guard count != lastChangeCount else {
            stateLock.unlock()
            return
        }
        lastChangeCount = count
        let selfWriteID = expectedSelfWriteItemID
        expectedSelfWriteItemID = nil
        stateLock.unlock()

        if let selfWriteID {
            store.touch(id: selfWriteID)
            Self.log.debug("Own write detected; item \(selfWriteID, privacy: .public) moved to front")
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.capture(changeCount: count)
        }
    }

    /// Main thread: reads the pasteboard and the frontmost app, then hands off to the processing queue.
    private func capture(changeCount: Int, attempt: Int = 0) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == changeCount else { return } // superseded already
        let source = SourceApp.frontmost()

        switch PasteboardReader.read(pasteboard) {
        case .skipped(.empty) where attempt < 2:
            // Apps call clearContents() (which bumps changeCount) and then add data. If the poll landed in
            // that gap the pasteboard looks empty; look again shortly, as long as nothing newer replaced it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.capture(changeCount: changeCount, attempt: attempt + 1)
            }
        case .skipped(let reason):
            Self.log.info("Skipped pasteboard change #\(changeCount): \(reason.rawValue, privacy: .public)")
        case .captured(let payload):
            let store = self.store
            processingQueue.async {
                guard let item = CaptureProcessor.makeItem(from: payload, source: source, blobs: store.blobs) else { return }
                let saved = store.save(item)
                Self.log.info("Captured \(saved.type.rawValue, privacy: .public) (\(saved.byteSize) bytes) from \(saved.sourceAppName ?? "unknown", privacy: .public) [\(saved.sourceBundleID ?? "-", privacy: .public)] pinned=\(saved.pinned)")
            }
        }
    }
}
