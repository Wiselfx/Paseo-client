#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The profile editor: name, provider, model, mode, thinking, notes. Seeded from an existing
/// profile in edit mode; empty in create mode. Saves by writing the whole list through
/// `HostSettingsStore.saveProfiles` (daemon config `agentProfiles`), like upstream.
struct AgentProfileEditSheet: View {
    let session: HostSession
    let target: ProfileEditTarget

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var providerID = ""
    @State private var model: String?
    @State private var modeId: String?
    @State private var thinkingOptionId: String?
    @State private var notes = ""
    @State private var saving = false
    @State private var saveError: String?
    @State private var didSeed = false
    /// The values the sheet opened with, so it can tell an edit from a seed.
    @State private var seeded = Seeded(
        name: "", providerID: "", model: nil, modeId: nil, thinkingOptionId: nil, notes: "")

    private struct Seeded: Equatable {
        var name: String
        var providerID: String
        var model: String?
        var modeId: String?
        var thinkingOptionId: String?
        var notes: String
    }


    private var entries: [ProviderSnapshotEntry] { session.agentControl.providers }
    private var providerOptions: [ProviderSnapshotEntry] {
        var options = entries
        if !providerID.isEmpty, !options.contains(where: { $0.provider == providerID }) {
            // Seeded from an existing profile whose provider is not in the current catalogue.
            options.append(ProviderSnapshotEntry(
                provider: providerID, status: .unknown(""), enabled: true, label: providerID))
        }
        return options
    }
    private var models: [AgentModelDefinition] {
        session.agentControl.models(forProvider: providerID)
    }
    private var modeOptions: [AgentMode] {
        session.agentControl.modes(forProvider: providerID)
    }
    private var effectiveModelID: String? {
        model ?? session.agentControl.defaultModel(forProvider: providerID)?.id
    }
    private var thinkingOptions: [ProviderThinkingOption] {
        guard let effectiveModelID else { return [] }
        return session.agentControl.thinkingOptions(
            forProvider: providerID, modelId: effectiveModelID)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        !saving && !trimmedName.isEmpty && !providerID.isEmpty
    }
    private var catalogHint: String? {
        if entries.isEmpty {
            if case .failed(let message) = session.agentControl.phase {
                return "Could not load the provider catalogue: \(message)"
            }
            return "The provider catalogue is not loaded yet."
        }
        return nil
    }

    private var sheetTitle: String {
        target.mode == .create ? "New profile" : "Edit profile"
    }

    /// The sheet asks before throwing edits away.
    private var isDirty: Bool { didSeed && hasEdits }

    private var hasEdits: Bool {
        name != seeded.name || notes != seeded.notes || providerID != seeded.providerID
            || model != seeded.model || modeId != seeded.modeId
            || thinkingOptionId != seeded.thinkingOptionId
    }

