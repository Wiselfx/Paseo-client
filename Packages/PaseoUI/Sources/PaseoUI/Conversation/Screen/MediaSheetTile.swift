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
    /// The tile's measured width in points, bucketed to 40 so a resize does not reload the
    /// thumbnail on every frame. Starts at the phone-width tile.
    @State private var tileWidth: CGFloat = 120
    @Namespace private var zoom

    nonisolated static func == (lhs: MediaSheetTile, rhs: MediaSheetTile) -> Bool {
        lhs.item == rhs.item
    }

    var body: some View {
        // Opening the viewer ticks here; the jump for every other tile is the controller's
        // `openMediaItem`, which plays its own haptic.
        Button {
            if isRemoteImage {
                showViewer = true
            } else {
                richActions?.openMediaItem(item)
            }
        } label: {
            tileContent
        }
        .buttonStyle(.plain)
        .paseoFeedback(.selection, trigger: showViewer) { _, new in new }
        .accessibilityLabel("\(item.kind.accessibilityNoun), \(item.title)")
        .onGeometryChange(for: CGFloat.self) {
            ($0.size.width / 40).rounded(.up) * 40
        } action: { width in
            if width > 0 { tileWidth = width }
        }
        .task(id: "\(thumbKey)-\(Int(tileWidth))") { await loadThumb() }
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
        // The square is the layout; the image is an overlay, so a `.fill` thumbnail that is
        // wider than the square is clipped instead of widening the tile past its column.
        Rectangle()
            .fill(Palette.codeSurface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: item.kind.glyphName)
                        .font(.glyph(.large, weight: .light))
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
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
            let pixelWidth = MediaSizing.pixelWidth(points: tileWidth, scale: displayScale)
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
