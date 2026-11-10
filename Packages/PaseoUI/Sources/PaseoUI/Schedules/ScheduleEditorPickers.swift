#if canImport(UIKit)
import PaseoStore
import SwiftUI

// MARK: - Pickers

extension ScheduleEditorPage {
    /// Every picker page: a back row and a list of rows. One shape for provider/model/mode/thinking/workspace.
    @ViewBuilder internal func pickerView(_ which: Picker) -> some View {
        switch which {
        case .provider: providerPicker
        case .model: modelPicker
        case .mode: modePicker
        case .thinking: thinkingPicker
        case .workspace: workspacePicker
        }
    }

    internal func pickerShell<Content: View>(
        title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.paseo(.title, weight: .semibold))
                HStack {
                    Button {
                        Haptics.selection()
                        picker = nil
                    } label: {
                        Image(systemName: "chevron.left").font(.glyph(.large, weight: .light))
                            .frame(width: 42, height: 42)
                    }
                    .glassEffect(in: .circle)
                    .accessibilityLabel("Back")
                    Spacer()
                }
            }
            .frame(height: 56)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            content()
        }
    }

    internal func pickerRow(
        title: String, detail: String? = nil, checked: Bool, badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.paseo(.callout))
                        if let badge {
                            Text(badge)
                                .font(.paseo(.caption2, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Palette.ink.opacity(0.06), in: .capsule)
                        }
                    }
                    if let detail {
                        Text(detail)
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.glyph(.regular, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    internal var providerPicker: some View {
        pickerShell(title: "Provider") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if catalog.readyProviders.isEmpty {
                        Text("No providers are ready on this host.")
                            .font(.paseo(.footnote))
                            .foregroundStyle(Palette.secondaryInk)
                            .padding(16)
                    } else {
                        RowGroup {
                            ForEach(Array(catalog.readyProviders.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { RowDivider() }
                                pickerRow(
                                    title: entry.label ?? entry.provider,
                                    detail: entry.description,
                                    checked: providerId == entry.provider
                                ) {
                                    providerId = entry.provider
                                    modelId = ""
                                    modeId = ""
                                    thinkingId = ""
                                    picker = nil
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                }
            }
            .onAppear {
                Task { await catalog.loadCatalog(cwd: nil) }
            }
        }
    }

    internal var modelPicker: some View {
        pickerShell(title: "Model") {
            let models = catalog.models(forProvider: providerId)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    RowGroup {
                        pickerRow(title: "Provider default", checked: modelId.isEmpty) {
                            modelId = ""
                            picker = nil
                        }
                        ForEach(Array(models.enumerated()), id: \.element.id) { _, model in
                            RowDivider()
                            pickerRow(
                                title: model.label,
                                detail: model.description,
                                checked: modelId == model.id,
                                badge: model.isDefault == true ? "Default" : nil
                            ) {
                                modelId = model.id
                                thinkingId = ""
                                picker = nil
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    if models.isEmpty {
                        Text(providerId.isEmpty ? "Choose a provider first." : "This provider reports no models.")
                            .font(.paseo(.footnote))
                            .foregroundStyle(Palette.secondaryInk)
                            .padding(16)
                    }
                }
            }
        }
    }

    internal var modePicker: some View {
        pickerShell(title: "Mode") {
            let modes = catalog.modes(forProvider: providerId)
            ScrollView {
                RowGroup {
                    pickerRow(title: "Provider default", checked: modeId.isEmpty) {
                        modeId = ""
                        picker = nil
                    }
                    ForEach(Array(modes.enumerated()), id: \.element.id) { _, mode in
                        RowDivider()
                        pickerRow(title: mode.label, detail: mode.description, checked: modeId == mode.id) {
                            modeId = mode.id
                            picker = nil
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
    }

    internal var thinkingPicker: some View {
        pickerShell(title: "Thinking") {
            let options: [ProviderThinkingOption] = {
                guard let modelId = resolvedThinkingModelId else { return [] }
                return catalog.thinkingOptions(forProvider: providerId, modelId: modelId)
            }()
            ScrollView {
                RowGroup {
                    pickerRow(title: "Provider default", checked: thinkingId.isEmpty) {
                        thinkingId = ""
                        picker = nil
                    }
                    ForEach(Array(options.enumerated()), id: \.element.id) { _, option in
                        RowDivider()
                        pickerRow(
                            title: option.label,
                            detail: option.description,
                            checked: thinkingId == option.id,
                            badge: option.isDefault == true ? "Default" : nil
                        ) {
                            thinkingId = option.id
                            picker = nil
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                if options.isEmpty {
                    Text(resolvedThinkingModelId == nil
                        ? "Choose a provider first."
                        : "This model reports no thinking levels.")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(16)
                }
            }
        }
    }

    internal var workspacePicker: some View {
        pickerShell(title: "Target workspace") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    RowGroup {
                        ForEach(Array(workspaces.enumerated()), id: \.element.id) { index, workspace in
                            if index > 0 { RowDivider() }
                            pickerRow(
                                title: workspace.title ?? workspace.name,
                                detail: "\(workspace.projectDisplayName)\(workspace.branch.map { " · \($0)" } ?? "")",
                                checked: cwd == workspace.cwd
                            ) {
                                cwd = workspace.cwd
                                picker = nil
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    if workspaces.isEmpty {
                        Text("This host has no workspaces yet. Create one from the sidebar first.")
                            .font(.paseo(.footnote))
                            .foregroundStyle(Palette.secondaryInk)
                            .padding(16)
                    }
                }
            }
        }
    }
}
#endif
