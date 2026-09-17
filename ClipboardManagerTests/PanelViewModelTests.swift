import XCTest
@testable import ClipboardManager

@MainActor
final class PanelViewModelTests: XCTestCase {
    private var store: HistoryStore!
    private var directory: URL!
    private var viewModel: PanelViewModel!

    override func setUpWithError() throws {
        (store, directory) = try TestSupport.makeStore()
        let base = Date()
        store.save(TestSupport.textItem("apple pie recipe", createdAt: base.addingTimeInterval(-30), app: "Notes"))
        store.save(TestSupport.textItem("banana bread", createdAt: base.addingTimeInterval(-20), app: "Safari"))
        store.save(TestSupport.textItem("cherry tart", pinned: true, createdAt: base.addingTimeInterval(-10), app: "Mail"))
        store.save(TestSupport.textItem("date squares", createdAt: base, app: "Notes"))
        viewModel = PanelViewModel(store: store, settings: AppSettings.shared)
        viewModel.prepareForPresentation()
    }

    override func tearDownWithError() throws {
        viewModel = nil
        store = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func testPinnedSectionComesFirstThenNewestFirst() {
        XCTAssertEqual(viewModel.orderedVisible.map(\.content), ["cherry tart", "date squares", "banana bread", "apple pie recipe"])
    }

    func testSearchNarrowsAndAutoSelectsFirstMatch() {
        viewModel.appendSearch("a")
        viewModel.appendSearch("n")
        XCTAssertEqual(viewModel.orderedVisible.map(\.content), ["banana bread"])
        XCTAssertEqual(viewModel.selectedID, viewModel.orderedVisible.first?.id)
        XCTAssertTrue(viewModel.isSearching)
    }

    func testSearchMatchesSourceAppName() {
        viewModel.appendSearch("notes")
        XCTAssertEqual(Set(viewModel.orderedVisible.map(\.content)), ["apple pie recipe", "date squares"])
    }

    func testSearchIsCaseInsensitiveAndBackspaceRestores() {
        viewModel.appendSearch("CHERRY")
        XCTAssertEqual(viewModel.orderedVisible.count, 1)
        viewModel.appendSearch("zz")
        XCTAssertEqual(viewModel.orderedVisible.count, 0)
        XCTAssertTrue(viewModel.deleteSearchBackward())
        XCTAssertTrue(viewModel.deleteSearchBackward())
        XCTAssertEqual(viewModel.orderedVisible.count, 1)
        viewModel.clearSearch()
        XCTAssertFalse(viewModel.deleteSearchBackward())
        XCTAssertEqual(viewModel.orderedVisible.count, 4)
        XCTAssertNil(viewModel.selectedID)
    }

    func testFilterPinnedShowsOnlyPinned() {
        viewModel.filter = .pinned
        XCTAssertEqual(viewModel.orderedVisible.map(\.content), ["cherry tart"])
        viewModel.filter = .images
        XCTAssertTrue(viewModel.orderedVisible.isEmpty)
    }

    func testArrowNavigationClampsAtEnds() {
        viewModel.moveSelection(by: -1)
        XCTAssertEqual(viewModel.selectedID, viewModel.orderedVisible.last?.id)
        viewModel.moveSelection(by: 1)
        XCTAssertEqual(viewModel.selectedID, viewModel.orderedVisible.last?.id)
        viewModel.selectedID = nil
        viewModel.moveSelection(by: 1)
        XCTAssertEqual(viewModel.selectedID, viewModel.orderedVisible.first?.id)
        viewModel.moveSelection(by: -1)
        XCTAssertEqual(viewModel.selectedID, viewModel.orderedVisible.first?.id)
    }

    func testQuickIndexCoversFirstNine() {
        XCTAssertEqual(viewModel.quickIndex(for: viewModel.orderedVisible[0]), 1)
        XCTAssertEqual(viewModel.quickIndex(for: viewModel.orderedVisible[3]), 4)
    }

    func testQuickSelectAndPlainTextInversion() {
        var received: [(String, Bool)] = []
        viewModel.onSelect = { item, plain in received.append((item.content, plain)) }
        let defaultPlain = AppSettings.shared.copyAsPlainTextByDefault
        viewModel.quickSelect(index: 1, optionHeld: false)
        viewModel.quickSelect(index: 1, optionHeld: true)
        viewModel.quickSelect(index: 99, optionHeld: false)
        XCTAssertEqual(received.map(\.0), ["date squares", "date squares"])
        XCTAssertEqual(received.map(\.1), [defaultPlain, !defaultPlain])
    }

    func testDeleteMovesSelectionToNeighbour() {
        viewModel.selectedID = viewModel.orderedVisible[1].id // "date squares"
        viewModel.deleteSelection()
        XCTAssertEqual(viewModel.orderedVisible.map(\.content), ["cherry tart", "banana bread", "apple pie recipe"])
        XCTAssertEqual(viewModel.selectedID, viewModel.orderedVisible[1].id)
    }

    func testTogglePinMovesItemBetweenSections() {
        let banana = viewModel.orderedVisible[2]
        viewModel.togglePin(banana)
        XCTAssertEqual(viewModel.pinnedSection.map(\.content).first, "banana bread")
        XCTAssertFalse(viewModel.recentSection.contains(where: { $0.id == banana.id }))
    }

    func testDragProviderForText() {
        let provider = viewModel.dragProvider(for: viewModel.orderedVisible[0])
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier("public.plain-text") || provider.hasItemConformingToTypeIdentifier("public.utf8-plain-text"))
    }
}
