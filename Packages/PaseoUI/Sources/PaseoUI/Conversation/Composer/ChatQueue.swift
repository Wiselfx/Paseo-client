#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

extension ClaudeChatView {
    // MARK: Queue & saved drafts (M8b)

    var isQueueNonEmpty: Bool {
        !composerQueue.queue(for: store.agentId).isEmpty
    }

    /// The quiet stack of queued messages: ink at secondary emphasis, one line each,
    /// max 3 visible then "+N more"; Edit (back into the draft) and Send now (steers).
    @ViewBuilder var queueStack: some View {
        let queue = composerQueue.queue(for: store.agentId)
        if !queue.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(queue.messages.prefix(3)) { message in
                    queuedMessageRow(message)
                }
                if queue.count > 3 {
                    Text("+\(PaseoFormat.integer(queue.count - 3)) more")
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.tertiaryInk)
                        .frame(minHeight: 24)
                        .padding(.leading, 27)
                        .accessibilityLabel("\(queue.count - 3) more queued messages")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }

    func queuedMessageRow(_ message: MessageQueue.QueuedMessage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.glyph(.small, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)
            Text(message.text)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button {
                Haptics.selection()
                editQueuedMessage(message)
            } label: {
                Image(systemName: "pencil")
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit queued message")
            Button {
                Haptics.selection()
                sendQueuedNow(message)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send queued message now")
        }
        .frame(height: 32)
        .padding(.horizontal, 14)
        .contentShape(.rect)
    }

    /// Long-press on the send button: holds the draft back until the running turn ends.
    /// Attachments make queuing non-trivial, so it is disabled while the tray is non-empty.
    func queueDraft() {
        guard trayItems.isEmpty else {
            Haptics.selection()
            showToast("Remove attachments to queue")
            return
        }
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        composerQueue.mutate(store.agentId) { _ = $0.enqueue(text) }
        store.draft = ""
        Haptics.medium()
    }

    /// A turn ended: dequeue the head and send it (steers when the next turn is already running).
    /// The in-flight send holds the `isSending` mark until it settles, so an `activeTurnId`
    /// flicker can't fire the same message twice.
    func flushQueuedMessage() {
        var next: MessageQueue.QueuedMessage?
        composerQueue.mutate(store.agentId) { next = $0.dequeueNext(isIdle: true) }
        guard let next else { return }
        // The dequeued message is sent now: same anchor contract as a manual send.
        anchoringToAnswer = true
        isFollowing = false
        Task {
            await store.send(next.text)
            composerQueue.mutate(store.agentId) { $0.finishSending() }
        }
    }

    /// Moves a queued message back into the draft (replacing it, or appending on a new line).
    func editQueuedMessage(_ message: MessageQueue.QueuedMessage) {
        var taken: String?
        composerQueue.mutate(store.agentId) { taken = $0.take(message.id) }
        guard let text = taken else { return }
        if store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.draft = text
        } else {
            store.draft += "\n" + text
        }
        focused = true
    }

    /// Immediate steer of a queued message, cutting the line.
    func sendQueuedNow(_ message: MessageQueue.QueuedMessage) {
        var taken: String?
        composerQueue.mutate(store.agentId) { taken = $0.take(message.id) }
        guard let text = taken else { return }
        Haptics.send()
        anchoringToAnswer = true
        isFollowing = false
        Task { await store.send(text) }
    }

    // MARK: Saved drafts (M8b)

    /// Restores the persisted draft when the conversation opens and the store's draft is empty.
    func seedSavedDraft() {
        guard store.draft.isEmpty else { return }
        let saved = SavedDraftStore.load(store.agentId)
        if !saved.isEmpty { store.draft = saved }
    }

    /// Debounced write of the draft (~500 ms) to UserDefaults, cleared on send.
    func scheduleDraftSave(_ value: String) {
        draftSaveTask?.cancel()
        let agentId = store.agentId
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            SavedDraftStore.save(agentId, value)
        }
    }

}
#endif
