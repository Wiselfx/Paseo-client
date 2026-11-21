#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

/// The generic permission request: title, description, a preview of what is being requested,
/// and the daemon's answer buttons (or Deny/Accept when it names none). The parent supplies the
/// card chrome and owns the pending state.
struct PermissionToolCard: View {
    let request: AgentPermissionRequest
    /// The chosen button's title while the daemon confirms.
    let pendingTitle: String?
    /// Reports the chosen answer to the parent, which sends it.
    let onAnswer: (String, AgentPermissionResponse) -> Void

    private var answering: Bool { pendingTitle != nil }

    private var title: String {
        if let title = request.title, !title.isEmpty { return title }
        if request.kind == .question { return "How would you like to proceed?" }
        return request.kind == .plan ? "Proposed plan" : request.name
    }

    private struct ActionSpec: Identifiable {
        /// The daemon's action id; fixed ids for the default pair. Titles can repeat, ids cannot.
        let id: String
        var title: String
        var variant: AgentPermissionAction.Variant
        var response: AgentPermissionResponse
    }

    private var actionButtons: [ActionSpec] {
        if let actions = request.actions, !actions.isEmpty {
            return actions.map { action in
                ActionSpec(
                    id: action.id,
                    title: action.label,
                    variant: action.variant ?? (action.behavior == .deny ? .secondary : .primary),
                    response: response(for: action))
            }
        }
        return [
            ActionSpec(id: "deny", title: "Deny", variant: .secondary, response: .denying()),
            ActionSpec(id: "accept", title: "Accept", variant: .primary, response: .allowing()),
        ]
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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.glyph(.small, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            Text(title)
                .font(.paseo(.callout, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if answering { ProgressView().controlSize(.mini) }
        }
        if let description = request.description, !description.isEmpty {
            Text(description)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        PermissionRequestPreview(detail: request.detail, input: request.input)
        HStack(spacing: 8) {
            ForEach(actionButtons) { spec in
                PermissionAnswerButton(
                    title: spec.title, variant: spec.variant,
                    isPending: pendingTitle == spec.title, answering: answering
                ) {
                    onAnswer(spec.title, spec.response)
                }
            }
        }
    }
}
#endif
