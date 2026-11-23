#if canImport(UIKit)
import SwiftUI
import UIKit

/// A card's source view: the code in a capped, selectable scroll view and a Copy source button.
/// Copy goes through `RichActions` when the transcript provided it, else straight to the
/// pasteboard.
struct RichSourcePanel: View {
    let code: String
    /// The code's text role: `.codeCaption` for the web and SVG cards, `.codeSmall` for diagrams.
    var role: TextRole = .codeCaption

    @Environment(\.richActions) private var richActions
    @Environment(\.toast) private var toast
    /// Bumped on a pasteboard copy (no `RichActions`): the copy haptic, once per tap.
    @State private var copyTaps = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ScrollView {
                // Wrapping (not clipping) is the source view's contract: a long line must
                // never disappear at the card's right edge.
                Text(code)
                    .font(.paseo(role))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Metrics.sourcePreviewMaxHeight)
            HStack {
                Spacer(minLength: 0)
                Button(action: copySource) {
                    Label("Copy source", systemImage: "doc.on.doc")
                        .font(.paseo(.caption, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(minHeight: Metrics.hitSize)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .paseoFeedback(.light, trigger: copyTaps)
    }

    private func copySource() {
        if let richActions {
            richActions.copyText(code)
        } else {
            UIPasteboard.general.string = code
            copyTaps += 1
        }
        toast?.show("Source copied", systemImage: "checkmark")
    }
}
#endif
