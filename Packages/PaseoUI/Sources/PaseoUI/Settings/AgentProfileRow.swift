#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One saved agent profile: name, a provider/model/mode/thinking summary, optional notes and the
/// move, edit and delete controls. The summary is resolved here from the catalogue, so only a
/// row whose inputs changed re-runs those lookups.
struct AgentProfileRow: View {
    let profile: AgentProfile
    let catalog: AgentControlStore
    let isFirst: Bool
    let isLast: Bool
    let onMove: (Int) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.sm) {
                    Text(profile.name)
                        .font(.paseo(.body))
                        .lineLimit(1)
                        .accessibilityIdentifier("settings.profiles.name.\(profile.id)")
                    Text(summary)
                        .font(.paseo(.codeCaption))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let notes = profile.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, 9)
        .frame(minHeight: 56)
    }

    private var actions: some View {
        HStack(spacing: 0) {
            moveButton(offset: -1, isDisabled: isFirst)
            moveButton(offset: 1, isDisabled: isLast)
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.glyph(.regular, weight: .light))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(profile.name)")
            .accessibilityIdentifier("settings.profiles.edit.\(profile.id)")
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.glyph(.regular, weight: .light))
                    .foregroundStyle(Palette.failureInk)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(profile.name)")
            .accessibilityIdentifier("settings.profiles.delete.\(profile.id)")
        }
    }

    private func moveButton(offset: Int, isDisabled: Bool) -> some View {
        Button {
            Haptics.light()
            onMove(offset)
        } label: {
            Image(systemName: offset < 0 ? "chevron.up" : "chevron.down")
                .font(.glyph(.regular, weight: .regular))
                .foregroundStyle(isDisabled ? Palette.tertiaryInk.opacity(0.4) : Palette.tertiaryInk)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(offset < 0 ? "Move \(profile.name) up" : "Move \(profile.name) down")
        .accessibilityIdentifier("settings.profiles.move.\(offset < 0 ? "up" : "down").\(profile.id)")
    }

    // MARK: Summary line

    private var summary: String {
        var parts = [profile.provider]
        if let model = profile.model, !model.isEmpty {
            parts.append(modelName(model))
        }
        if let modeId = profile.modeId, !modeId.isEmpty,
            let mode = modeLabel(modeId) {
            parts.append(mode)
        }
        if let thinkingId = profile.thinkingOptionId, !thinkingId.isEmpty {
            parts.append(thinkingLabel(optionId: thinkingId))
        }
        return parts.joined(separator: " · ")
    }

    private func modelName(_ modelID: String) -> String {
        catalog.models(forProvider: profile.provider).first { $0.id == modelID }?.label ?? modelID
    }

    private func modeLabel(_ modeId: String) -> String? {
        catalog.modes(forProvider: profile.provider).first { $0.id == modeId }?.label ?? modeId
    }

    private func thinkingLabel(optionId: String) -> String {
        let effectiveModel = profile.model ?? catalog.defaultModel(forProvider: profile.provider)?.id
        let options = effectiveModel.map {
            catalog.thinkingOptions(forProvider: profile.provider, modelId: $0)
        } ?? []
        return options.first { $0.id == optionId }?.label ?? optionId
    }
}
#endif
