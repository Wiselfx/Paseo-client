#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The media tab: a three-column grid of tiles, or the empty state.
struct MediaSheetGrid: View {
    let items: [ConversationMediaItem]

    var body: some View {
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
#endif
