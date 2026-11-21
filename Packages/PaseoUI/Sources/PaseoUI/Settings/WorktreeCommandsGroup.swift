#if canImport(UIKit)
import SwiftUI

/// The worktree setup and teardown commands, saved to `paseo.json`.
struct WorktreeCommandsGroup: View {
    let hasUncommittedChanges: Bool
    @Binding var setup: String
    @Binding var teardown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSectionLabel(title: "Worktree", tucksIntoGroup: false)
            if hasUncommittedChanges {
                HStack(spacing: Space.sm) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(Palette.warning)
                    Text("This worktree setup has uncommitted changes.")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm)
            }
            RowGroup {
                ProjectConfigField(title: "Setup", text: $setup, placeholder: "npm install")
                RowDivider()
                ProjectConfigField(title: "Teardown", text: $teardown, placeholder: "docker compose down")
            }
            Text("One command per line, run in order. Saved to paseo.json on this host.")
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.tertiaryInk)
                .padding(.leading, Space.lg)
        }
    }
}
#endif
