#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → Host → Agents: the Paseo tools switches, the system prompt appended to every
/// agent, orchestration skills, restart recovery, idle cleanup and the host's agent profiles.
struct AgentsPage: View {
    let session: HostSession

    @State private var appendPromptDraft: String?
    @State private var appendPromptSaving = false
    @State private var showResumePromptSheet = false
    @FocusState private var appendPromptFocused: Bool

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
                SystemPromptCard(
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
                    ResumeOnStartupRow(
                        isOn: configBinding(
                            get: { $0.resumeOnStartup == true },
                            set: { $0.resumeOnStartup = $1 }),
                        canEdit: resumeOnStartupEnabled,
                        isDisabled: configControlsDisabled,
                        onEdit: { showResumePromptSheet = true }
                    )
                    .panelRow()
                } header: {
                    Text("Restart recovery")
                }
            }
            // COMPAT(idleRuntimeCleanup): `idleRuntimeCleanupSetting`, daemon v0.13.0.
            if hostSettings.supportsIdleRuntimeCleanup {
                Section {
                    SettingsToggleRow(
                        title: "Release idle agents",
                        hint: "Free up memory after an hour of inactivity.",
                        info:
                            "Stops the agent's process while keeping its conversation. Send a message to resume.\n\nActive work, pending notifications, and provider safety checks prevent cleanup.",
                        isOn: configBinding(
                            get: { $0.idleRuntimeCleanup != false },
                            set: { $0.idleRuntimeCleanup = $1 }),
                        isDisabled: configControlsDisabled
                    )
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
        .sheet(isPresented: $showResumePromptSheet) { ResumePromptSheet(hostSettings: hostSettings) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    if appendPromptFocused, appendPromptDirty { saveAppendPrompt() }
                    appendPromptFocused = false
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
        appendPromptSaving = true
        Task {
            var patch = DaemonConfigPatch()
            patch.appendSystemPrompt = draft
            let ok = await hostSettings.save(patch)
            appendPromptSaving = false
            if ok {
                appendPromptDraft = nil
                Haptics.success()
            }
            appendPromptFocused = false
        }
    }

    // MARK: Restart recovery

    private var resumeOnStartupEnabled: Bool {
        hostSettings.config?.resumeOnStartup == true
    }
}
#endif
