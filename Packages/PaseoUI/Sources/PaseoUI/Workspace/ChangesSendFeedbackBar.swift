#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// "Send feedback (N)": sends the displayed diff's review drafts to a workspace agent (the open
/// chat's by default), and offers to clear drafts that no longer match the diff. Renders nothing
/// without drafts.
struct ChangesSendFeedbackBar: View {
    let session: HostSession
    let checkout: CheckoutStore
    let extras: WorkspaceGitExtras
    /// The open chat's agent, the default recipient.
    let agentId: String?
    let reviewKey: WorkspaceReviewDraftKey
    let compare: ChangesCompare
    let baseRef: String?

    @Environment(\.toast) private var toast
    @State private var feedbackError: String?

    var body: some View {
        let draftCount = WorkspaceReviewDrafts.shared.count(for: reviewKey)
        if draftCount > 0 {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: 10) {
                    if let defaultRecipient {
                        sendButton(to: defaultRecipient, draftCount: draftCount)
                    } else {
                        Text("Open an agent in this workspace to send feedback.")
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    if let feedbackError {
                        Text(feedbackError)
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.failureInk)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 2)
                // One `buildAll` per evaluation: the stale set feeds the text, the label and Clear.
                let stale = staleDrafts
                if !stale.isEmpty {
                    HStack(spacing: 6) {
                        Text("^[\(stale.count) comment](inflect: true) no longer matching this diff")
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                        Button("Clear") {
                            Haptics.light()
                            for draft in stale {
                                WorkspaceReviewDrafts.shared.delete(key: reviewKey, id: draft.id)
                            }
                        }
                        .font(.paseo(.caption, weight: .medium))
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear stale comments")
                        .accessibilityIdentifier("changes.staleDrafts.clear")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        Text("^[\(stale.count) comment](inflect: true) no longer matching this diff"))
                }
            }
        }
    }

    private func sendButton(to defaultRecipient: AgentSnapshot, draftCount: Int) -> some View {
        HStack(spacing: 0) {
            Button {
                Task { await sendFeedback(to: defaultRecipient) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane")
                        .font(.glyph(.small, weight: .medium))
                    Text("Send feedback (\(PaseoFormat.integer(draftCount)))")
                        .font(.paseo(.footnote, weight: .semibold))
                }
                .foregroundStyle(Palette.background)
                .padding(.leading, 14)
                .padding(.trailing, Space.md)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text(
                    "Send feedback to \(agentTitle(defaultRecipient)), ^[\(draftCount) comment](inflect: true)"
                ))
            if recipients.count > 1 {
                Menu {
                    ForEach(recipients) { agent in
                        Button {
                            Task { await sendFeedback(to: agent) }
                        } label: {
                            if agent.id == agentId {
                                Label("\(agentTitle(agent)) (this chat)", systemImage: "checkmark")
                            } else {
                                Text(agentTitle(agent))
                            }
                        }
                    }
                } label: {
                    Label("Choose an agent to send feedback", systemImage: "chevron.down")
                        .labelStyle(.iconOnly)
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.background)
                        .padding(.trailing, 10)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
            }
        }
        .background(Palette.ink, in: .capsule)
    }

    /// The agents in this workspace; the open chat's agent is the default recipient.
    private var recipients: [AgentSnapshot] {
        session.agents.filter { $0.workspaceId == checkout.workspaceId }
    }

    private var defaultRecipient: AgentSnapshot? {
        let all = recipients
        if let agentId, let current = all.first(where: { $0.id == agentId }) { return current }
        return all.first
    }

    /// Drafts whose anchor is gone from the current diff (M3k follow-up): invisible in the
    /// diff, skipped by the attachment builder. Only meaningful once the diff is ready —
    /// before that, an empty file list would make every draft look stale.
    private var staleDrafts: [WorkspaceReviewDraftComment] {
        guard extras.diffPhase == .ready else { return [] }
        let scoped = WorkspaceReviewDrafts.shared.comments(for: reviewKey)
        guard !scoped.isEmpty else { return [] }
        let built = WorkspaceReviewAttachmentBuilder.buildAll(
            comments: scoped, files: extras.files, cwd: checkout.cwd,
            mode: compare.mode, baseRef: baseRef)
        let sentIds = Set((built?.1 ?? []).map(\.id))
        return scoped.filter { !sentIds.contains($0.id) }
    }

    private func agentTitle(_ agent: AgentSnapshot) -> String {
        let title = agent.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.map { $0.isEmpty ? "Agent" : $0 } ?? "Agent"
    }

    /// Sends the current diff's drafts as one `review` attachment on one prompt. Drafts that were
    /// attached are cleared only when the daemon accepts the message.
    private func sendFeedback(to agent: AgentSnapshot) async {
        feedbackError = nil
        let scoped = WorkspaceReviewDrafts.shared.comments(for: reviewKey)
        guard !scoped.isEmpty else { return }
        guard let (attachment, sent) = WorkspaceReviewAttachmentBuilder.buildAll(
            comments: scoped, files: extras.files, cwd: checkout.cwd,
            mode: compare.mode, baseRef: baseRef)
        else {
            feedbackError = "Saved comments no longer match this diff."
            Haptics.failure()
            return
        }
        let conversation = session.conversation(for: agent.id)
        await conversation.sendWithAttachments(
            "Please address this code review.",
            attachments: [.review(attachment)])
        if let error = conversation.actionError {
            feedbackError = error
            Haptics.failure()
            return
        }
        WorkspaceReviewDrafts.shared.clearSent(key: reviewKey, comments: sent)
        feedbackError = nil
        Haptics.success()
        toast?.show("Feedback sent to \(agentTitle(agent))")
    }
}
#endif
