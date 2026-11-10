#if canImport(UIKit)
import PaseoStore

/// What the draft composer hands up when it is sent (D2 §3): the prompt and the attachments that
/// already finished uploading.
///
/// Creation belongs to the shell, not to the composer: the composer's identity is gone the moment
/// the shell swaps the conversation in, so nothing here waits on the network and nothing writes a
/// view's `@State` after an `await`. The composer clears its tray before it hands this over and
/// keeps the items to put back when the draft's `error` comes in (`DraftSession.create` restores
/// the text itself).
struct DraftSubmission {
    /// The trimmed prompt is not required: `DraftSession.create` decides what may be empty.
    var text: String
    var attachments: [AgentAttachment]

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }
}
#endif
