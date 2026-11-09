#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The in-conversation find bar (doc 08 / M7 §2): a search field, a live "3 of 12" counter, up/down
/// chevrons to step matches, and a close button. The bar itself is stateless; `ClaudeChatView`
/// owns the search session (`ConversationStore.search`) and the scroll target.
struct ClaudeFindBar: View {
    let typography: ClaudeTypography
    @Binding var query: String
    let isSearching: Bool
    /// Located messages, in timeline order; `currentIndex` is the one on screen.
    let resultCount: Int
    let currentIndex: Int
    let error: String?
    let onStep: (Int) -> Void
    let onCancel: () -> Void

    @FocusState.Binding var focused: Bool

    private var hasResults: Bool { resultCount > 0 }
    private var position: String {
        guard hasResults else { return "0 of 0" }
        return "\(currentIndex + 1) of \(resultCount)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(ClaudePalette.secondaryInk)
            TextField("Search in conversation", text: $query)
                .focused($focused)
                .font(typography.sans(15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onKeyPress(.escape) {
                    onCancel()
                    return .handled
                }
                .accessibilityLabel("Search in conversation")
                .accessibilityIdentifier("find.query")
            if isSearching {
                ProgressView().controlSize(.mini)
            }
            if let error, !error.isEmpty {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .accessibilityLabel("Search failed")
                    .help(error)
            } else {
                Text(position)
                    .font(typography.mono(11))
                    .monospacedDigit()
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .lineLimit(1)
                    .accessibilityLabel("Match \(currentIndex + 1) of \(resultCount)")
            }
            stepButton("chevron.up", label: "Previous match", enabled: currentIndex > 0) {
                onStep(-1)
            }
            stepButton("chevron.down", label: "Next match", enabled: currentIndex < resultCount - 1) {
                onStep(1)
            }
            Button {
                Haptics.selection()
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ClaudePalette.ink)
                    .frame(width: 30, height: 30)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close search")
            .accessibilityIdentifier("find.close")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(ClaudePalette.chip, in: .rect(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { ClaudeDivider() }
        .accessibilityIdentifier("find.bar")
    }

    @ViewBuilder private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? ClaudePalette.ink : ClaudePalette.tertiaryInk)
                .frame(width: 26, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
#endif
