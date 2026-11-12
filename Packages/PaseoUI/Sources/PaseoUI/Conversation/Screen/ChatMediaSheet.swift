#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - ChatMediaSheet (G12 C15)

// NOTE: RemoteImagePipeline/G12: "where was that screenshot?" The grid answers from the
// store's incremental index (maintained with the turns, so opening the sheet never
// walks the chat): remote-image tiles render from the pipeline, diagrams from the
// mermaid snapshot cache, everything else is an identity glyph. Tapping a remote
// image opens the shared viewer; every other tile jumps the transcript to its turn,
// where the full card (player, download, source) already lives.

/// The conversation's media, links and files: values in, jumps out (R-2). The sheet
/// reads only `store.mediaIndex` (R-1); the jump verb arrives on `RichActions`.
struct ChatMediaSheet: View {
    @Bindable var store: ConversationStore
    @Environment(\.richActions) private var richActions
    @Environment(\.dismiss) private var dismiss

    @State private var tab = MediaSheetTab.media

    var body: some View {
        let items = store.mediaIndex.items
        VStack(spacing: 0) {
            SheetHeader(title: "Media in this chat", close: { dismiss() })
            Picker("Sections", selection: $tab) {
                ForEach(MediaSheetTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
            switch tab {
            case .media:
                mediaGrid(items.filter(\.isMedia))
            case .links:
                linkRows(items.filter { $0.kind == .link })
            case .files:
                fileRows(items.filter { $0.kind == .file })
            }
        }
        .background(Palette.background)
        .presentationDetents([.medium, .large])
    }

    // MARK: Media grid

    private func mediaGrid(_ items: [ConversationMediaItem]) -> some View {
        Group {
            if items.isEmpty {
                EmptyState(
                    systemImage: "photo.on.rectangle",
                    title: "No media yet",
                    message: "Images, diagrams and recordings appear here as they arrive.")
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: Metrics.galleryTileSpacing),
                            GridItem(.flexible(), spacing: Metrics.galleryTileSpacing),
                            GridItem(.flexible(), spacing: Metrics.galleryTileSpacing),
                        ],
                        spacing: Metrics.galleryTileSpacing
                    ) {
                        ForEach(items) { item in
                            MediaSheetTile(item: item)
                        }
                    }
                    .padding(Space.lg)
                }
            }
        }
    }

    // MARK: Link and file rows

    private func linkRows(_ items: [ConversationMediaItem]) -> some View {
        Group {
            if items.isEmpty {
                EmptyState(
                    systemImage: "link",
                    title: "No links yet",
                    message: "Links shared in this chat appear here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            MediaSheetRow(item: item)
                        }
                    }
                    .padding(.vertical, Space.sm)
                }
            }
        }
    }

    private func fileRows(_ items: [ConversationMediaItem]) -> some View {
        Group {
            if items.isEmpty {
                EmptyState(
                    systemImage: "doc",
                    title: "No files yet",
                    message: "Files shared in this chat appear here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            MediaSheetRow(item: item)
                        }
                    }
                    .padding(.vertical, Space.sm)
                }
            }
        }
    }
}

/// The sheet's three sections (G12 §15: the tab names are upstream's).
private enum MediaSheetTab: String, CaseIterable, Identifiable {
    case media
    case links
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: return "Media"
        case .links: return "Links"
        case .files: return "Files"
        }
    }
}

private extension ConversationMediaItem {
    /// The grid holds everything with pixels or sound: images, video, audio, diagrams
    /// and artifact snapshots. Links and files get rows.
    var isMedia: Bool {
        switch kind {
        case .image, .video, .audio, .diagram, .artifact:
            return true
        case .link, .file:
            return false
        }
    }
}

// MARK: - Tiles and rows

/// One grid tile: values in, one actions object, interaction state local (R-1/R-2).
/// Remote images render their thumbnail through the pipeline; diagrams render their
/// mermaid snapshot; everything else is an identity glyph over the reserved square.
private struct MediaSheetTile: View, Equatable {
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
            let cap = mediaDownloadCap(
                kind: .remoteImage,
                condition: richActions?.linkCondition ?? .assumed)
            for await event in await MediaPipeline.shared.events(
                source: .remote(url), pixelWidth: pixelWidth, capBytes: cap)
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

/// One link or file row: values in, the jump verb on the actions object (R-2).
private struct MediaSheetRow: View, Equatable {
    let item: ConversationMediaItem

    @Environment(\.richActions) private var richActions

    nonisolated static func == (lhs: MediaSheetRow, rhs: MediaSheetRow) -> Bool {
        lhs.item == rhs.item
    }

    var body: some View {
        Button {
            Haptics.selection()
            richActions?.openMediaItem(item)
        } label: {
            HStack(spacing: Space.md) {
                Image(systemName: item.kind.glyphName)
                    .font(.glyph(.regular, weight: .light))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 28, alignment: .center)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.paseo(.body))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Space.sm)
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.kind.accessibilityNoun), \(item.title)")
    }

    private var subtitle: String? {
        switch item.kind {
        case .link:
            return (item.ref as NSString).lastPathComponent.isEmpty
                ? RichContentDetector.domain(for: item.ref) : (item.ref as NSString).lastPathComponent
        case .file:
            let parent = (item.ref as NSString).deletingLastPathComponent
            return (parent as NSString).lastPathComponent
        default:
            return nil
        }
    }
}

private extension ConversationMediaItem.Kind {
    var glyphName: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .diagram: return "chart.bar.doc"
        case .artifact: return "square.on.square.screens"
        case .link: return "link"
        case .file: return "doc"
        }
    }

    var accessibilityNoun: String {
        switch self {
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .diagram: return "Diagram"
        case .artifact: return "Visualization"
        case .link: return "Link"
        case .file: return "File"
        }
    }
}
#endif
