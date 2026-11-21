#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The schedule editor, pushed from the list or the detail page. Unsaved edits block the swipe
/// down and ask "Discard changes?" on back (PLAN §RI 11); the keyboard has a Done button for
/// the number pad and the prompt editor.
struct ScheduleEditorPage: View {
    let session: HostSession
    let seed: ClaudeSchedulesView.EditorSeed

    @Environment(\.dismiss) private var dismiss
    @Environment(\.toast) private var toast

    /// The picker this editor pushes; nil shows the form.
    enum Picker: Hashable {
        case provider, model, mode, thinking
    }

    @State private var picker: Picker?
    @State private var isSaving = false
    @State private var asksDiscard = false

    /// The editable values, and what they were when the page opened. Both are `@State`, so a
    /// re-init of the page (the stores may have loaded since) never moves the baseline.
    @State private var fields: ScheduleEditorFields
    @State private var baseline: ScheduleEditorFields
    @State private var usePreset: Int?
    /// A cadence that is `.every` or otherwise not one we can edit as cron: shown read-only.
    @State private var readOnlyCadence: String?

    @FocusState private var promptFocused: Bool
    @FocusState private var maxRunsFocused: Bool

    private var schedules: SchedulesStore { session.schedules }
    var workspaces: [WorkspaceDescriptor] {
        session.workspaceDirectory.groups.flatMap(\.workspaces)
    }
    private var isHeartbeat: Bool { seed.isHeartbeat }
    var catalog: AgentControlStore { session.agentControl }

    init(session: HostSession, seed: ClaudeSchedulesView.EditorSeed) {
        self.session = session
        self.seed = seed
        let initial = ScheduleEditorFields(
            seed: seed,
            defaultCwd: session.workspaceDirectory.groups.first?.workspaces.first?.cwd ?? "",
            defaultProviderId: session.agentControl.readyProviders.first?.provider ?? "")
        _fields = State(initialValue: initial)
        _baseline = State(initialValue: initial)
        _usePreset = State(
            initialValue: CadencePreset.all.firstIndex(where: { $0.expression == initial.cron }))
        var readOnly: String?
        if let cadence = seed.stored?.summary.cadence {
            switch cadence {
            case .cron: break
            default: readOnly = cadence.words()
            }
        }
        _readOnlyCadence = State(initialValue: readOnly)
    }

