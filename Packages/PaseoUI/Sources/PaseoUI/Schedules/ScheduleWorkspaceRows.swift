#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The editor's Target workspace rows: one per workspace, the chosen one checked, plus a row for
/// a stored directory that no longer matches any workspace.
struct ScheduleWorkspaceRows: View {
    let workspaces: [WorkspaceDescriptor]
    @Binding var cwd: String

    var body: some View {
        ForEach(workspaces) { workspace in
            ListRow(
                title: workspace.title ?? workspace.name,
                subtitle:
                    "\(workspace.projectDisplayName)\(workspace.branch.map { " · \($0)" } ?? "")",
                accessory: ListRow.Accessory.checkmark(cwd == workspace.cwd),
                action: {
                    cwd = workspace.cwd
                }
            )
            .panelRow()
        }
        .paseoFeedback(.selection, trigger: cwd)
        if !cwd.isEmpty, !workspaces.contains(where: { $0.cwd == cwd }) {
            ListRow(title: "Custom directory", subtitle: cwd)
                .panelRow()
        }
    }
}
#endif
