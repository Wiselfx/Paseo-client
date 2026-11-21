#if canImport(UIKit)
import SwiftUI

/// The footer of a draft on a host with no workspace: nothing can be created yet, so the hero
/// asks for a project instead of offering a composer (§3.1).
struct DraftAddProjectAction: View {
    let onAddProject: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onAddProject) {
                Label("Add project", systemImage: "folder.badge.plus")
                    .font(.paseo(.callout, weight: .medium))
                    .foregroundStyle(Palette.background)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Palette.ink, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("draft.addProject")
        }
        .padding(.bottom, 40)
        // Top the footer up to the normal resting chrome (28 + 4 + 48 + 8 = 88): the hero must
        // not move when the host has no workspace, and `HomeHeroLayout` shares this strip with
        // the speaking draft (E2b §2).
        .padding(.bottom, Space.xs)
    }
}
#endif
