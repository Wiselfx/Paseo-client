#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - Tiles and rows

/// One grid tile: values in, one actions object, interaction state local (R-1/R-2).
/// Remote images render their thumbnail through the pipeline; diagrams render their
/// mermaid snapshot; everything else is an identity glyph over the reserved square.
struct MediaSheetTile: View, Equatable {
    let item: ConversationMediaItem

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.richActions) private var richActions
    @Environment(\.displayScale) private var displayScale
    @State private var thumb: UIImage?
    @State private var showViewer = false
    @Namespace private var zoom

    nonisolated static func == (lhs: MediaSheetTile, rhs: MediaSheetTile) -> Bool {
        lhs.item == rhs.item
    }

    var body: some View {
        Button {
            Haptics.selection()
            if isRemoteImage {
                showViewer = true
            } else {
                richActions?.openMediaItem(item)
            }
        } label: {
            tileContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.kind.accessibilityNoun), \(item.title)")
        .task(id: thumbKey) { await loadThumb() }
        .fullScreenCover(isPresented: $showViewer) {
            if let url = remoteURL {
                MediaViewerView(
                    items: [
                        MediaViewerItem(
                            id: item.ref, thumbnail: thumb,
                            fullSource: .remote(url),
                            fileName: item.title, alt: item.title, filePath: nil)
                    ],
                    sourceID: item.ref,
                    namespace: zoom,
                    onClose: { showViewer = false },
                    selection: .constant(0))
            }
        }
    }

    /// Only remote images open the viewer: local pixels need the transcript card's
    /// daemon resolution, and players live on the card too.
    private var isRemoteImage: Bool {
        item.kind == .image && remoteURL != nil
    }

    private var remoteURL: URL? {
        guard item.kind == .image else { return nil }
        return MediaPipeline.target(for: item.ref)
    }

    private var thumbKey: String {
        "\(item.id)-\(colorScheme == .dark ? "dark" : "light")"
    }

    @ViewBuilder
    private var tileContent: some View {
        ZStack {
            Rectangle()
                .fill(Palette.codeSurface)
            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: item.kind.glyphName)
                    .font(.glyph(.large, weight: .light))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: Radius.md))
        .overlay {
            if showsPlayBadge {
                Image(systemName: "play.circle.fill")
                    .font(.glyph(.large, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
    }

    private var showsPlayBadge: Bool {
        thumb == nil && (item.kind == .video || item.kind == .audio)
    }

    private func loadThumb() async {
        if let url = remoteURL {
            let pixelWidth = MediaSizing.pixelWidth(points: 120, scale: displayScale)
            for await event in await MediaPipeline.shared.events(
                source: .remote(url), pixelWidth: pixelWidth)
            {
                guard !Task.isCancelled else { return }
                if case .final(let outcome) = event,
                    case .image(let payload) = outcome
                {
                    thumb = payload.image
                    return
                }
            }
        } else if item.kind == .diagram {
            let outcome = await RichWebSnapshotRenderer.shared.renderMermaid(
                source: item.ref, dark: colorScheme == .dark, slotWidth: 240)
            if case .diagram(let image, _, _) = outcome {
                thumb = image
            }
        }
    }
}
#endif
