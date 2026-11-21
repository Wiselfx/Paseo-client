#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The start/stop circle at the end of a script row. The circle stays 32 pt; the hit area is 44.
struct WorkspaceScriptActionButton: View {
    let script: WorkspaceScript
    let isBusy: Bool
    let action: () -> Void

    private var isRunning: Bool { script.lifecycle == .running }

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView().controlSize(.small).tint(Palette.ink)
                } else {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .frame(width: 32, height: 32)
            .background(Palette.chip, in: .circle)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("\(isRunning ? "Stop" : "Start") \(script.scriptName)")
    }
}
#endif
