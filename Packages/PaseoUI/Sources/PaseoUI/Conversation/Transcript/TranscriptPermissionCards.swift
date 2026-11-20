#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

struct TranscriptPermissionCards: View {
    let store: ConversationStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.pendingPermissions) { request in
                ClaudePermissionCard(request: request, store: store) { answered in
                    store.recordAnsweredPermission(answered)
                }
            }
        }
        .animation(
            Motion.disclosure.resolved(reduceMotion: reduceMotion),
            value: store.pendingPermissions.count)
    }
}
#endif
