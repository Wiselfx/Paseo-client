#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A managed subagent: ordinary agent row plus the detach action. Upstream shows the action
/// cluster always on compact form factors (a phone) and on hover on desktop
/// (`subagents-track.tsx`, `actionsAlwaysVisible`), so the button is visible here; the context
/// menu carries the same action for a long press.
///
/// The row is two real buttons around the detach control (the nested button is why it was once
/// a tap gesture): the leading content and the trailing chevron both open the agent, and the
/// padding sits inside them so the whole row stays tappable.
struct ManagedSubagentRow: View {
    let agent: AgentSnapshot
    let providerLabel: String
    let canDetach: Bool
    let isDetaching: Bool
    let onOpen: (String) -> Void
    let onDetach: () -> Void

    var body: some View {
        HStack(spacing: Space.md) {
            Button {
                onOpen(agent.id)
            } label: {
                HStack(spacing: Space.md) {
                    StatusDot(status)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.paseo(.callout, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(providerLabel)
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Space.sm)
                }
                .padding(.leading, Space.lg)
                .frame(minHeight: 56)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if canDetach {
                if isDetaching {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("Detaching")
                } else {
                    Button(action: onDetach) {
                        Image(systemName: "person.badge.minus")
                            .font(.glyph(.regular, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                            .frame(width: 28, height: 28)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Detach \(title)")
                    .accessibilityIdentifier("subagents.detach")
                }
            }
            Button {
                onOpen(agent.id)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.trailing, Space.lg)
                    .frame(minHeight: 56)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The leading button already names this action; the chevron only extends its target.
            .accessibilityHidden(true)
        }
        .contextMenu {
            Button("Open agent", systemImage: "arrow.up.right.square") {
                onOpen(agent.id)
            }
            if canDetach {
                Button("Detach", systemImage: "person.badge.minus", action: onDetach)
            }
        }
    }

    private var title: String {
        let trimmed = agent.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "New agent" : trimmed
    }

    /// The same dot the panel's agent rows use: attention first, then the lifecycle status.
    private var status: StatusDot.State {
        switch agent.attention {
        case .permission: return .attention
        case .error: return .failed
        case .finished: return .unread
        case .unknown, nil: break
        }
        return switch agent.status {
        case .running: .running
        case .error: .failed
        case .initializing, .idle, .closed, .unknown: .idle
        }
    }
}
#endif
