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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !isConnected {
                    Text("Connect to this host to configure voice.")
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.secondary)
                        .padding(.top, 32)
                        .frame(maxWidth: .infinity)
                } else if !voice.supportsSpeechSettings {
                    Text("Update the host to configure voice.")
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.secondary)
                        .padding(.top, 32)
                        .frame(maxWidth: .infinity)
                } else if let speech {
                    dictationSection(speech)
                    voiceModeSection(speech)
                    if let error = voice.error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(ClaudePalette.failureInk)
                            .padding(.leading, 16)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    Text("Loading…")
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: Binding(
            get: { openSite != nil },
            set: { if !$0 { openSite = nil } })) {
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
        VStack(alignment: .leading, spacing: 18) {
            sectionLabel("Dictation")
            RowGroup {
                featureSwitchRow(
                    "Dictation",
                    hint: "Speak into the message box instead of typing",
                    envVar: voice.envOverrides["features.dictation.enabled"],
                    value: speech.dictationEnabled,
                    onChange: { enabled in
                        Task { _ = await voice.setDictationEnabled(enabled) }
                    },
                    identifier: "settings.voice.dictation.enabled")
                rowDivider
                siteRow(.dictationSTT, "Speech-to-text")
            }
        }
    }

    private func voiceModeSection(_ speech: SpeechSettings) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionLabel("Voice mode")
            RowGroup {
                featureSwitchRow(
                    "Voice mode",
                    hint: "Talk with your agents hands-free",
                    envVar: voice.envOverrides["features.voiceMode.enabled"],
                    value: speech.voiceModeEnabled,
                    onChange: { enabled in
                        Task { _ = await voice.setVoiceModeEnabled(enabled) }
                    },
                    identifier: "settings.voice.voiceMode.enabled")
                rowDivider
                siteRow(.voiceModeSTT, "Listening")
                rowDivider
                siteRow(.voiceModeTTS, "Speaking")
            }
            Text("Voice mode transcribes what you say and reads agent replies aloud.")
                .font(.system(size: 13))
                .foregroundStyle(ClaudePalette.secondary)
                .padding(.leading, 16)
        }
    }

    // MARK: Rows

    private func featureSwitchRow(
        _ title: String, hint: String, envVar: String?, value: Bool,
        onChange: @escaping (Bool) -> Void, identifier: String
    ) -> some View {
        Toggle(isOn: Binding(
            get: { value },
            set: { newValue in
                Haptics.selection()
                onChange(newValue)
            })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17))
                Text(envVar.map { "Set by \($0)" } ?? hint)
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(.blue)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .disabled(envVar != nil || session.hostSettings.isSaving)
        .accessibilityIdentifier(identifier)
    }

    private func siteRow(_ siteID: SpeechSiteID, _ title: String) -> some View {
        let summary = voice.summary(for: siteID)
        let disabled = summary == .unknown(provider: voice.site(siteID)?.provider.wireValue ?? "")
            || voice.site(siteID)?.provider.isKnown == false
        return Button {
            Haptics.selection()
            openSite = siteID
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17))
                    Text(summaryLabel(summary))
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15))
                    .foregroundStyle(ClaudePalette.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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

    // MARK: Shared bits

    private var rowDivider: some View {
        Divider().padding(.leading, 16).padding(.trailing, 16)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15))
            .foregroundStyle(ClaudePalette.secondary)
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }
}
#endif
