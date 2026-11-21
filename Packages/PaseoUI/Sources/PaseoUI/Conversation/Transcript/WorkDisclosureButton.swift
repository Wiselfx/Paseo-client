#if canImport(UIKit)
import SwiftUI

/// The button that opens and folds a work step. Its spoken label stands in for the visible content,
/// so whatever that content shows beyond the label (an outcome, a diff stat) is passed as
/// `accessibilityDetails` and read after "Expanded" or "Collapsed". A second button on the same
/// row can `hidesFromVoiceOver` so the step is not announced twice.
struct WorkDisclosureButton<Label: View>: View {
    let isExpanded: Bool
    let accessibilityLabel: String
    var accessibilityDetails: [String] = []
    var hidesFromVoiceOver = false
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(
            ([isExpanded ? "Expanded" : "Collapsed"] + accessibilityDetails).joined(separator: ", ")
        )
        .accessibilityHidden(hidesFromVoiceOver)
    }
}
#endif
