#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// A subagent tool call as a row card (C4 §9.4): matched to the provider subagent
/// by `toolCallId` — pi's `subagent` tool carries it on the execution event, and
/// claude's Task tool and opencode's children resolve through the same
/// `provider_subagents` list. Tapping pushes the subagent's read-only timeline
/// page (the existing `ChatSubagentTimelineView`: transcript components, no new
/// renderer). Presented as a sheet: the transcript has no NavigationStack to push
/// onto. Unmatched stays an informational row with the daemon's own description.
struct ClaudeSubagentRow: View {
    let call: ToolCall

    @Environment(\.richActions) private var richActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The mirrored match (C4 review): the daemon usually lists the subagent after
    /// the tool call row appears, so a one-shot lookup would stay blank forever.
    /// A dictionary read in body is O(1); the value changes rarely (R-1).
    private var subagent: ProviderSubagent? {
        richActions?.subagentsByCallId[call.callId]
    }

    private var subAgentType: String? {
        if case .subAgent(let type_, _, _) = call.detail { type_ } else { nil }
    }

    private var callDescription: String? {
        if case .subAgent(_, let description, _) = call.detail { description } else { nil }
    }

    private var title: String {
        if let name = subagent?.title, !name.isEmpty { return name }
        return subAgentType ?? "Subagent"
    }

    var body: some View {
        if subagent != nil {
            Button {
                Haptics.selection()
                if let subagent { richActions?.openSubagent(subagent) }
            } label: {
                card(accessory: chevron)
            }
            .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
            .accessibilityLabel("Subagent \(title)")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the subagent's timeline")
        } else {
            card(accessory: EmptyView())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Subagent \(title)")
        }
    }

    private func card<Accessory: View>(accessory: Accessory) -> some View {
        PaseoRowCard(
            glyph: "person.2", title: title, meta: callDescription,
            accessory: accessory)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.glyph(.small, weight: .semibold))
            .foregroundStyle(Palette.tertiaryInk)
            .accessibilityHidden(true)
    }
}
#endif
