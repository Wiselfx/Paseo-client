#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The project's scripts: the list, an add button and any validation issue.
struct ProjectScriptsGroup: View {
    let scripts: [ProjectScriptDraft]
    let issue: String?
    let onAdd: () -> Void
    let onEdit: (ProjectScriptDraft) -> Void
    let onRemove: (ProjectScriptDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SettingsSectionLabel(title: "Scripts", tucksIntoGroup: false)
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.glyph(.regular, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 30, height: 30)
                        .frame(width: 44, height: 44)
                        .background(Palette.chip, in: .circle)
                }
                .padding(.trailing, Space.lg)
                .accessibilityLabel("Add script")
            }
            RowGroup {
                if scripts.isEmpty {
                    Text("No scripts. Scripts run on demand from the workspace panel.")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, 14)
                } else {
                    ForEach(scripts.enumerated(), id: \.element.id) { index, script in
                        ProjectScriptRow(
                            script: script,
                            onEdit: { onEdit(script) },
                            onRemove: { onRemove(script) }
                        )
                        if index < scripts.count - 1 { RowDivider() }
                    }
                }
            }
            if let issue {
                Text(issue)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.failureInk)
                    .padding(.leading, Space.lg)
            }
        }
    }
}
#endif
