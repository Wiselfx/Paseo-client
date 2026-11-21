#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

/// One answer pill on a permission card. The chosen button carries the pending state; the rest
/// dim and disable. Nothing reports a resolution here (D8): the parent renders the line only
/// after the daemon confirms (the request leaves `pendingPermissions`).
struct PermissionAnswerButton: View {
    let title: String
    let variant: AgentPermissionAction.Variant
    /// This is the button the user chose and the daemon has not yet confirmed.
    let isPending: Bool
    /// Some button on the card was chosen; every button is inert until the timeout re-arms them.
    let answering: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let filled = variant == .primary
        let danger = variant == .danger
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.paseo(.callout, weight: .medium))
                    .lineLimit(1)
                if isPending {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Waiting for confirmation")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(
                filled
                    ? Palette.background
                    : danger ? Palette.failureInk : Palette.ink)
            .background(
                filled ? Palette.ink : Palette.adaptive(light: 0.94, dark: 0.24),
                in: .capsule)
            // The pill stays 36 pt; the tap area reaches the 44 pt minimum around it.
            .frame(minHeight: Metrics.hitSize)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(answering)
        .opacity(answering && !isPending ? 0.6 : 1)
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: answering)
        .accessibilityLabel(isPending ? "\(title), waiting for confirmation" : title)
    }
}
#endif
