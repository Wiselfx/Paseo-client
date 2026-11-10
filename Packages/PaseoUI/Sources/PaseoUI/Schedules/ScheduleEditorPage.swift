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

struct ScheduleEditorPage: View {
    let session: HostSession
    let seed: ClaudeSchedulesView.EditorSeed
    let onBack: () -> Void
    let onCreated: (String) -> Void
    let showToast: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The picker currently open inside the editor; nil shows the form.
    enum Picker: Hashable {
        case provider, model, mode, thinking, workspace
    }

    @State var picker: Picker?
    @State private var isSaving = false

    @State var name: String
    @State private var prompt: String
    @State private var cron: String
    @State private var usePreset: Int?
    @State private var timezone: String
    /// A cadence that is `.every` or otherwise not one we can edit as cron: shown read-only.
    @State private var readOnlyCadence: String?
    @State private var maxRuns: String
    @State var cwd: String
    @State var providerId: String
    @State var modelId: String
    @State var modeId: String
    @State var thinkingId: String

    private var schedules: SchedulesStore { session.schedules }
    var workspaces: [WorkspaceDescriptor] {
        session.workspaceDirectory.groups.flatMap(\.workspaces)
    }
    private var isHeartbeat: Bool { seed.isHeartbeat }
    var catalog: AgentControlStore { session.agentControl }

    init(
        session: HostSession, seed: ClaudeSchedulesView.EditorSeed,
        onBack: @escaping () -> Void, onCreated: @escaping (String) -> Void, showToast: @escaping (String) -> Void
    ) {
        self.session = session
        self.seed = seed
        self.onBack = onBack
        self.onCreated = onCreated
        self.showToast = showToast
        if let stored = seed.stored {
            _name = State(initialValue: stored.summary.name ?? "")
            _prompt = State(initialValue: stored.summary.prompt)
            _maxRuns = State(initialValue: stored.summary.maxRuns.map(String.init) ?? "")
            switch stored.summary.cadence {
            case .cron(let expression, let timezone):
                _cron = State(initialValue: expression)
                _timezone = State(initialValue: timezone ?? "")
                _usePreset = State(initialValue: CadencePreset.all.firstIndex(where: { $0.expression == expression }))
            default:
                _cron = State(initialValue: "")
                _timezone = State(initialValue: "")
                _usePreset = State(initialValue: nil)
                _readOnlyCadence = State(initialValue: stored.summary.cadence.words)
            }
            if let config = stored.summary.target.newAgentConfig {
                _cwd = State(initialValue: config.cwd)
                _providerId = State(initialValue: config.provider)
                _modelId = State(initialValue: config.model ?? "")
                _modeId = State(initialValue: config.modeId ?? "")
                _thinkingId = State(initialValue: config.thinkingOptionId ?? "")
            } else {
                _cwd = State(initialValue: "")
                _providerId = State(initialValue: "")
                _modelId = State(initialValue: "")
                _modeId = State(initialValue: "")
                _thinkingId = State(initialValue: "")
            }
        } else {
            let firstWorkspace = session.workspaceDirectory.groups.first?.workspaces.first
            _name = State(initialValue: "")
            _prompt = State(initialValue: "")
            _cron = State(initialValue: CadencePreset.all[0].expression)
            _usePreset = State(initialValue: 0)
            _timezone = State(initialValue: "")
            _readOnlyCadence = State(initialValue: nil)
            _maxRuns = State(initialValue: "")
            _cwd = State(initialValue: firstWorkspace?.cwd ?? "")
            let firstProvider = session.agentControl.readyProviders.first?.provider ?? ""
            _providerId = State(initialValue: firstProvider)
            _modelId = State(initialValue: "")
            _modeId = State(initialValue: "")
            _thinkingId = State(initialValue: "")
        }
    }

    var body: some View {
        Group {
            if let picker {
                pickerView(picker)
            } else {
                form
            }
        }
        .onAppear {
            if catalog.readyProviders.isEmpty {
                Task { await catalog.loadCatalog(cwd: nil) }
            }
        }
    }

    // MARK: Form

