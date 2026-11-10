#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The in-conversation find bar's host (doc 08 / M7 §2): a search field, a live "3 of 12"
/// counter, up/down chevrons to step matches, and a close button.
///
/// **Reads:** `store.search` (results, spinner, error), `controller.find` (query, index). The bar
/// is the only view besides the composer that reads the keyboard focus state.
struct ChatFindBarView: View {
    @Bindable var store: ConversationStore
    @Bindable var controller: ChatController

    @FocusState private var focused: Bool

    var body: some View {
        ClaudeFindBar(
            query: $controller.find.query,
            isSearching: store.search.isSearching,
            resultCount: store.search.locations.count,
            currentIndex: controller.find.index,
            error: store.search.error,
            onStep: { controller.stepFind($0) },
            onCancel: { controller.closeFind() },
            focused: $focused)
        .onAppear { focused = true }
        .onChange(of: controller.find.query) { _, query in
            controller.find.index = 0
            controller.scheduleSearch(query)
        }
        .transition(.opacity)
    }
}
#endif
