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
        // Newest first (C15): what just arrived is what the reader is looking for.
        let items = store.mediaIndex.newestFirst
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
extension ConversationMediaItem {
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
extension ConversationMediaItem.Kind {
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
