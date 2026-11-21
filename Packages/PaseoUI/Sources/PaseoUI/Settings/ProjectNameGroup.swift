#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The project's name row: tap to rename, and Reset once a custom name is set.
struct ProjectNameGroup: View {
    let session: HostSession
    let project: WorkspaceProjectDescriptor
    let onRename: () -> Void

    private var title: String {
        project.projectCustomName ?? project.projectDisplayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSectionLabel(title: "Name", tucksIntoGroup: false)
            RowGroup {
                HStack(spacing: 14) {
                    Button(action: onRename) {
                        HStack(spacing: 14) {
                            Text(title)
                                .font(.paseo(.body))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer(minLength: Space.sm)
                            if project.projectCustomName == nil {
                                Image(systemName: "chevron.right")
                                    .font(.glyph(.regular))
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 51)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rename project")
                    if project.projectCustomName != nil {
                        Button {
                            Task {
                                let ok = await session.workspaceDirectory.renameProject(
                                    project.projectId, to: nil)
                                if ok { Haptics.success() } else { Haptics.failure() }
                            }
                        } label: {
                            ProjectChip(horizontalPadding: Space.md, visibleHeight: 30) {
                                Text("Reset")
                                    .font(.paseo(.footnote, weight: .medium))
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reset to the folder name")
                    }
                }
                .padding(.horizontal, Space.lg)
            }
        }
    }
}
#endif
