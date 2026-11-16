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
    @State private var originalTitle: String?
    @State private var originalBody: String?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDirty: Bool {
        guard let originalTitle, let originalBody else { return false }
        return title != originalTitle || prBody != originalBody
    }

    var body: some View {
        SheetScaffold(
            "Create pull request",
            detents: .large,
            confirm: SheetConfirm("Create pull request", isEnabled: !trimmedTitle.isEmpty, isWorking: busy) {
                onCreate()
            },
            onClose: onCancel
        ) {
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
                    InlineBanner(.failure, title: failure)
                }
            }
            .padding(.horizontal, Space.lg)
            .frame(maxHeight: .infinity, alignment: .top)
            .sheetDirty(isDirty)
            .onAppear {
                guard originalTitle == nil else { return }
                originalTitle = title
                originalBody = prBody
            }
        }
    }
}
#endif
