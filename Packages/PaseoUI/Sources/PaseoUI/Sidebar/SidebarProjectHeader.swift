#if canImport(UIKit)
import SwiftUI

/// What a project header asks the sidebar to do.
enum SidebarProjectHeaderAction {
    case toggleCollapsed
    case newSession
    case rename
    case openSettings
    case copyPath
    case remove
}

/// A project's collapsible header: chevron and title, a "+" for a new session, and the project
/// context menu.
struct SidebarProjectHeader: View {
    let title: String
    let collapsed: Bool
    let supportsRemove: Bool
    let onAction: (SidebarProjectHeaderAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                    onAction(.toggleCollapsed)
                }
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
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
            Button {
                onAction(.newSession)
            } label: {
                Image(systemName: "plus")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 30, height: 30)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New session in \(title)")
        }
        // A collapsed group is a 44 pt hit row at the sidebar's action-row pitch: 8 pt above,
        // nothing below (E2b §11). The workspace rows carry their own vertical padding, so the
        // first one does not crowd the header when the group expands.
        .padding(.top, Space.sm)
        .paseoFeedback(.selection, trigger: collapsed)
        .contextMenu {
            // PLAN §RH order: open-variants, edit verbs, copy, then the destructive verb.
            Button("New session", systemImage: "plus") { onAction(.newSession) }
            Button("Rename…", systemImage: "pencil") { onAction(.rename) }
            Button("Project settings…", systemImage: "gearshape") { onAction(.openSettings) }
            Button("Copy path", systemImage: "doc.on.doc") { onAction(.copyPath) }
            if supportsRemove {
                Divider()
                Button("Remove project", systemImage: "trash", role: .destructive) {
                    onAction(.remove)
                }
            }
        }
    }
}
#endif
