#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One local speech model: the select button (name, size, status chips) with the download or
/// delete control beside it, then any error. The control is a sibling of the select button, not
/// nested in its label, so VoiceOver and Voice Control can reach both.
struct LocalSpeechModelRow: View {
    let model: LocalSpeechModel
    let selected: Bool
    let state: LocalModelState
    let actionError: String?
    /// "Set by …" for the model field, shown on the selected row only.
    let setByHint: String?
    let isReadOnly: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.md) {
                Button {
                    Haptics.selection()
                    if !isReadOnly { onSelect() }
                } label: {
                    info
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isReadOnly)
                .accessibilityIdentifier("settings.voice.model." + model.id)
                .accessibilityAddTraits(selected ? .isSelected : [])
                LocalModelControl(model: model, state: state, onDelete: onDelete, onDownload: onDownload)
                    .disabled(isReadOnly)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.glyph(.large, weight: .semibold))
                        .foregroundStyle(Palette.selection)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Space.lg)

            if let rowError {
                Text(rowError)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.failureInk)
                    .padding(.leading, Space.xxxl)
            }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Text(model.label)
                    .font(.paseo(.body))
                    .lineLimit(1)
                if model.isDefault {
                    Text("Recommended")
                        .font(.paseo(.caption2, weight: .semibold))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 5)
                        .background(Palette.chip, in: .capsule)
                }
            }
            Text(formatModelSize(bytes: model.downloadSizeBytes))
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
            if state == .installed {
                Text(model.inUse ? "In use" : "Downloaded")
                    .font(.paseo(.caption2, weight: .semibold))
                    .foregroundStyle(Palette.successInk)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, 5)
                    .background(Palette.chip, in: .capsule)
            }
            if selected, let setByHint {
                Text(setByHint)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    private var rowError: String? {
        if let actionError { return actionError }
        if case .failed(let error) = state, !error.isEmpty { return error }
        return nil
    }
}
#endif