    private var form: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(seed.title)
                    .font(.paseo(.title, weight: .semibold))
                HStack {
                    Button {
                        Haptics.selection()
                        onBack()
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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fieldLabel("Name")
                    TextField("Optional", text: $name)
                        .font(.paseo(.callout))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 46)
                        .background(Palette.panel, in: .capsule)
                        .overlay { Capsule().stroke(Palette.ink.opacity(0.10), lineWidth: 0.5) }
                        .accessibilityIdentifier("schedule.name")
                    fieldLabel("Prompt")
                    ZStack(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("What should the agent do each time?")
                                .font(.paseo(.callout))
                                .foregroundStyle(Palette.secondaryInk)
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $prompt)
                            .font(.paseo(.callout))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .accessibilityIdentifier("schedule.prompt")
                    }
                    .frame(height: 132)
                    .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
                    .overlay { RoundedRectangle(cornerRadius: Radius.lg).stroke(Palette.ink.opacity(0.08), lineWidth: 0.5) }
                    cadenceSection
                    fieldLabel("Max runs")
                    TextField("Unlimited", text: $maxRuns)
                        .keyboardType(.numberPad)
                        .font(.paseo(.callout))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 46)
                        .background(Palette.panel, in: .capsule)
                        .overlay { Capsule().stroke(Palette.ink.opacity(0.10), lineWidth: 0.5) }
                        .accessibilityIdentifier("schedule.maxRuns")
                    if isHeartbeat {
                        Text("This schedule prompts an existing agent every run.")
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .padding(.horizontal, 6)
                    } else {
                        targetSection
                        agentSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            if let actionError = schedules.actionError {
                Text(actionError)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.failureInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            bottomBar
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.paseo(.caption2, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Palette.secondaryInk)
            .padding(.leading, 6)
    }

    // MARK: Cadence

    private var cadenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Cadence")
            if let readOnlyCadence {
                HStack {
                    Image(systemName: "clock").foregroundStyle(Palette.secondaryInk)
                    Text(readOnlyCadence).font(.paseo(.callout)).foregroundStyle(Palette.ink)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(Palette.panel, in: .capsule)
                .overlay { Capsule().stroke(Palette.ink.opacity(0.10), lineWidth: 0.5) }
                Text("Interval cadences can't be edited here yet.")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, 6)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
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
                                .background(selected ? Palette.ink : Palette.panel, in: .rect(cornerRadius: Radius.md))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                TextField("Custom cron expression", text: $cron)
                    .font(.paseo(.code))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
                    .background(Palette.panel, in: .capsule)
                    .overlay {
                        Capsule().stroke(
                            cronIsInvalid && !cron.isEmpty
                                ? Palette.failureInk
                                : Palette.ink.opacity(0.10),
                            lineWidth: 0.5)
                    }
                    .onChange(of: cron) { _, expression in
                        if let index = CadencePreset.all.firstIndex(where: { $0.expression == expression }) {
                            usePreset = index
                        } else {
                            usePreset = nil
                        }
                    }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("schedule.cron")
                if cronIsInvalid && !cron.isEmpty {
                    Text("Five fields: minute hour day-of-month month day-of-week.")
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.failureInk)
                        .padding(.horizontal, 6)
                }
                TextField("Timezone (optional)", text: $timezone)
                    .font(.paseo(.code))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
                    .background(Palette.panel, in: .capsule)
                    .overlay { Capsule().stroke(Palette.ink.opacity(0.10), lineWidth: 0.5) }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("schedule.timezone")
            }
        }
    }

    // MARK: Target

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Target workspace")
            RowGroup {
                ForEach(Array(workspaces.enumerated()), id: \.element.id) { index, workspace in
                    if index > 0 { RowDivider() }
                    workspaceRow(workspace)
                }
                if !cwd.isEmpty, !workspaces.contains(where: { $0.cwd == cwd }) {
                    RowDivider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom directory").font(.paseo(.callout))
                        Text(cwd)
                            .font(.paseo(.codeCaption))
                            .foregroundStyle(Palette.captionInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func workspaceRow(_ workspace: WorkspaceDescriptor) -> some View {
        let selected = cwd == workspace.cwd
        return Button {
            Haptics.selection()
            cwd = workspace.cwd
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.title ?? workspace.name)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text("\(workspace.projectDisplayName)\(workspace.branch.map { " · \($0)" } ?? "")")
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.glyph(.regular, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Agent

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Agent")
            RowGroup {
                SheetRow(title: "Provider", value: providerValue, chevron: true) {
                    picker = .provider
                }
                RowDivider()
                SheetRow(title: "Model", value: modelValue, chevron: true) {
                    picker = .model
                }
                RowDivider()
                SheetRow(title: "Mode", value: modeValue, chevron: true) {
                    picker = .mode
                }
                RowDivider()
                SheetRow(title: "Thinking", value: thinkingValue, chevron: true) {
                    picker = .thinking
                }
            }
        }
    }

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
        return catalog.modes(forProvider: providerId).first(where: { $0.id == modeId })?.label ?? modeId
    }

    private var thinkingValue: String {
        if thinkingId.isEmpty { return "Provider default" }
        let modelId = resolvedThinkingModelId
        guard let modelId else { return thinkingId }
        return catalog.thinkingOptions(forProvider: providerId, modelId: modelId)
            .first(where: { $0.id == thinkingId })?.label ?? thinkingId
    }

    var resolvedThinkingModelId: String? {
        if !modelId.isEmpty { return modelId }
        return catalog.defaultModel(forProvider: providerId)?.id
    }

    // MARK: Bottom bar and validation

    private var promptIsEmpty: Bool { prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var cronIsInvalid: Bool { !ScheduleWords.isValid(cron: cron) }
    private var maxRunsIsInvalid: Bool {
        let trimmed = maxRuns.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return Int(trimmed).map { $0 >= 1 } != true
    }
    private var canSave: Bool {
        if isHeartbeat {
            return !promptIsEmpty && !maxRunsIsInvalid && (readOnlyCadence != nil || !cronIsInvalid)
        }
        return !promptIsEmpty && !cronIsInvalid && !maxRunsIsInvalid && !providerId.isEmpty && !cwd.isEmpty
    }

    private var bottomBar: some View {
        Button {
            save()
        } label: {
            Text(isSaving ? "Saving…" : (seed.stored == nil ? "Create schedule" : "Save changes"))
                .font(.paseo(.callout, weight: .semibold))
                .foregroundStyle(canSave ? Palette.background : Palette.background.opacity(0.55))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(canSave ? Palette.ink : Palette.ink.opacity(0.3), in: .capsule)
        }
        .disabled(!canSave || isSaving)
        .accessibilityIdentifier("schedule.save")
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func save() {
        Haptics.selection()
        isSaving = true
        if let stored = seed.stored {
            Task {
                let edits = buildEdits(stored)
                if await schedules.update(stored.id, edits) {
                    showToast("Saved")
                    onCreated(stored.id)
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
                    prompt: prompt, cadence: cadence, target: .newAgent(config), maxRuns: maxRunsValue)
                if let created = await schedules.create(draft) {
                    showToast("Schedule created")
                    onCreated(created.id)
                }
                isSaving = false
            }
        }
    }

    private func buildEdits(_ stored: StoredSchedule) -> ScheduleEdits {
        let initial = stored.summary
        let namePatch = patchString(name, comparedTo: initial.name ?? "")
        let promptEdit = prompt.trimmingCharacters(in: .whitespacesAndNewlines) == initial.prompt.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : prompt
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
            return ScheduleEdits(name: namePatch, prompt: promptEdit, cadence: cadenceEdit, maxRuns: maxRunsPatch)
        }

        var newAgentConfig: ScheduleNewAgentConfigUpdate? = nil
        let providerChanged = providerId != config.provider
        let modelPatch = patchString(modelId, comparedTo: config.model ?? "")
        let modePatch = patchString(modeId, comparedTo: config.modeId ?? "")
        let thinkingPatch = patchString(thinkingId, comparedTo: config.thinkingOptionId ?? "")
        if providerChanged || modelPatch != .unchanged || modePatch != .unchanged || thinkingPatch != .unchanged {
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
        guard newTrimmed.isEmpty || parsed != nil else { return .unchanged } // invalid input can't be saved anyway
        if parsed == old { return .unchanged }
        guard let parsed else { return .clear }
        return .set(parsed)
    }
}
#endif
