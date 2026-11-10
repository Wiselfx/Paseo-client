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


    var body: some View {
        VStack(spacing: 14) {
            SheetHeader(title: "Create pull request", close: onCancel)
            VStack(alignment: .leading, spacing: 10) {
                ClaudeCard {
                    TextField("Title", text: $title)
                        .font(.paseo(.callout, weight: .medium))
                        .textInputAutocapitalization(.sentences)
                        .focused($focused)
                }
                ClaudeCard {
                    TextEditor(text: $prBody)
                        .font(.paseo(.callout))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100, maxHeight: 160)
                        .accessibilityLabel("Pull request description")
                }
                Text("Opens from \(branch) into \(baseRef ?? "base").")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, 2)
                if let failure {
                    Text(failure)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                        .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
            Button {
                onCreate()
            } label: {
                if busy {
                    ProgressView().tint(Palette.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                } else {
                    Text("Create pull request")
                        .font(.paseo(.callout, weight: .semibold))
                        .foregroundStyle(Palette.background)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                }
            }
            .background(Palette.ink.opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1), in: .capsule)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
#endif
