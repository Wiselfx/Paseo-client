#if canImport(UIKit)
import PaseoStore
import SwiftUI

// MARK: - Editor page

struct CadencePreset: Hashable {
    let label: String
    let expression: String

    static let all: [CadencePreset] = [
        .init(label: "Every day at 9:00", expression: "0 9 * * *"),
        .init(label: "Weekdays at 9:00", expression: "0 9 * * 1-5"),
        .init(label: "Mondays at 9:00", expression: "0 9 * * 1"),
        .init(label: "1st of the month at 9:00", expression: "0 9 1 * *"),
        .init(label: "Every 6 hours", expression: "0 */6 * * *"),
        .init(label: "Every hour", expression: "0 * * * *"),
    ]
}

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

    @State private var name: String
    @State private var prompt: String
    @State private var cron: String
    @State private var usePreset: Int?
    @State private var timezone: String
    /// A cadence that is `.every` or otherwise not one we can edit as cron: shown read-only.
    @State private var readOnlyCadence: String?
    @State private var maxRuns: String
    @State private var cwd: String
    @State private var providerId: String
    @State private var modelId: String
    @State private var modeId: String
    @State private var thinkingId: String

    @FocusState private var promptFocused: Bool
    @FocusState private var maxRunsFocused: Bool

    private let initialName: String
    private let initialPrompt: String
    private let initialCron: String
    private let initialTimezone: String
    private let initialMaxRuns: String
    private let initialCwd: String
    private let initialProvider: String
    private let initialModel: String
    private let initialMode: String
    private let initialThinking: String

    private var schedules: SchedulesStore { session.schedules }
    var workspaces: [WorkspaceDescriptor] {
        session.workspaceDirectory.groups.flatMap(\.workspaces)
    }
    private var isHeartbeat: Bool { seed.isHeartbeat }
    var catalog: AgentControlStore { session.agentControl }

    init(session: HostSession, seed: ClaudeSchedulesView.EditorSeed) {
        self.session = session
        self.seed = seed
        var name = ""
        var prompt = ""
        var cron = CadencePreset.all[0].expression
        var timezone = ""
        var maxRuns = ""
        var cwd = session.workspaceDirectory.groups.first?.workspaces.first?.cwd ?? ""
        var providerId = session.agentControl.readyProviders.first?.provider ?? ""
        var modelId = ""
        var modeId = ""
        var thinkingId = ""
        var readOnlyCadence: String?
        var usePreset: Int? = 0
        if let stored = seed.stored {
            let summary = stored.summary
            name = summary.name ?? ""
            prompt = summary.prompt
            maxRuns = summary.maxRuns.map(String.init) ?? ""
            switch summary.cadence {
            case .cron(let expression, let storedTimezone):
                cron = expression
                timezone = storedTimezone ?? ""
                usePreset = CadencePreset.all.firstIndex(where: { $0.expression == expression })
            default:
                cron = ""
                timezone = ""
                usePreset = nil
                readOnlyCadence = summary.cadence.words
            }
            if let config = summary.target.newAgentConfig {
                cwd = config.cwd
                providerId = config.provider
                modelId = config.model ?? ""
                modeId = config.modeId ?? ""
                thinkingId = config.thinkingOptionId ?? ""
            } else {
                cwd = ""
                providerId = ""
                modelId = ""
                modeId = ""
                thinkingId = ""
            }
        }
        _name = State(initialValue: name)
        _prompt = State(initialValue: prompt)
        _cron = State(initialValue: cron)
        _usePreset = State(initialValue: usePreset)
        _timezone = State(initialValue: timezone)
        _readOnlyCadence = State(initialValue: readOnlyCadence)
        _maxRuns = State(initialValue: maxRuns)
        _cwd = State(initialValue: cwd)
        _providerId = State(initialValue: providerId)
        _modelId = State(initialValue: modelId)
        _modeId = State(initialValue: modeId)
        _thinkingId = State(initialValue: thinkingId)
        initialName = name
        initialPrompt = prompt
        initialCron = cron
        initialTimezone = timezone
        initialMaxRuns = maxRuns
        initialCwd = cwd
        initialProvider = providerId
        initialModel = modelId
        initialMode = modeId
        initialThinking = thinkingId
    }

    var body: some View {
        PageList {
            Section {
                TextField("Optional", text: $name)
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
                promptEditor
                    .panelRow()
            } header: {
                Text("Prompt")
            }
            Section {
                cadenceSection
            } header: {
                Text("Cadence")
            }
            Section {
                TextField("Unlimited", text: $maxRuns)
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
                    workspaceRows
                } header: {
                    Text("Target workspace")
                }
                Section {
                    agentRows
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
                Button {
                    if isDirty { asksDiscard = true } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
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

    // MARK: Fields

    private var promptEditor: some View {
        ZStack(alignment: .topLeading) {
            if prompt.isEmpty {
                Text("What should the agent do each time?")
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(Space.lg)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $prompt)
                .font(.paseo(.callout))
                .scrollContentBackground(.hidden)
                .focused($promptFocused)
                .padding(Space.sm)
                .accessibilityIdentifier("schedule.prompt")
        }
        .frame(height: 132)
    }

    @ViewBuilder private var cadenceSection: some View {
        if let readOnlyCadence {
            ListRow(title: readOnlyCadence, systemImage: "clock")
                .panelRow()
            Text("Interval cadences can't be edited here yet.")
                .font(.paseo(.caption))
                .foregroundStyle(Palette.secondaryInk)
                .padding(.horizontal, Space.lg)
                .panelRow(Palette.background)
        } else {
            presetGrid
                .padding(Space.lg)
                .panelRow()
            TextField("Custom cron expression", text: $cron)
                .font(.paseo(.code))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, Space.lg)
                .frame(minHeight: 44)
                .panelRow()
                .overlay {
                    if cronIsInvalid, !cron.isEmpty {
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(Palette.failureInk, lineWidth: 0.5)
                    }
                }
                .onChange(of: cron) { _, expression in
                    if let index = CadencePreset.all.firstIndex(where: { $0.expression == expression }) {
                        usePreset = index
                    } else {
                        usePreset = nil
                    }
                }
                .accessibilityIdentifier("schedule.cron")
            if cronIsInvalid, !cron.isEmpty {
                Text("Five fields: minute hour day-of-month month day-of-week.")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.failureInk)
                    .padding(.horizontal, Space.lg)
                    .panelRow(Palette.background)
            }
            TextField("Timezone (optional)", text: $timezone)
                .font(.paseo(.code))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, Space.lg)
                .frame(minHeight: 44)
                .panelRow()
                .accessibilityIdentifier("schedule.timezone")
        }
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.sm) {
            ForEach(Array(CadencePreset.all.enumerated()), id: \.offset) { index, preset in
                let selected = usePreset == index && cron == preset.expression
                Button {
                    Haptics.selection()
                    usePreset = index
                    cron = preset.expression
                } label: {
                    Text(preset.label)
                        .font(.paseo(.caption, weight: .medium))
                        .foregroundStyle(selected ? Palette.background : Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 42)
                        .background(
                            selected ? Palette.ink : Palette.chip,
                            in: .rect(cornerRadius: Radius.md))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var workspaceRows: some View {
        ForEach(workspaces) { workspace in
            ListRow(
                title: workspace.title ?? workspace.name,
                subtitle:
                    "\(workspace.projectDisplayName)\(workspace.branch.map { " · \($0)" } ?? "")",
                accessory: ListRow.Accessory.checkmark(cwd == workspace.cwd),
                action: {
                    Haptics.selection()
                    cwd = workspace.cwd
                }
            )
            .panelRow()
        }
        if !cwd.isEmpty, !workspaces.contains(where: { $0.cwd == cwd }) {
            ListRow(title: "Custom directory", subtitle: cwd)
                .panelRow()
        }
    }

    @ViewBuilder private var agentRows: some View {
        ListRow(
            title: "Provider",
            accessory: ListRow.Accessory.value(providerValue),
            action: {
                Haptics.selection()
                picker = .provider
            }
        )
        .panelRow()
        ListRow(
            title: "Model",
            accessory: ListRow.Accessory.value(modelValue),
            action: {
                Haptics.selection()
                picker = .model
            }
        )
        .panelRow()
        ListRow(
            title: "Mode",
            accessory: ListRow.Accessory.value(modeValue),
            action: {
                Haptics.selection()
                picker = .mode
            }
        )
        .panelRow()
        ListRow(
            title: "Thinking",
            accessory: ListRow.Accessory.value(thinkingValue),
            action: {
                Haptics.selection()
                picker = .thinking
            }
        )
        .panelRow()
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
                title: "Provider", rows: providerPickerRows, selected: $providerId
            ) {
                modelId = ""
                modeId = ""
                thinkingId = ""
            }
        case .model:
            SchedulePickerPage(title: "Model", rows: modelPickerRows, selected: $modelId) {
                thinkingId = ""
            }
        case .mode:
            SchedulePickerPage(title: "Mode", rows: modePickerRows, selected: $modeId)
        case .thinking:
            SchedulePickerPage(title: "Thinking", rows: thinkingPickerRows, selected: $thinkingId)
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
        let models = catalog.models(forProvider: providerId)
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
        let modes = catalog.modes(forProvider: providerId)
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
        let options = catalog.thinkingOptions(forProvider: providerId, modelId: modelId)
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
        if providerId.isEmpty { return "Choose a provider" }
        return catalog.provider(providerId)?.label ?? providerId
    }

    private var modelValue: String {
        if modelId.isEmpty { return "Provider default" }
        if let match = catalog.models(forProvider: providerId).first(where: { $0.id == modelId }) {
            return match.label
        }
        return modelId
    }

    private var modeValue: String {
        if modeId.isEmpty { return "Provider default" }
        return catalog.modes(forProvider: providerId).first(where: { $0.id == modeId })?.label
            ?? modeId
    }

    private var thinkingValue: String {
        if thinkingId.isEmpty { return "Provider default" }
        guard let modelId = resolvedThinkingModelId else { return thinkingId }
        return catalog.thinkingOptions(forProvider: providerId, modelId: modelId)
            .first(where: { $0.id == thinkingId })?.label ?? thinkingId
    }

    var resolvedThinkingModelId: String? {
        if !modelId.isEmpty { return modelId }
        return catalog.defaultModel(forProvider: providerId)?.id
    }

    // MARK: Validation

    private var promptIsEmpty: Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var cronIsInvalid: Bool { !ScheduleWords.isValid(cron: cron) }
    private var maxRunsIsInvalid: Bool {
        let trimmed = maxRuns.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return Int(trimmed).map { $0 >= 1 } != true
    }
    private var canSave: Bool {
        if isHeartbeat {
            return !promptIsEmpty && !maxRunsIsInvalid
                && (readOnlyCadence != nil || !cronIsInvalid)
        }
        return !promptIsEmpty && !cronIsInvalid && !maxRunsIsInvalid && !providerId.isEmpty
            && !cwd.isEmpty
    }

    /// True once any field differs from what the editor opened with (PLAN §RI 11).
    private var isDirty: Bool {
        name != initialName
            || prompt != initialPrompt
            || maxRuns != initialMaxRuns
            || cron != initialCron
            || timezone != initialTimezone
            || cwd != initialCwd
            || providerId != initialProvider
            || modelId != initialModel
            || modeId != initialMode
            || thinkingId != initialThinking
    }

    // MARK: Save

    private func save() {
        Haptics.selection()
        isSaving = true
        if let stored = seed.stored {
            Task {
                let edits = buildEdits(stored)
                if await schedules.update(stored.id, edits) {
                    toast?.show("Saved")
                    isSaving = false
                    dismiss()
                    return
                }
                isSaving = false
            }
        } else {
            Task {
                let config = ScheduleNewAgentConfig(
                    provider: providerId, cwd: cwd,
                    modeId: modeId.isEmpty ? nil : modeId,
                    model: modelId.isEmpty ? nil : modelId,
                    thinkingOptionId: thinkingId.isEmpty ? nil : thinkingId)
                let trimmedTimezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)
                let cadence = ScheduleCadence.cron(
                    expression: cron.trimmingCharacters(in: .whitespacesAndNewlines),
                    timezone: trimmedTimezone.isEmpty ? nil : trimmedTimezone)
                let maxRunsValue = Int(maxRuns.trimmingCharacters(in: .whitespacesAndNewlines))
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let draft = ScheduleDraft(
                    name: trimmedName.isEmpty ? nil : trimmedName,
                    prompt: prompt, cadence: cadence, target: .newAgent(config),
                    maxRuns: maxRunsValue)
                if await schedules.create(draft) != nil {
                    toast?.show("Schedule created")
                    isSaving = false
                    dismiss()
                    return
                }
                isSaving = false
            }
        }
    }

    private func buildEdits(_ stored: StoredSchedule) -> ScheduleEdits {
        let initial = stored.summary
        let namePatch = patchString(name, comparedTo: initial.name ?? "")
        let promptEdit = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            == initial.prompt.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : prompt
        let maxRunsPatch = patchInt(maxRuns, comparedTo: initial.maxRuns)

        var cadenceEdit: ScheduleCadence?
        if readOnlyCadence == nil {
            let trimmedTimezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)
            let cadence = ScheduleCadence.cron(
                expression: cron.trimmingCharacters(in: .whitespacesAndNewlines),
                timezone: trimmedTimezone.isEmpty ? nil : trimmedTimezone)
            if cadence != initial.cadence { cadenceEdit = cadence }
        }

        guard let config = initial.target.newAgentConfig else {
            // A heartbeat: provider/model/mode/thinking stay untouched.
            return ScheduleEdits(
                name: namePatch, prompt: promptEdit, cadence: cadenceEdit, maxRuns: maxRunsPatch)
        }

        var newAgentConfig: ScheduleNewAgentConfigUpdate? = nil
        let providerChanged = providerId != config.provider
        let modelPatch = patchString(modelId, comparedTo: config.model ?? "")
        let modePatch = patchString(modeId, comparedTo: config.modeId ?? "")
        let thinkingPatch = patchString(thinkingId, comparedTo: config.thinkingOptionId ?? "")
        if providerChanged || modelPatch != .unchanged || modePatch != .unchanged
            || thinkingPatch != .unchanged
        {
            newAgentConfig = ScheduleNewAgentConfigUpdate(
                provider: providerChanged ? providerId : nil,
                model: modelPatch, modeId: modePatch, thinkingOptionId: thinkingPatch)
        }

        return ScheduleEdits(
            name: namePatch, prompt: promptEdit, cadence: cadenceEdit,
            maxRuns: maxRunsPatch, newAgentConfig: newAgentConfig)
    }

    private func patchString(_ new: String, comparedTo old: String) -> SchedulePatch<String> {
        let newTrimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldTrimmed = old.trimmingCharacters(in: .whitespacesAndNewlines)
        if newTrimmed == oldTrimmed { return .unchanged }
        return newTrimmed.isEmpty ? .clear : .set(newTrimmed)
    }

    private func patchInt(_ new: String, comparedTo old: Int?) -> SchedulePatch<Int> {
        let newTrimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = newTrimmed.isEmpty ? nil : Int(newTrimmed)
        // Invalid input can't be saved anyway.
        guard newTrimmed.isEmpty || parsed != nil else { return .unchanged }
        if parsed == old { return .unchanged }
        guard let parsed else { return .clear }
        return .set(parsed)
    }
}
#endif
