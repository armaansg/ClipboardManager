import SwiftUI

/// One clipboard item. All card types share the same footprint.
struct CardView: View {
    let item: ClipItem
    let height: CGFloat

    @EnvironmentObject private var viewModel: PanelViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var globalFrame: CGRect = .zero

    private var isSelected: Bool { viewModel.selectedID == item.id }
    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(item: item, hideTrailing: isHovering)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(width: AppConfig.cardWidth, height: height)
        .background(shape.fill(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.05)))
        .background(shape.fill(isHovering ? Color.primary.opacity(0.04) : .clear))
        .overlay(
            shape.strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                               lineWidth: isSelected ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if isHovering {
                CardActions(item: item)
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            SourceAppIcon(bundleID: item.sourceBundleID, appName: item.sourceAppName)
                .padding(7)
        }
        .clipShape(shape)
        .contentShape(shape)
        .scaleEffect(isHovering ? 1.015 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onTapGesture { viewModel.select(item) }
        .onHover { hovering in
            isHovering = hovering
            if item.type == .text {
                viewModel.hoverChanged(item, isHovering: hovering, frame: globalFrame)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { globalFrame = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, frame in globalFrame = frame }
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.type.displayName): \(item.previewText)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .text: TextCardContent(item: item)
        case .image: ImageCardContent(item: item)
        case .link: LinkCardContent(item: item)
        case .file: FileCardContent(item: item)
        }
    }
}

private struct CardHeader: View {
    let item: ClipItem
    let hideTrailing: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: item.type.symbolName)
            Text(label)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !hideTrailing {
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(Color.accentColor)
                }
                Text(item.createdAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .lineLimit(1)
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(height: 14)
    }

    private var label: String {
        switch item.type {
        case .text:
            if TextHeuristics.looksLikeCode(item.previewText) { return "Code" }
            return item.isRich ? "Rich Text" : "Text"
        case .image: return "Image"
        case .link: return "Link"
        case .file:
            let count = item.filePaths.count
            return count > 1 ? "\(count) Files" : "File"
        }
    }
}

private struct CardActions: View {
    let item: ClipItem
    @EnvironmentObject private var viewModel: PanelViewModel

    var body: some View {
        HStack(spacing: 4) {
            CardActionButton(symbol: item.pinned ? "pin.fill" : "pin",
                             help: item.pinned ? "Unpin" : "Pin",
                             tint: item.pinned ? Color.accentColor : .primary) {
                viewModel.togglePin(item)
            }
            CardActionButton(symbol: "trash", help: "Delete", tint: .red) {
                viewModel.delete(item)
            }
        }
    }
}

private struct CardActionButton: View {
    let symbol: String
    let help: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct SourceAppIcon: View {
    let bundleID: String?
    let appName: String?

    var body: some View {
        if let icon = AppIconCache.shared.icon(forBundleID: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .help(appName ?? bundleID ?? "")
                .accessibilityLabel(appName.map { "Copied from \($0)" } ?? "")
        }
    }
}
