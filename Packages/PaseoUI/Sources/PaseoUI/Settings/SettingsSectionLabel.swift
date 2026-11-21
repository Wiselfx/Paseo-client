#if canImport(UIKit)
import SwiftUI

/// A group label above a `RowGroup` in the Settings sheets. The negative bottom padding pulls it
/// toward the group, so the label and group read as one block inside a roomier parent stack.
/// `ProjectSettingsView` sets `tucksIntoGroup` to false: its stack spacing already fits.
struct SettingsSectionLabel: View {
    let title: String
    var tucksIntoGroup = true

    var body: some View {
        Text(title)
            .font(.paseo(.callout))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.leading, Space.lg)
            .padding(.top, tucksIntoGroup ? Space.sm : 0)
            .padding(.bottom, tucksIntoGroup ? -Space.sm : 0)
    }
}
#endif
