#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The workspace's configured `paseo.json` scripts under the terminal stage.
struct WorkspaceScriptsSection: View {
    let scripts: [WorkspaceScript]
    /// Ids of the workspace's current terminals, so a row only offers "View" for one that exists.
    let terminalIds: Set<String>
    let busy: Set<String>
    let isLoading: Bool
    let onOpenService: (URL) -> Void
    let onShowTerminal: (String) -> Void
    let onToggle: (WorkspaceScript) -> Void
    let onRestart: (WorkspaceScript) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Scripts")
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: Space.sm)
                if isLoading {
                    ProgressView().controlSize(.small).tint(Palette.secondaryInk)
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(scripts) { script in
                        if script.id != scripts.first?.id { ClaudeDivider().padding(.leading, 40) }
                        WorkspaceScriptRow(
                            script: script,
                            isBusy: busy.contains(script.scriptName),
                            canShowTerminal: script.terminalId.map { terminalIds.contains($0) } ?? false,
                            onOpenService: onOpenService,
                            onShowTerminal: onShowTerminal,
                            onToggle: { onToggle(script) },
                            onRestart: { onRestart(script) })
                    }
                }
            }
            .frame(maxHeight: 168)
        }
        .padding(.bottom, Space.xs)
    }
}
#endif
