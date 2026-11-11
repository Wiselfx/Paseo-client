#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → Voice (host group): the Dictation and Voice mode switches plus the three
/// provider rows (Speech-to-text, Listening, Speaking), each opening a provider sheet.
/// Gated like upstream (`voice-page.tsx`): offline and old-host states instead of the page.
struct VoicePage: View {
    let session: HostSession

    @State private var openSite: SpeechSiteID?

    private var voice: VoiceSettingsStore { session.voiceSettings }
    private var speech: SpeechSettings? { voice.speechSettings }
    private var isConnected: Bool {
        if case .connected = session.connection { return true }
        return false
    }

    var body: some View {
        PageList {
            if !isConnected {
                Section {
                    EmptyState(title: "Connect to this host to configure voice.")
                        .frame(minHeight: 180)
                        .panelRow(Palette.background)
                }
            } else if !voice.supportsSpeechSettings {
                Section {
                    EmptyState(title: "Update the host to configure voice.")
                        .frame(minHeight: 180)
                        .panelRow(Palette.background)
                }
            } else if let speech {
                dictationSection(speech)
                voiceModeSection(speech)
                if let error = voice.error {
                    Section {
                        InlineBanner(
                            .failure, title: error,
                            action: ("Try again", { Task { await session.hostSettings.load() } }))
                            .panelRow(Palette.background)
                    }
                }
            } else {
                Section {
                    LoadingState("Loading…")
                        .frame(minHeight: 160)
                        .panelRow(Palette.background)
                }
            }
        }
        .inlinePageTitle("Voice")
        .refreshable { await session.hostSettings.load() }
        .sheet(
            isPresented: Binding(
                get: { openSite != nil },
                set: { if !$0 { openSite = nil } })
        ) {
            if let siteID = openSite {
                SpeechProviderSheet(session: session, siteID: siteID)
                    .id(siteID.rawValue)
            }
        }
        .task {
            await voice.loadModels()
        }
        .onDisappear {
            voice.stopModelPolling()
        }
    }

    // MARK: Sections

    private func dictationSection(_ speech: SpeechSettings) -> some View {
        Section {
            featureSwitchRow(
                "Dictation",
                hint: "Speak into the message box instead of typing",
                envVar: voice.envOverrides["features.dictation.enabled"],
                value: speech.dictationEnabled,
                onChange: { enabled in
                    Task { _ = await voice.setDictationEnabled(enabled) }
                },
                identifier: "settings.voice.dictation.enabled")
            siteRow(.dictationSTT, "Speech-to-text")
        } header: {
            Text("Dictation")
        }
    }

    private func voiceModeSection(_ speech: SpeechSettings) -> some View {
        Section {
            featureSwitchRow(
                "Voice mode",
                hint: "Talk with your agents hands-free",
                envVar: voice.envOverrides["features.voiceMode.enabled"],
                value: speech.voiceModeEnabled,
                onChange: { enabled in
                    Task { _ = await voice.setVoiceModeEnabled(enabled) }
                },
                identifier: "settings.voice.voiceMode.enabled")
            siteRow(.voiceModeSTT, "Listening")
            siteRow(.voiceModeTTS, "Speaking")
        } header: {
            Text("Voice mode")
        } footer: {
            Text("Voice mode transcribes what you say and reads agent replies aloud.")
        }
    }

    // MARK: Rows

    private func featureSwitchRow(
        _ title: String, hint: String, envVar: String?, value: Bool,
        onChange: @escaping (Bool) -> Void, identifier: String
    ) -> some View {
        ListRow(
            title: title,
            subtitle: envVar.map { "Set by \($0)" } ?? hint,
            accessory: ListRow.Accessory.toggle(
                Binding(
                    get: { value },
                    set: { newValue in
                        Haptics.selection()
                        onChange(newValue)
                    }))
        )
        .panelRow()
        .disabled(envVar != nil || session.hostSettings.isSaving)
        .accessibilityIdentifier(identifier)
    }

    private func siteRow(_ siteID: SpeechSiteID, _ title: String) -> some View {
        let summary = voice.summary(for: siteID)
        let disabled = summary == .unknown(provider: voice.site(siteID)?.provider.wireValue ?? "")
            || voice.site(siteID)?.provider.isKnown == false
        return ListRow(
            title: title,
            subtitle: summaryLabel(summary),
            accessory: ListRow.Accessory.chevron,
            action: {
                openSite = siteID
            }
        )
        .panelRow()
        .disabled(disabled)
        .accessibilityIdentifier("settings.voice.site." + siteID.accessibilityID)
    }

    private func summaryLabel(_ summary: SpeechSiteSummary?) -> String {
        switch summary {
        case .local(let model):
            if let model { return "Local · \(model)" }
            return "Local"
        case .openAI(let model, let missingKey):
            return "OpenAI · \(missingKey ? "API key missing" : model)"
        case .unknown(let provider):
            return "Update the app to configure \(provider)"
        case nil:
            return "Local"
        }
    }
}
#endif
