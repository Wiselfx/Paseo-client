#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

/// One pending permission request, inline in the transcript. Answers through the store; the card
/// disappears when the daemon reports the resolution, not optimistically. This view also reports
/// what it answered, so `ClaudeChatView` can keep a quiet line in place of the card afterwards
/// (the store drops resolved requests without remembering the answer).
struct ClaudePermissionCard: View {
    let request: AgentPermissionRequest
    let store: ConversationStore
    /// Fired when the user taps an answer; the focus record is that this client answered.
    let onAnswered: (AnsweredPermission) -> Void

    /// The chosen button's title while the daemon confirms: the card shows its
    /// pending state there, never a resolution line (D8 — the line appears only
    /// after the request leaves `pendingPermissions`).
    @State private var pendingTitle: String?

    private var answering: Bool { pendingTitle != nil }
    /// The optimistic quiet line is reported at most once per request: a retry after the
    /// answer timeout must not append a second line with the same id (the parent renders
    /// them in a `ForEach`, where duplicate ids are undefined behaviour).
    @State private var didReportAnswer = false

    private var isPlan: Bool { request.kind == .plan }

    var body: some View {
        Group {
            // Pi `ask_user`-style payloads parse; anything else degrades to the generic tool card.
            if let form = QuestionForm(input: request.input) {
                PermissionQuestionCard(
                    form: form, request: request, pendingTitle: pendingTitle, onAnswer: answer)
            } else if isPlan {
                PermissionPlanCard(request: request, pendingTitle: pendingTitle, onAnswer: answer)
                    .padding(Space.md)
                    .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Palette.cardBorder, lineWidth: 1)
                    }
            } else {
                PermissionToolCard(request: request, pendingTitle: pendingTitle, onAnswer: answer)
                    .padding(Space.md)
                    .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Palette.cardBorder, lineWidth: 1)
                    }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .task(id: answering) {
            guard answering else { return }
            // The answer is fire-and-forget by protocol: `agent_permission_response` carries
            // no correlated reply, so a lost frame never surfaces as an error and no
            // `agent_permission_resolved` event ever arrives. Without this timeout the card
            // would sit on its spinner with dead buttons forever. When the card is still
            // mounted after the timeout the answer never landed, so the user can answer again.
            // (HB: the timeout only re-arms the buttons; the recorded answer stays put
            // and still renders if the daemon confirms it late.)
            try? await Task.sleep(for: Self.answerTimeout)
            guard !Task.isCancelled else { return }
            pendingTitle = nil
        }
        .paseoFeedback(.selection, trigger: pendingTitle) { _, new in new != nil }
    }

    /// How long the card waits for the daemon's `agent_permission_resolved` event before it
    /// lets the user answer again. Normal confirmation is near-instant; a lost answer frame
    /// never resolves, so this is generous rather than tight.
    private static let answerTimeout: Duration = .seconds(10)

    /// The chosen button carries the pending state; the rest dim and disable.
    /// Nothing reports a resolution here (D8): the parent renders the line only
    /// after the daemon confirms (the request leaves `pendingPermissions`).
    private func answer(title: String, response: AgentPermissionResponse) {
        guard !answering else { return }
        pendingTitle = title
        let requestId = request.id
        let line = ResolutionLine.text(for: response, request: request)
        Task { await store.respond(to: requestId, with: response) }
        if !didReportAnswer {
            didReportAnswer = true
            onAnswered(AnsweredPermission(id: requestId, line: line))
        }
    }
}
#endif
