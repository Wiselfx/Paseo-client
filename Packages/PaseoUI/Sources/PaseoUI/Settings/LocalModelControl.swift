#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The trailing control of a local speech model row: progress while it downloads or extracts,
/// Delete once installed and unused, Download or Retry otherwise. A sibling of the row's select
/// button, never inside it, so each is its own element for VoiceOver and Voice Control.
struct LocalModelControl: View {
    let model: LocalSpeechModel
    let state: LocalModelState
    let onDelete: () -> Void
    let onDownload: () -> Void

    var body: some View {
        switch state {
        case .downloading(let percent):
            HStack(spacing: Space.sm) {
                ProgressView().controlSize(.small)
                Text(percent.map { "Downloading \($0)%" } ?? "Downloading...")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
            }
        case .extracting:
            HStack(spacing: Space.sm) {
                ProgressView().controlSize(.small)
                Text("Extracting...")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
            }
        case .installed:
            if !model.inUse {
                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.paseo(.footnote, weight: .medium))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.voice.model.delete." + model.id)
            }
        case .failed, .notInstalled:
            Button {
                Haptics.light()
                onDownload()
            } label: {
                Label(isFailed ? "Retry" : "Download", systemImage: "arrow.down.circle")
                    .font(.paseo(.footnote, weight: .medium))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("settings.voice.model.download." + model.id)
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}
#endif
