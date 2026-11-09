#if canImport(UIKit)
import SwiftUI

/// The Create-PR sheet: title/body fields prefilled from the branch and last commit, and a
/// full-width Create button. Failure text is shown inline; the parent owns the RPC.
struct WorkspaceCreatePRSheet: View {
    let branch: String
    let baseRef: String?
    @Binding var title: String
    @Binding var prBody: String
    var failure: String?
    var busy: Bool
    var onCancel: () -> Void
    var onCreate: () -> Void

    @FocusState private var focused: Bool

    private let typography = ClaudeTypography()

    var body: some View {
        VStack(spacing: 14) {
            SheetHeader(title: "Create pull request", close: onCancel)
            VStack(alignment: .leading, spacing: 10) {
                ClaudeCard {
                    TextField("Title", text: $title)
                        .font(typography.sans(16, weight: .medium))
                        .textInputAutocapitalization(.sentences)
                        .focused($focused)
                }
                ClaudeCard {
                    TextEditor(text: $prBody)
                        .font(typography.sans(14))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100, maxHeight: 160)
                        .accessibilityLabel("Pull request description")
                }
                Text("Opens from \(branch) into \(baseRef ?? "base").")
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
                onCreate()
            } label: {
                if busy {
                    ProgressView().tint(ClaudePalette.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                } else {
                    Text("Create pull request")
                        .font(typography.sans(15, weight: .semibold))
                        .foregroundStyle(ClaudePalette.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
            }
            .background(ClaudePalette.ink.opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1), in: .capsule)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
    }
}
#endif
