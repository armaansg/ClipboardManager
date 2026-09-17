import AppKit
import Combine
import Foundation

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
        didSet { if filter != oldValue { selectedID = nil } }
    }
    @Published var selectedID: String?

    var onSelect: ((ClipItem) -> Void)?
    /// Called with the hovered text item and its frame in SwiftUI global coordinates, or nil when hover ends.
    var onHover: ((ClipItem?, CGRect) -> Void)?

    private let store: HistoryStore
    private var observer: NSObjectProtocol?

    init(store: HistoryStore) {
        self.store = store
        observer = NotificationCenter.default.addObserver(forName: .clipboardHistoryDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Sections

    /// Pinned items that pass the filter, most recently pinned first.
    var pinnedSection: [ClipItem] {
        items.filter { $0.pinned && filter.matches($0) }
            .sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
    }

    /// Unpinned items that pass the filter, newest first (store order).
    var recentSection: [ClipItem] {
        guard filter != .pinned else { return [] }
        return items.filter { !$0.pinned && filter.matches($0) }
    }

    var orderedVisible: [ClipItem] { pinnedSection + recentSection }

    var blobStore: BlobStore { store.blobs }

    // MARK: - Lifecycle

    func reload() {
        items = store.allItems()
        if let selectedID, !items.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }

    func prepareForPresentation() {
        filter = .all
        selectedID = nil
        reload()
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

    func activateSelection() {
        guard let selectedID, let item = items.first(where: { $0.id == selectedID }) else { return }
        select(item)
    }

    func select(_ item: ClipItem) {
        onSelect?(item)
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
}
