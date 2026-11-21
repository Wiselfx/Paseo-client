#if canImport(UIKit)
import SwiftUI

/// "Remove project…": asks the caller to confirm. The confirmation dialog hangs off this button.
struct ProjectRemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Remove project…")
                .font(.paseo(.callout, weight: .medium))
                .foregroundStyle(Palette.failureInk)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove project")
    }
}
#endif