    var body: some View {
        PageList {
            Section {
                TextField("Optional", text: $fields.name)
                    .font(.paseo(.callout))
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, Space.lg)
                    .frame(minHeight: 44)
                    .panelRow()
                    .accessibilityIdentifier("schedule.name")
            } header: {
                Text("Name")
            }
            Section {
                SchedulePromptField(prompt: $fields.prompt, isFocused: $promptFocused)
                    .panelRow()
            } header: {
                Text("Prompt")
            }
            Section {
                ScheduleCadenceSection(
                    cron: $fields.cron, timezone: $fields.timezone, usePreset: $usePreset,
                    readOnlyCadence: readOnlyCadence, cronIsInvalid: fields.cronIsInvalid)
            } header: {
                Text("Cadence")
            }
            Section {
                TextField("Unlimited", text: $fields.maxRunsText)
                    .keyboardType(.numberPad)
                    .focused($maxRunsFocused)
                    .font(.paseo(.callout))
                    .padding(.horizontal, Space.lg)
                    .frame(minHeight: 44)
                    .panelRow()
                    .accessibilityIdentifier("schedule.maxRuns")
            } header: {
                Text("Max runs")
            }
            if isHeartbeat {
                Section {
                    Text("This schedule prompts an existing agent every run.")
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.horizontal, Space.lg)
                        .panelRow(Palette.background)
                }
            } else {
                Section {
                    ScheduleWorkspaceRows(workspaces: workspaces, cwd: $fields.cwd)
                } header: {
                    Text("Target workspace")
                }
                Section {
                    ScheduleAgentRows(
                        providerValue: providerValue, modelValue: modelValue,
                        modeValue: modeValue, thinkingValue: thinkingValue, picker: $picker)
                } header: {
                    Text("Agent")
                }
            }
            if let actionError = schedules.actionError {
                Section {
                    InlineBanner(.failure, title: actionError)
                        .panelRow(Palette.background)
                }
            }
            Section {
                saveButton
                    .panelRow(Palette.background)
            }
        }
        .inlinePageTitle(seed.title)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back", systemImage: "chevron.left", action: attemptDismiss)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    promptFocused = false
                    maxRunsFocused = false
                }
            }
        }
        .navigationDestination(item: $picker) { which in
            pickerPage(which)
        }
        .sheetDirty(isDirty)
        .confirmationDialog(
            "Discard changes?", isPresented: $asksDiscard, titleVisibility: .visible
        ) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .task {
            if catalog.readyProviders.isEmpty {
                await catalog.loadCatalog(cwd: nil)
            }
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text(
                isSaving
                    ? "Saving…" : (seed.stored == nil ? "Create schedule" : "Save changes"))
        }
        .buttonStyle(.paseoPrimary(isWorking: isSaving))
        .disabled(!canSave || isSaving)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("schedule.save")
    }

    // MARK: Picker

    @ViewBuilder private func pickerPage(_ which: Picker) -> some View {
        switch which {
        case .provider:
            SchedulePickerPage(
                title: "Provider", rows: providerPickerRows, selected: $fields.providerId
            ) {
                fields.modelId = ""
                fields.modeId = ""
                fields.thinkingId = ""
            }
        case .model:
            SchedulePickerPage(title: "Model", rows: modelPickerRows, selected: $fields.modelId) {
                fields.thinkingId = ""
            }
        case .mode:
            SchedulePickerPage(title: "Mode", rows: modePickerRows, selected: $fields.modeId)
        case .thinking:
            SchedulePickerPage(title: "Thinking", rows: thinkingPickerRows, selected: $fields.thinkingId)
        }
    }

    private var providerPickerRows: [SchedulePickerRow] {
        guard !catalog.readyProviders.isEmpty else {
            return []
        }
        return catalog.readyProviders.map { entry in
            SchedulePickerRow(
                id: entry.provider,
                title: entry.label ?? entry.provider,
                detail: entry.description,
                badge: nil)
        }
    }

    private var modelPickerRows: [SchedulePickerRow] {
        let models = catalog.models(forProvider: fields.providerId)
        return [
            SchedulePickerRow(
                id: "", title: "Provider default", detail: nil, badge: nil)
        ] + models.map { model in
            SchedulePickerRow(
                id: model.id,
                title: model.label,
                detail: model.description,
                badge: model.isDefault == true ? "Default" : nil)
        }
    }

    private var modePickerRows: [SchedulePickerRow] {
        let modes = catalog.modes(forProvider: fields.providerId)
        return [
            SchedulePickerRow(id: "", title: "Provider default", detail: nil, badge: nil)
        ] + modes.map { mode in
            SchedulePickerRow(
                id: mode.id, title: mode.label, detail: mode.description, badge: nil)
        }
    }

    private var thinkingPickerRows: [SchedulePickerRow] {
        guard let modelId = resolvedThinkingModelId else {
            return [
                SchedulePickerRow(id: "", title: "Provider default", detail: nil, badge: nil)
            ]
        }
        let options = catalog.thinkingOptions(forProvider: fields.providerId, modelId: modelId)
        return [
            SchedulePickerRow(id: "", title: "Provider default", detail: nil, badge: nil)
        ] + options.map { option in
            SchedulePickerRow(
                id: option.id,
                title: option.label,
                detail: option.description,
                badge: option.isDefault == true ? "Default" : nil)
        }
    }

    // MARK: Values

    private var providerValue: String {
        if fields.providerId.isEmpty { return "Choose a provider" }
        return catalog.provider(fields.providerId)?.label ?? fields.providerId
    }

    private var modelValue: String {
        if fields.modelId.isEmpty { return "Provider default" }
        if let match = catalog.models(forProvider: fields.providerId).first(where: { $0.id == fields.modelId }) {
            return match.label
        }
        return fields.modelId
    }

    private var modeValue: String {
        if fields.modeId.isEmpty { return "Provider default" }
        return catalog.modes(forProvider: fields.providerId).first(where: { $0.id == fields.modeId })?.label
            ?? fields.modeId
    }

    private var thinkingValue: String {
        if fields.thinkingId.isEmpty { return "Provider default" }
        guard let modelId = resolvedThinkingModelId else { return fields.thinkingId }
        return catalog.thinkingOptions(forProvider: fields.providerId, modelId: modelId)
            .first(where: { $0.id == fields.thinkingId })?.label ?? fields.thinkingId
    }

    var resolvedThinkingModelId: String? {
        if !fields.modelId.isEmpty { return fields.modelId }
        return catalog.defaultModel(forProvider: fields.providerId)?.id
    }

    // MARK: Validation

    private var canSave: Bool {
        fields.canSave(isHeartbeat: isHeartbeat, hasReadOnlyCadence: readOnlyCadence != nil)
    }

    /// True once any field differs from what the editor opened with (PLAN §RI 11).
    private var isDirty: Bool { fields != baseline }

    // MARK: Save

    private func attemptDismiss() {
        if isDirty { asksDiscard = true } else { dismiss() }
    }

    private func save() {
        isSaving = true
        if let stored = seed.stored {
            Task {
                let edits = fields.edits(for: stored, hasReadOnlyCadence: readOnlyCadence != nil)
                if await schedules.update(stored.id, edits) {
                    toast?.show("Saved")
                    isSaving = false
                    Haptics.success()
                    dismiss()
                    return
                }
                isSaving = false
            }
        } else {
            Task {
                if await schedules.create(fields.draft) != nil {
                    toast?.show("Schedule created")
                    isSaving = false
                    Haptics.success()
                    dismiss()
                    return
                }
                isSaving = false
            }
        }
    }
}
#endif
