#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → Host → Agents: the Paseo tools switches, the system prompt appended to every
/// agent, orchestration skills, restart recovery, idle cleanup and the host's agent profiles.
struct AgentsPage: View {
    let session: HostSession

    @State private var appendPromptDraft: String?
    @State private var appendPromptSaving = false
    @State private var resumePromptDraft: String?
    @State private var resumePromptSaving = false
    @State private var showResumePromptSheet = false
    @FocusState private var appendPromptFocused: Bool
    @FocusState private var resumePromptFocused: Bool

    private var hostSettings: HostSettingsStore { session.hostSettings }

    var body: some View {
        PageList {
            Section {
                configToggleRow(
                    "Enable Paseo tools",
                    subtitle: "Agents will be able to manage worktrees, agents and schedules",
                    isOn: configBinding(
                        get: { $0.mcp?.injectIntoAgents ?? true },
                        set: { $0.mcp = .init(injectIntoAgents: $1) }))
                configToggleRow(
                    "Browser tools",
                    subtitle: "Agents can control the in-app browser, including logged-in state",
                    isOn: configBinding(
                        get: { $0.browserTools?.enabled ?? false },
                        set: { $0.browserTools = .init(enabled: $1) }))
            } header: {
                Text("Tools")
            }
            Section {
                promptCard(
                    title: "Appended to every agent's system prompt",
                    placeholder: "What every agent should always know…",
                    draft: appendPromptBinding,
                    focused: $appendPromptFocused,
                    saving: appendPromptSaving,
                    dirty: appendPromptDirty
                ) {
                    saveAppendPrompt()
                }
                .panelRow()
            } header: {
                Text("System prompt")
            }
            if let skills = hostSettings.config?.skillsSelection {
                Section {
                    ListRow(
                        title: "Skills",
                        subtitle: "Installed on the host for orchestrating agents",
                        accessory: ListRow.Accessory.value(skills.label)
                    )
                    .panelRow()
                } header: {
                    Text("Orchestration skills")
                }
            }
            // COMPAT(restartRecovery): the card needs the host's `resumeOnStartupSetting`
            // feature (messages.ts:240-271, daemon v0.14.0); an old host drops the patch.
            if hostSettings.supportsResumeOnStartup {
                Section {
                    resumeOnStartupRow
                        .panelRow()
                } header: {
                    Text("Restart recovery")
                }
            }
            // COMPAT(idleRuntimeCleanup): `idleRuntimeCleanupSetting`, daemon v0.13.0.
            if hostSettings.supportsIdleRuntimeCleanup {
                Section {
                    labeledToggleRow(
                        "Release idle agents",
                        hint: "Free up memory after an hour of inactivity.",
                        info:
                            "Stops the agent's process while keeping its conversation. Send a message to resume.\n\nActive work, pending notifications, and provider safety checks prevent cleanup.",
                        isOn: configBinding(
                            get: { $0.idleRuntimeCleanup != false },
                            set: { $0.idleRuntimeCleanup = $1 }))
                    .panelRow()
                } header: {
                    Text("Idle agents")
                }
            }
            Section {
                VStack(alignment: .leading, spacing: Space.sm) {
                    AgentProfilesSection(session: session)
                }
                .panelRow(Palette.background)
            }
            if let error = hostSettings.error {
                Section {
                    InlineBanner(
                        .failure, title: error,
                        action: ("Try again", { Task { await hostSettings.load() } }))
                        .panelRow(Palette.background)
                }
            }
        }
        .inlinePageTitle("Agents")
        .refreshable { await hostSettings.load() }
        .sheet(isPresented: $showResumePromptSheet) { resumePromptSheet }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    if appendPromptFocused, appendPromptDirty { saveAppendPrompt() }
                    if resumePromptFocused, resumePromptDirty { saveResumePrompt() }
                    appendPromptFocused = false
                    resumePromptFocused = false
                }
            }
        }
    }

    // MARK: Shared save helpers

    private var configControlsDisabled: Bool {
        hostSettings.isSaving || hostSettings.config == nil
    }

    private func configBinding(
        get: @escaping (DaemonConfig) -> Bool,
        set: @escaping (inout DaemonConfigPatch, Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard let config = hostSettings.config else { return false }
                return get(config)
            },
            set: { newValue in
                var patch = DaemonConfigPatch()
                set(&patch, newValue)
                Haptics.selection()
                Task { await hostSettings.save(patch) }
            })
    }

    private func configToggleRow(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        ListRow(title: title, subtitle: subtitle, accessory: ListRow.Accessory.toggle(isOn))
            .panelRow()
            .disabled(configControlsDisabled)
            .accessibilityIdentifier("settings.config." + title)
    }

    // MARK: System prompt

    private var appendPromptBinding: Binding<String> {
        Binding(
            get: { appendPromptDraft ?? hostSettings.config?.appendSystemPrompt ?? "" },
            set: { appendPromptDraft = $0 })
    }

    private var appendPromptDirty: Bool {
        guard let draft = appendPromptDraft else { return false }
        return draft != (hostSettings.config?.appendSystemPrompt ?? "")
    }

    private func saveAppendPrompt() {
        guard let draft = appendPromptDraft else { return }
        Haptics.selection()
        appendPromptSaving = true
        Task {
            var patch = DaemonConfigPatch()
            patch.appendSystemPrompt = draft
            let ok = await hostSettings.save(patch)
            appendPromptSaving = false
            if ok { appendPromptDraft = nil }
            appendPromptFocused = false
        }
    }

    @ViewBuilder private func promptCard(
        title: String,
        placeholder: String,
        draft: Binding<String>,
        focused: FocusState<Bool>.Binding,
        saving: Bool,
        dirty: Bool,
        onSave: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
            TextField(placeholder, text: draft, axis: .vertical)
                .font(.paseo(.codeSmall))
                .lineLimit(3...12)
                .padding(Space.md)
                .background(Palette.background.opacity(0.55), in: .rect(cornerRadius: Radius.md))
                .focused(focused)
            if dirty {
                HStack {
                    Spacer(minLength: Space.sm)
                    Button(action: onSave) {
                        Text(saving ? "Saving…" : "Done")
                            .font(.paseo(.callout, weight: .semibold))
                    }
                    .disabled(saving)
                }
            }
        }
        .padding(Space.lg)
    }

    // MARK: Restart recovery

    /// Upstream's restart-recovery card (`restart-recovery-card.tsx`): title with an info tip,
    /// the hint, then Edit and the switch. Edit edits the prompt the daemon appends to a
    /// resumed agent's message.
    private var resumeOnStartupRow: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text("Resume agents after restart")
                        .font(.paseo(.body))
                    SettingsInfoButton(
                        title: "Resume agents after restart",
                        info:
                            "Reopen agents that were working when the host stopped and send the resume prompt. Applies after graceful restarts and crashes."
                    )
                }
                Text("Continue interrupted work automatically.")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.sm)
            Button("Edit") { showResumePromptSheet = true }
                .font(.paseo(.callout))
                .disabled(!resumeOnStartupEnabled || configControlsDisabled)
                .accessibilityLabel("Edit prompt")
            Toggle(
                "",
                isOn: configBinding(
                    get: { $0.resumeOnStartup == true },
                    set: { $0.resumeOnStartup = $1 })
            )
            .labelsHidden()
            .tint(Palette.toggleTint)
            .disabled(configControlsDisabled)
            .accessibilityLabel("Resume agents after restart")
            .accessibilityIdentifier("settings.config.Resume agents after restart")
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(minHeight: 44)
    }

    private var resumeOnStartupEnabled: Bool {
        hostSettings.config?.resumeOnStartup == true
    }

    /// Upstream's idle-cleanup card (`idle-runtime-cleanup-card.tsx`): title with an info tip,
    /// the hint, then the switch. The switch defaults on — the daemon only reports it as off.
    private func labeledToggleRow(
        _ title: String, hint: String, info: String, isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text(title)
                        .font(.paseo(.body))
                    SettingsInfoButton(title: title, info: info)
                }
                Text(hint)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.sm)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Palette.toggleTint)
                .disabled(configControlsDisabled)
                .accessibilityLabel(title)
                .accessibilityIdentifier("settings.config." + title)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(minHeight: 44)
    }

    // MARK: Resume prompt sheet

    /// Upstream's `ResumePromptSheet`: the saved prompt (or the default), Cancel and Save. Save
    /// needs a change and a non-blank prompt.
    private var resumePromptSheet: some View {
        SheetScaffold("Resume prompt", detents: .medium) {
            VStack(alignment: .leading, spacing: Space.lg) {
                TextField("Resume working.", text: resumePromptBinding, axis: .vertical)
                    .font(.paseo(.codeSmall))
                    .lineLimit(4...12)
                    .padding(Space.md)
                    .background(Palette.background.opacity(0.55), in: .rect(cornerRadius: Radius.md))
                    .focused($resumePromptFocused)
                    .accessibilityLabel("Resume prompt")
                if let error = hostSettings.error {
                    Text(error)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                }
                HStack(spacing: Space.md) {
                    Button("Cancel") { closeResumePromptSheet() }
                        .buttonStyle(.paseoSecondary)
                        .disabled(resumePromptSaving)
                    Spacer(minLength: 0)
                    Button(resumePromptSaving ? "Saving…" : "Save") { saveResumePrompt() }
                        .buttonStyle(.paseoPrimary(isWorking: resumePromptSaving))
                        .disabled(!canSaveResumePrompt)
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.md)
        }
    }

    private var resumePromptBinding: Binding<String> {
        Binding(
            get: { resumePromptDraft ?? hostSettings.config?.resumePrompt ?? "" },
            set: { resumePromptDraft = $0 })
    }

    private var resumePromptDirty: Bool {
        guard let draft = resumePromptDraft else { return false }
        return draft != (hostSettings.config?.resumePrompt ?? "")
    }

    private func saveResumePrompt() {
        guard let draft = resumePromptDraft else { return }
        Haptics.selection()
        resumePromptSaving = true
        Task {
            var patch = DaemonConfigPatch()
            patch.resumePrompt = draft
            let ok = await hostSettings.save(patch)
            resumePromptSaving = false
            if ok { resumePromptDraft = nil }
            resumePromptFocused = false
            if ok { showResumePromptSheet = false }
        }
    }

    private func closeResumePromptSheet() {
        resumePromptDraft = nil
        resumePromptFocused = false
        showResumePromptSheet = false
    }

    private var canSaveResumePrompt: Bool {
        guard let draft = resumePromptDraft, resumePromptDirty, !resumePromptSaving else {
            return false
        }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Upstream's `SettingsInfoTip`: an info icon in the title that opens the explanation. A popover,
/// not a paragraph under the row, so the row stays one line (UX-SPEC §0.3).
struct SettingsInfoButton: View {
    let title: String
    let info: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.glyph(.small))
                .foregroundStyle(Palette.tertiaryInk)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(title)")
        .popover(isPresented: $isPresented) {
            Text(info)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Space.xl)
                .frame(maxWidth: 320)
                .presentationCompactAdaptation(.popover)
        }
    }
}
#endif
