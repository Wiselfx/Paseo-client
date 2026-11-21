#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// M7f — the subagents track: a quiet pill under the header (provider subagents) and a sheet
/// that lists them with status; rows open the read-only timeline.

/// Counts the pill reports: the ticket's wording is `N subagents`, `N working`, `N failed`.
/// Provider rows carry no attention/needs-input signal, so there is no "needs input" mark here.
/// Managed rows are ordinary agents (`session.subagents(of:)`), so they do carry status.
struct SubagentTrackPill: View {
    let items: [ProviderSubagent]
    /// Paseo-managed child agents: ordinary agents labelled with this parent's id.
    var managed: [AgentSnapshot] = []
    let action: () -> Void

    var running: Int {
        items.count(where: { $0.status == .running }) + managed.count(where: { $0.status == .running })
    }
    var failed: Int {
        items.count(where: { $0.status == .failed }) + managed.count(where: { $0.status == .error })
    }
    var total: Int { items.count + managed.count }

    /// The working / failed counts; empty when neither applies.
    private var statusParts: [String] {
        var parts: [String] = []
        if running > 0 { parts.append("\(running) working") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts
    }

    /// "2 subagents" / "1 subagent", inflected by the system.
    private var totalLabel: Text {
        Text("^[\(total) subagent](inflect: true)")
    }

    var text: Text {
        let parts = statusParts
        return parts.isEmpty ? totalLabel : Text(parts.joined(separator: " · "))
    }

    var accessibilityText: Text {
        let parts = statusParts
        return parts.isEmpty ? totalLabel : Text(parts.formatted())
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "person.2")
                    .font(.glyph(.small, weight: .medium))
                text
                    .font(.paseo(.footnote))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .foregroundStyle(failed > 0 ? Palette.failureInk : Palette.secondaryInk)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Palette.chip, in: .capsule)
            .padding(.vertical, Space.xs)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transcript.subagents")
        .accessibilityLabel(Text("Subagents: ") + accessibilityText)
    }
}
#endif
