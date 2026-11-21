#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

/// A proposed plan awaiting Approve or Reject. The parent supplies the card chrome and owns the
/// pending state.
struct PermissionPlanCard: View {
    let request: AgentPermissionRequest
    /// The chosen button's title while the daemon confirms.
    let pendingTitle: String?
    /// Reports the chosen answer to the parent, which sends it.
    let onAnswer: (String, AgentPermissionResponse) -> Void

    private var answering: Bool { pendingTitle != nil }

    private var planText: String {
        if let metadata = request.metadata, let text = metadata["planText"]?.stringValue,
           !text.isEmpty {
            return text
        }
        if let input = request.input, let text = input["plan"]?.stringValue,
           !text.isEmpty {
            return text
        }
        return request.description ?? "The agent proposed a plan."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                Text("Proposed plan")
                    .font(.paseo(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                if answering { ProgressView().controlSize(.mini) }
            }
            Text(planText)
                .font(.paseo(.processTitle))
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let description = request.description, !description.isEmpty {
                Text(description)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
            }
            HStack(spacing: 8) {
                PermissionAnswerButton(
                    title: "Reject", variant: .secondary,
                    isPending: pendingTitle == "Reject", answering: answering
                ) {
                    onAnswer("Reject", .denying())
                }
                PermissionAnswerButton(
                    title: "Approve", variant: .primary,
                    isPending: pendingTitle == "Approve", answering: answering
                ) {
                    onAnswer("Approve", .allowing())
                }
            }
        }
    }
}
#endif
