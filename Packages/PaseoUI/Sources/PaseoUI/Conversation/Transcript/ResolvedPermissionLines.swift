#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The daemon-confirmed resolution lines (D8), factored out of the transcript body:
/// this small view reads `pendingPermissions` and the store's answered lines,
/// so a permission change re-evaluates only this view — never the transcript (R-1).
struct ResolvedPermissionLines: View {
    @Bindable var store: ConversationStore

    var body: some View {
        let pendingIds = Set(store.pendingPermissions.map(\.id))
        let confirmed = store.permissionResolvedLines.filter { !pendingIds.contains($0.id) }
        if !confirmed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(confirmed) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.glyph(.small))
                        Text(item.line)
                            .font(.paseo(.caption))
                    }
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(item.line)
                }
            }
            .transition(.opacity)
        }
    }
}
#endif
