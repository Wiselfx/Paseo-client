#if canImport(UIKit)
import SwiftUI

/// The date-group header, collapsible like a project row.
struct SidebarDateGroupHeader: View {
    let title: String
    let collapsed: Bool
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion), onToggle)
        } label: {
            HStack(spacing: 6) {
                ClaudeChevron(expanded: !collapsed)
                Text(title)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .padding(.bottom, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
        .paseoFeedback(.selection, trigger: collapsed)
    }
}
#endif
