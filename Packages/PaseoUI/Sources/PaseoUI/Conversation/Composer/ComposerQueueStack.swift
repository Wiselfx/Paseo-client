#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The queued messages above the card: the first three, and a count of the rest. Reads the queue
/// itself, so the composer's body does not.
struct ComposerQueueStack: View {
    let controller: ChatController
    @Binding var focused: Bool

    var body: some View {
        let queue = controller.composerQueue.queue(for: controller.store.agentId)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(queue.messages.prefix(3)) { message in
                QueueRow(
                    message: message,
                    onEdit: {
                        if controller.editQueuedMessage(message) { focused = true }
                    },
                    onSendNow: { controller.sendQueuedNow(message) })
            }
            if queue.count > 3 {
                Text("+\(PaseoFormat.integer(queue.count - 3)) more")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(minHeight: 24)
                    .padding(.leading, 27)
                    .accessibilityLabel(Text("^[\(queue.count - 3) more queued message](inflect: true)"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .padding(.bottom, 6)
    }
}
#endif
