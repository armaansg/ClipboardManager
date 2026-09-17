import AppKit
import SwiftUI

struct TextCardContent: View {
    let item: ClipItem

    var body: some View {
        Text(item.previewText)
            .font(TextHeuristics.looksLikeCode(item.previewText) ? .system(.caption, design: .monospaced) : .callout)
            .lineLimit(6)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct ImageCardContent: View {
    let item: ClipItem
    @EnvironmentObject private var viewModel: PanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ThumbnailView(relativePath: item.thumbPath, blobs: viewModel.blobStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var caption: String {
        var parts: [String] = []
        if let w = item.imageWidth, let h = item.imageHeight { parts.append("\(w) × \(h)") }
        parts.append(Formatters.bytes(item.byteSize))
        return parts.joined(separator: "  ·  ")
    }
}

struct ThumbnailView: View {
    let relativePath: String?
    let blobs: BlobStore
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: relativePath) {
            image = await ThumbnailCache.shared.image(for: relativePath, in: blobs)
        }
    }
}

struct LinkCardContent: View {
    let item: ClipItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "globe")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    if let title = item.title {
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(2)
                    }
                    if let host = item.url?.host {
                        Text(host)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Text(item.content)
                .font(.caption)
                .foregroundStyle(item.title == nil ? .primary : .secondary)
                .lineLimit(item.title == nil ? 5 : 3)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct FileCardContent: View {
    let item: ClipItem

    private var paths: [String] { item.filePaths }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(nsImage: FileIconCache.shared.icon(forPath: paths.first))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? "File")
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                    Text(Formatters.bytes(item.byteSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if paths.count > 1 {
                Text(paths.dropFirst().map { ($0 as NSString).lastPathComponent }.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else if let first = paths.first {
                Text((first as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
