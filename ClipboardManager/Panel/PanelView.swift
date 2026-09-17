import SwiftUI

/// Root SwiftUI content of the clipboard panel: header with search and filter, then the horizontal card row.
struct PanelView: View {
    @EnvironmentObject private var viewModel: PanelViewModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: AppConfig.panelCornerRadius, bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0, topTrailingRadius: AppConfig.panelCornerRadius,
                               style: .continuous)
    }

    var body: some View {
        VStack(spacing: 6) {
            header
            cardRow
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            // Subtle 1px inner highlight along the glass edge.
            panelShape
                .strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(colorScheme == .dark ? 0.28 : 0.6),
                                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.25)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
                .allowsHitTesting(false)
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.secondary)
            Text("Clipboard")
                .font(.headline)
            Text(countLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            SearchPill(text: viewModel.searchText, onClear: { viewModel.clearSearch() })
            Spacer(minLength: 8)
            FilterMenu(selection: $viewModel.filter)
        }
        .frame(height: 26)
    }

    private var countLabel: String {
        let count = viewModel.orderedVisible.count
        return count == 1 ? "1 item" : "\(count) items"
    }

    private var cardRow: some View {
        GeometryReader { geometry in
            let pinned = viewModel.pinnedSection
            let recent = viewModel.recentSection
            if pinned.isEmpty && recent.isEmpty {
                emptyState
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(pinned) { item in
                                CardView(item: item, height: geometry.size.height, quickIndex: viewModel.quickIndex(for: item))
                                    .id(item.id)
                            }
                            if !pinned.isEmpty && !recent.isEmpty {
                                SectionDivider(height: geometry.size.height)
                            }
                            ForEach(recent) { item in
                                CardView(item: item, height: geometry.size.height, quickIndex: viewModel.quickIndex(for: item))
                                    .id(item.id)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .onChange(of: viewModel.selectedID) { _, newValue in
                        guard let newValue else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(newValue, anchor: nil)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: viewModel.isSearching ? "magnifyingglass" : (viewModel.filter == .all ? "clipboard" : viewModel.filter.symbolName))
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(emptyHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var emptyTitle: String {
        if viewModel.isSearching { return "No results for “\(viewModel.searchText)”" }
        if viewModel.filter != .all { return "No \(viewModel.filter.rawValue.lowercased()) in history" }
        return "Nothing copied yet"
    }

    private var emptyHint: String {
        if viewModel.isSearching { return "Press Delete to edit the search or Esc to clear it." }
        return "Items you copy will appear here. Press \(settings.hotKey.displayString) to toggle this panel, type to search, ⌘1–9 to grab a card."
    }
}

/// Shows the live type-to-search query. There is no text field: keystrokes are routed by the panel.
struct SearchPill: View {
    let text: String
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            if text.isEmpty {
                Text("Type to search")
                    .foregroundStyle(.tertiary)
            } else {
                Text(text)
                    .lineLimit(1)
                    .truncationMode(.head)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 1.5, height: 14)
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search (Esc)")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(minWidth: 180, maxWidth: 360)
        .background(Capsule().fill(Color.primary.opacity(text.isEmpty ? 0.05 : 0.1)))
        .overlay(Capsule().strokeBorder(text.isEmpty ? Color.primary.opacity(0.1) : Color.accentColor.opacity(0.6), lineWidth: 1))
        .animation(.easeOut(duration: 0.12), value: text.isEmpty)
    }
}

struct FilterMenu: View {
    @Binding var selection: FilterKind

    var body: some View {
        Menu {
            Picker("Filter", selection: $selection) {
                ForEach(FilterKind.allCases) { kind in
                    Label(kind.rawValue, systemImage: kind.symbolName).tag(kind)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(selection == .all ? "Filter" : selection.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                .font(.subheadline.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Show only one kind of item")
    }
}

struct SectionDivider: View {
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 1, height: max(0, height - 24))
            .frame(height: height)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }
}
