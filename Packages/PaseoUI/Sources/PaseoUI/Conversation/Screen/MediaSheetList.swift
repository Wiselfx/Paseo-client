#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The links and files tabs: one row per item, or the tab's own empty state.
struct MediaSheetList: View {
    let items: [ConversationMediaItem]
    let emptySymbol: String
    let emptyTitle: String
    let emptyMessage: String

    var body: some View {
        if items.isEmpty {
            EmptyState(systemImage: emptySymbol, title: emptyTitle, message: emptyMessage)
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
#endif
