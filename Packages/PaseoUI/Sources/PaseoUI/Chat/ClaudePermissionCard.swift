#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// A pending permission request, inline in the transcript. Answers through the store; the card
/// disappears when the daemon reports the resolution, not optimistically.
struct ClaudePermissionCard: View {
    let request: AgentPermissionRequest
    let store: ConversationStore
    @State private var answering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPlan: Bool { request.kind == .plan }

    private var title: String {
        if let title = request.title, !title.isEmpty { return title }
        return isPlan ? "Plan" : request.name
    }

    private var actions: [AgentPermissionAction] { request.actions ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                VStack(alignment: .leading, spacing: 2) {
                    if isPlan {
                        Text("Permission Required")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                            .textCase(.uppercase)
                    }
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ClaudePalette.ink)
                }
                Spacer(minLength: 0)
                if answering { ProgressView().controlSize(.mini) }
            }
            if let description = request.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let input = request.input {
                ClaudeCodeBlock(output: ClaudeToolCallDetail.describe(input), maxHeight: 180)
            }
            HStack(spacing: 8) {
                if actions.isEmpty {
                    answerButton(
                        title: "Deny", behavior: .deny, variant: .secondary,
                        response: .denying())
                    answerButton(
                        title: "Accept", behavior: .allow, variant: .primary,
                        response: .allowing())
                } else {
                    ForEach(actions) { action in
                        answerButton(
                            title: action.label, behavior: action.behavior,
                            variant: action.variant ?? (action.behavior == .deny ? .secondary : .primary),
                            response: response(for: action))
                    }
                }
            }
        }
        .padding(14)
        .background(ClaudePalette.panel, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var symbol: String {
        switch request.kind {
        case .plan: "list.bullet.clipboard"
        case .question: "questionmark.bubble"
        case .mode: "slider.horizontal.3"
        case .tool: "hand.raised"
        case .other, .unknown: "lock.shield"
        }
    }

    private func response(for action: AgentPermissionAction) -> AgentPermissionResponse {
        switch action.behavior {
        case .allow: .allowing(selectedActionId: action.id)
        case .deny: .denying(selectedActionId: action.id)
        case .unknown: .denying(selectedActionId: action.id)
        }
    }

    private func answerButton(
        title: String, behavior: AgentPermissionAction.Behavior, variant: AgentPermissionAction.Variant,
        response: AgentPermissionResponse
    ) -> some View {
        let filled = variant == .primary
        let danger = variant == .danger
        return Button {
            guard !answering else { return }
            answering = true
            Haptics.selection()
            let requestId = request.id
            Task { await store.respond(to: requestId, with: response) }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .foregroundStyle(
                    filled
                        ? ClaudePalette.background
                        : danger ? ClaudePalette.failureInk : ClaudePalette.ink
                )
                .background(
                    filled ? ClaudePalette.ink : ClaudePalette.adaptive(light: 0.94, dark: 0.24),
                    in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(answering)
        .opacity(answering ? 0.6 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.feedback), value: answering)
        .accessibilityLabel(title)
    }
}
#endif
