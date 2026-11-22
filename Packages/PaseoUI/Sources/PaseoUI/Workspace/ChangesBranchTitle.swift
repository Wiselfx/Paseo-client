#if canImport(UIKit)
import SwiftUI

/// The branch name, tapping which opens the switcher (upstream `BranchSwitcher`'s trigger,
/// `branch-switcher.tsx`). Only the name is the button: the PR chip beside it is its own button.
/// A detached HEAD has no branch to switch to and stays a plain label.
struct ChangesBranchTitle: View {
    let label: String
    let canSwitch: Bool
    let onSwitch: () -> Void

    var body: some View {
        if canSwitch {
            Button(action: onSwitch) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.paseo(.code, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Current branch: \(label). Press to switch branch.")
            .accessibilityIdentifier("changes.branchSwitcher")
        } else {
            Text(label)
                .font(.paseo(.code, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
    }
}
#endif
