#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

struct TranscriptBackgroundWork: View {
    let store: ConversationStore
    let controller: ChatController

    var body: some View {
        if store.backgroundWork.hasRunningItems {
            BackgroundWorkRow(items: store.backgroundWork.items) {
                controller.sheet = .backgroundWork
            }
        }
    }
}
#endif
