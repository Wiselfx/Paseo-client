#if canImport(UIKit)
import Foundation
import SwiftUI
import PaseoStore

/// The commit message sheet: multiline field, an all-changes footnote, and a full-width commit
/// button. Stages everything first (`git add -A` semantics), like the daemon's `addAll` default.
struct WorkspaceChangesCommitSheet: View {
    let checkout: CheckoutStore
    /// Called after a successful commit, so the page can re-subscribe its own diff view.
    var onCommitted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    @State private var message = ""
    @State private var failure: String?

    private let typography = ClaudeTypography()

    private var trimmedEmpty: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 14) {
            SheetHeader(title: "Commit", close: { dismiss() })
            VStack(alignment: .leading, spacing: 10) {
                ClaudeCard {
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Message")
                                .font(typography.sans(15))
                                .foregroundStyle(ClaudePalette.secondaryInk)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 13)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $message)
                            .font(typography.sans(15))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120, maxHeight: 180)
                            .focused($focused)
                            .accessibilityIdentifier("changes.commit.message")
                    }
                }
                Text("All current changes will be staged before committing.")
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .padding(.horizontal, 2)
                if let failure {
                    Text(failure)
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
            Button {
                Task {
                    let committed = await checkout.commit(message: message)
                    if committed {
                        Haptics.success()
                        onCommitted?()
                        dismiss()
                    } else {
                        Haptics.failure()
                        failure = checkout.actionError ?? "The commit failed."
                    }
                }
            } label: {
                if checkout.isCommitting {
                    ProgressView().tint(ClaudePalette.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                } else {
                    Text("Commit")
                        .font(typography.sans(16, weight: .semibold))
                        .foregroundStyle(ClaudePalette.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
            }
            .background(
                ClaudePalette.ink.opacity(trimmedEmpty ? 0.35 : 1), in: .capsule
            )
            .disabled(trimmedEmpty || checkout.isCommitting)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .accessibilityIdentifier("changes.commit.submit")
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .onAppear { focused = true }
    }
}
#endif