    var body: some View {
        SheetScaffold(
            sheetTitle,
            detents: .large,
            confirm: SheetConfirm(
                "Save", isEnabled: canSave, isWorking: saving,
                identifier: "settings.profiles.save"
            ) {
                Haptics.selection()
                save()
            }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    sectionLabel("Name")
                    RowGroup { nameField }
                    sectionLabel("Provider")
                    RowGroup { providerRow }
                    sectionLabel("Model")
                    RowGroup { modelRow }
                    sectionLabel("Mode")
                    RowGroup { modeRow }
                    sectionLabel("Thinking")
                    RowGroup { thinkingRow }
                    sectionLabel("When to use")
                    RowGroup { notesField }
                    Text("Free text surfaced to orchestrating agents, so they can pick the right profile.")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.leading, 16)
                    if let saveError {
                        InlineBanner(.failure, title: saveError)
                            .padding(.horizontal, Space.lg)
                    }
                }
                .padding(.bottom, Space.xxl)
                .sheetDirty(isDirty)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear(perform: seedIfNeeded)
    }

    // MARK: Fields

    private var nameField: some View {
        TextField("Profile name", text: $name)
            .font(.paseo(.body))
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .accessibilityIdentifier("settings.profiles.name.field")
    }

    private var notesField: some View {
        TextField("When to use this profile…", text: $notes, axis: .vertical)
            .font(.paseo(.callout))
            .lineLimit(2...5)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .accessibilityIdentifier("settings.profiles.notes.field")
    }

    private func pickerRow(
        title: String, current: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.paseo(.body))
            Spacer(minLength: 8)
            Menu {
                content()
            } label: {
                HStack(spacing: 5) {
                    Text(current)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var providerRow: some View {
        pickerRow(
            title: "Provider",
            current: providerID.isEmpty ? "Choose" : providerLabel(providerID)
        ) {
            if providerOptions.isEmpty {
                Text("No providers reported")
            } else {
                ForEach(providerOptions) { option in
                    Button(option.label ?? option.provider) {
                        selectProvider(option.provider)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.profiles.provider")
    }

    private var modelRow: some View {
        pickerRow(
            title: "Model",
            current: modelLabel(model)
        ) {
            Button("Provider default") { model = nil }
            ForEach(models) { option in
                Button(option.label) { model = option.id }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.profiles.model")
    }

    private var modeRow: some View {
        pickerRow(
            title: "Mode",
            current: modeLabel(modeId)
        ) {
            Button("Provider default") { modeId = nil }
            ForEach(modeOptions, id: \.id) { option in
                Button(option.label) { modeId = option.id }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.profiles.mode")
    }

    private var thinkingRow: some View {
        pickerRow(
            title: "Thinking",
            current: thinkingLabel(thinkingOptionId)
        ) {
            Button("Provider default") { thinkingOptionId = nil }
            ForEach(thinkingOptions) { option in
                Button(option.label) { thinkingOptionId = option.id }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.profiles.thinking")
    }

    // MARK: Labels

    private func providerLabel(_ id: String) -> String {
        entries.first { $0.provider == id }?.label ?? id
    }

    private func modelLabel(_ id: String?) -> String {
        guard let id else { return "Provider default" }
        return models.first { $0.id == id }?.label ?? id
    }

    private func modeLabel(_ id: String?) -> String {
        guard let id else { return "Provider default" }
        return modeOptions.first { $0.id == id }?.label ?? id
    }

    private func thinkingLabel(_ id: String?) -> String {
        guard let id else { return "Provider default" }
        return thinkingOptions.first { $0.id == id }?.label ?? id
    }

    // MARK: Lifecycle

    private func seedIfNeeded() {
        guard !didSeed else { return }
        didSeed = true
        let seed = target.profile
        name = seed?.name ?? ""
        providerID = seed?.provider ?? defaultProvider
        model = seed?.model
        modeId = seed?.modeId
        thinkingOptionId = seed?.thinkingOptionId
        notes = seed?.notes ?? ""
        seeded = Seeded(
            name: name, providerID: providerID, model: model, modeId: modeId,
            thinkingOptionId: thinkingOptionId, notes: notes)
        if session.agentControl.phase == .idle {
            Task { await session.agentControl.loadCatalog() }
        }
    }

    private var defaultProvider: String {
        entries.first { $0.status == .ready }?.provider ?? entries.first?.provider ?? ""
    }

    private func selectProvider(_ id: String) {
        guard id != providerID else { return }
        Haptics.selection()
        providerID = id
        model = nil
        modeId = nil
        thinkingOptionId = nil
    }

    // MARK: Save


    private func save() {
        let trimmed = trimmedName
        guard !trimmed.isEmpty, !providerID.isEmpty else { return }
        saving = true
        saveError = nil
        var profile = target.profile
            ?? AgentProfile(id: UUID().uuidString, name: trimmed, provider: providerID)
        profile.name = trimmed
        profile.provider = providerID
        profile.model = model
        profile.modeId = modeId
        profile.thinkingOptionId = thinkingOptionId
        profile.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = session.hostSettings.profiles
        if target.mode == .edit, let existing = next.firstIndex(where: { $0.id == profile.id }) {
            next[existing] = profile
        } else {
            next.append(profile)
        }
        Task {
            let ok = await session.hostSettings.saveProfiles(next)
            saving = false
            if ok {
                dismiss()
            } else {
                saveError = session.hostSettings.error ?? "The daemon rejected that profile."
            }
        }
    }

    // MARK: Shared bits

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.paseo(.callout))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }
}
#endif
