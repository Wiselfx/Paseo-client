#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// General → Feedback: haptics and the mascot.
struct GeneralFeedbackSection: View {
    @AppStorage(PaseoSettingsKeys.haptics) private var haptics = true
    @AppStorage(PaseoSettingsKeys.mascot) private var mascot = true

    var body: some View {
        Section {
            ListRow(title: "Haptic feedback", systemImage: "iphone.gen3.radiowaves.left.and.right", accessory: ListRow.Accessory.toggle($haptics))
                .panelRow()
                .accessibilityIdentifier("settings.haptics")
                .onChange(of: haptics) { _, enabled in Haptics.setEnabled(enabled) }
            ListRow(title: "Show mascot", systemImage: "sparkles", accessory: ListRow.Accessory.toggle($mascot))
                .panelRow()
                .accessibilityIdentifier("settings.mascot")
        } header: {
            Text("Feedback")
        }
    }
}
#endif
