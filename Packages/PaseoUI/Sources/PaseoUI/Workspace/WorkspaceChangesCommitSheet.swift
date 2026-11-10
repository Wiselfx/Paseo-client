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

    private var trimmedEmpty: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SheetScaffold(
            "Commit",
            detents: .mediumLarge,
            confirm: SheetConfirm(
                "Commit", isEnabled: !trimmedEmpty, isWorking: checkout.isCommitting,
                identifier: "changes.commit.submit"
            ) {
                Task { await commit() }
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ClaudeCard {
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Message")
                                .font(.paseo(.callout))
                                .foregroundStyle(Palette.secondaryInk)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 13)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $message)
                            .font(.paseo(.callout))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120, maxHeight: 180)
                            .focused($focused)
                            .accessibilityIdentifier("changes.commit.message")
                    }
                }
                Text("All current changes will be staged before committing.")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, 2)
                if let failure {
                    InlineBanner(.failure, title: failure)
                }
            }
            .padding(.horizontal, Space.lg)
            .frame(maxHeight: .infinity, alignment: .top)
            .sheetDirty(!trimmedEmpty)
            .onAppear { focused = true }
        }
    }

    private func commit() async {
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
}
#endif
