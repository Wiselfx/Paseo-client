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
                MediaSheetGrid(items: items.filter(\.isMedia))
            case .links:
                MediaSheetList(
                    items: items.filter { $0.kind == .link },
                    emptySymbol: "link", emptyTitle: "No links yet",
                    emptyMessage: "Links shared in this chat appear here.")
            case .files:
                MediaSheetList(
                    items: items.filter { $0.kind == .file },
                    emptySymbol: "doc", emptyTitle: "No files yet",
                    emptyMessage: "Files shared in this chat appear here.")
            }
        }
        .background(Palette.background)
        .presentationDetents([.medium, .large])
    }
}
extension ConversationMediaItem {
    /// The grid holds everything with pixels or sound: images, video, audio, diagrams
    /// and artifact snapshots. Links and files get rows.
    var isMedia: Bool {
        switch kind {
        case .image, .video, .audio, .diagram, .artifact:
            true
        case .link, .file:
            false
        }
    }
}
extension ConversationMediaItem.Kind {
    var glyphName: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .diagram: "chart.bar.doc"
        case .artifact: "square.on.square.screens"
        case .link: "link"
        case .file: "doc"
        }
    }

    var accessibilityNoun: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        case .audio: "Audio"
        case .diagram: "Diagram"
        case .artifact: "Visualization"
        case .link: "Link"
        case .file: "File"
        }
    }
}
#endif
