import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum FilterKind: String, CaseIterable, Identifiable {
    case all = "All"
    case text = "Text"
    case images = "Images"
    case links = "Links"
    case files = "Files"
    case pinned = "Pinned"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .images: return "photo"
        case .links: return "link"
        case .files: return "doc"
        case .pinned: return "pin"
        }
    }

    func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.type == .text
        case .images: return item.type == .image
        case .links: return item.type == .link
        case .files: return item.type == .file
        case .pinned: return item.pinned
        }
    }
}

/// State for the panel UI. Reads synchronously from the store (small, indexed queries).
@MainActor
final class PanelViewModel: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published var filter: FilterKind = .all {
        didSet { if filter != oldValue { selectFirstIfSearching() } }
    }
    @Published var searchText = "" {
        didSet { if searchText != oldValue { selectFirstIfSearching() } }
    }
    @Published var selectedID: String?

    /// Called when the user picks an item. `plainText` asks for formatting to be dropped (text items only).
    var onSelect: ((ClipItem, _ plainText: Bool) -> Void)?
    /// Called with the hovered text item and its frame in SwiftUI global coordinates, or nil when hover ends.
    var onHover: ((ClipItem?, CGRect) -> Void)?

    private let store: HistoryStore
    private let settings: AppSettings
    private var observer: NSObjectProtocol?

    init(store: HistoryStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        observer = NotificationCenter.default.addObserver(forName: .clipboardHistoryDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Sections

    private var normalizedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }

    private func passes(_ item: ClipItem) -> Bool {
        guard filter.matches(item) else { return false }
        let query = normalizedSearch
        guard !query.isEmpty else { return true }
        if item.previewText.localizedCaseInsensitiveContains(query) { return true }
        if item.type != .image, item.content.localizedCaseInsensitiveContains(query) { return true }
        if let title = item.title, title.localizedCaseInsensitiveContains(query) { return true }
        if let app = item.sourceAppName, app.localizedCaseInsensitiveContains(query) { return true }
        if item.type == .image, "image".localizedCaseInsensitiveContains(query) { return true }
        return false
    }

    /// Pinned items that pass the filter and search, most recently pinned first.
    var pinnedSection: [ClipItem] {
        items.filter { $0.pinned && passes($0) }
            .sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
    }

    /// Unpinned items that pass the filter and search, newest first (store order).
    var recentSection: [ClipItem] {
        guard filter != .pinned else { return [] }
        return items.filter { !$0.pinned && passes($0) }
    }

    var orderedVisible: [ClipItem] { pinnedSection + recentSection }

    var isSearching: Bool { !searchText.isEmpty }

    var blobStore: BlobStore { store.blobs }

    /// ⌘1 … ⌘9 badge index for a card, if it is among the first nine visible.
    func quickIndex(for item: ClipItem) -> Int? {
        guard let index = orderedVisible.prefix(9).firstIndex(where: { $0.id == item.id }) else { return nil }
        return index + 1
    }

    // MARK: - Lifecycle

    func reload() {
        items = store.allItems()
        if let selectedID, !items.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }

    func prepareForPresentation() {
        filter = .all
        searchText = ""
        selectedID = nil
        reload()
    }

    // MARK: - Search

    func appendSearch(_ text: String) {
        searchText += text
    }

    /// Returns false when there was nothing to delete.
    @discardableResult
    func deleteSearchBackward() -> Bool {
        guard !searchText.isEmpty else { return false }
        searchText.removeLast()
        return true
    }

    func clearSearch() {
        searchText = ""
        selectedID = nil
    }

    private func selectFirstIfSearching() {
        selectedID = isSearching ? orderedVisible.first?.id : nil
    }

    // MARK: - Selection

    func moveSelection(by delta: Int) {
        let list = orderedVisible
        guard !list.isEmpty else { return }
        let newIndex: Int
        if let selectedID, let current = list.firstIndex(where: { $0.id == selectedID }) {
            newIndex = min(max(current + delta, 0), list.count - 1)
        } else {
            newIndex = delta >= 0 ? 0 : list.count - 1
        }
        selectedID = list[newIndex].id
    }

    func activateSelection(optionHeld: Bool = false) {
        guard let selectedID, let item = items.first(where: { $0.id == selectedID }) else { return }
        select(item, optionHeld: optionHeld)
    }

    func quickSelect(index: Int, optionHeld: Bool) {
        let list = orderedVisible
        guard list.indices.contains(index) else { return }
        select(list[index], optionHeld: optionHeld)
    }

    /// ⌥ inverts the "copy as plain text" default.
    func select(_ item: ClipItem, optionHeld: Bool = false) {
        let plain = settings.copyAsPlainTextByDefault != optionHeld
        onSelect?(item, plain)
    }

    // MARK: - Mutations

    func togglePin(_ item: ClipItem) {
        store.setPinned(id: item.id, !item.pinned)
        reload()
    }

    func delete(_ item: ClipItem) {
        let list = orderedVisible
        let index = list.firstIndex(where: { $0.id == item.id })
        store.delete(id: item.id)
        reload()
        if selectedID == item.id || selectedID == nil, let index {
            let remaining = orderedVisible
            selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
    }

    func deleteSelection() {
        guard let selectedID, let item = items.first(where: { $0.id == selectedID }) else { return }
        delete(item)
    }

    // MARK: - Hover

    func hoverChanged(_ item: ClipItem, isHovering: Bool, frame: CGRect) {
        onHover?(isHovering ? item : nil, frame)
    }

    // MARK: - Drag out

    /// Item provider for dragging a card into another app or Finder.
    func dragProvider(for item: ClipItem) -> NSItemProvider {
        switch item.type {
        case .text:
            return NSItemProvider(object: item.content as NSString)
        case .link:
            if let url = item.url { return NSItemProvider(object: url as NSURL) }
            return NSItemProvider(object: item.content as NSString)
        case .file:
            if let path = item.filePaths.first, let provider = NSItemProvider(contentsOf: URL(fileURLWithPath: path)) {
                return provider
            }
            return NSItemProvider()
        case .image:
            // Export to a nicely named temporary file so Finder drops get a readable filename.
            guard let blobPath = item.blobPath else { return NSItemProvider() }
            let source = store.blobs.url(for: blobPath)
            let name = "Clipboard Image \(item.imageWidth ?? 0)×\(item.imageHeight ?? 0).\(source.pathExtension)"
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardManagerDrag", isDirectory: true)
            try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let destination = temp.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.copyItem(at: source, to: destination)
            }
            return NSItemProvider(contentsOf: destination) ?? NSItemProvider()
        }
    }
}
