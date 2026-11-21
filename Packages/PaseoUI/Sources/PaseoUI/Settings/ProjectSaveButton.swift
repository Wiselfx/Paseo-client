#if canImport(UIKit)
import SwiftUI

/// The primary action of the project page. Disabling it is the caller's `.disabled`, which the
/// button style reads from the environment.
struct ProjectSaveButton: View {
    let isSaving: Bool
    let savedPulse: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(savedPulse ? "Saved" : "Save changes")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.paseoPrimary(isWorking: isSaving))
        .accessibilityLabel("Save project settings")
    }
}
#endif
