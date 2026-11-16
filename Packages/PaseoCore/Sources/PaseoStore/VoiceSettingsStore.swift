import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Host Voice settings and local speech models for one daemon: the Dictation / Voice mode
/// switches, the three provider sites, and the local model catalog.
///
/// Reads/writes ride `HostSettingsStore`'s `set_daemon_config_request` patch path
/// (`DaemonConfigPatch.features`, deep-partial); the settings themselves are decoded from
/// `config.features` on every access, so a `daemon_config_changed` push is reflected with
/// no extra state here. Local model downloads report progress through the list response
/// (`LocalSpeechModel.receivedBytes`/`totalBytes`, rpc-schemas.ts list response), so while
/// any model is downloading or extracting this store polls the list once a second
/// (`use-local-speech-models.ts` upstream). There is no speech progress push on the wire
/// and no subscription family for it in `docs/research/09-owned-subscriptions.md`, so
/// polling is not a legacy fallback — it is the only mechanism, on modern sockets too.
///
/// IMPLEMENTATION TICKET: docs/tickets/M13-voice-settings.md
@MainActor @Observable
public final class VoiceSettingsStore {
    public enum ModelsPhase: Sendable, Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    /// `features.speechSettings` (messages.ts:3871): the Voice UI only exists when the
    /// daemon advertises it. Read once per `server_info`, like every capability flag.
    public private(set) var supportsSpeechSettings = false

    /// The daemon's local speech model catalog, as last loaded. Empty until `loadModels()`.
    public private(set) var models: [LocalSpeechModel] = []
    public private(set) var modelsPhase: ModelsPhase = .idle
    /// Last model-list error (nil once a load succeeds).
    public private(set) var modelsError: String?

    /// Last download/delete error per model id. Cleared by the next successful action.
    public private(set) var modelActionErrors: [String: String] = [:]

    /// Last failed settings save, mirrored from `HostSettingsStore.error`.
    public private(set) var error: String?

    private let client: any DaemonClient
    private let hostSettings: HostSettingsStore
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?

    /// True while the 1 s download-progress poll is running.
    public var isPollingModels: Bool { pollTask != nil }

    /// - Parameters:
    ///   - hostSettings: owns the daemon-config document (`config`/`envOverrides`) and the
    ///     patch RPC. This store never sends `get_daemon_config_request` itself.
    ///   - pollInterval: 1 s in the app (`DOWNLOAD_POLL_INTERVAL_MS` upstream).
    public init(
        client: any DaemonClient, hostSettings: HostSettingsStore,
        pollInterval: Duration = .seconds(1)
    ) {
        self.client = client
        self.hostSettings = hostSettings
        self.pollInterval = pollInterval
    }

    // MARK: Settings

    /// The decoded speech block, from the live host config. Nil before the config loads.
    public var speechSettings: SpeechSettings? {
        SpeechSettings(features: hostSettings.config?.features)
    }

    /// The daemon's env overrides, for "Set by …" hints and read-only fields.
    public var envOverrides: [String: String] {
        hostSettings.config?.envOverrides ?? [:]
    }

    public func site(_ siteID: SpeechSiteID) -> SpeechSite? {
        speechSettings?.site(siteID)
    }

    /// What a settings row shows for one site (model label, or OpenAI model / missing key).
    public func summary(for siteID: SpeechSiteID) -> SpeechSiteSummary? {
        guard let site = site(siteID) else { return nil }
        return summarizeSpeechSite(
            siteID: siteID, site: site, localModels: models, envOverrides: envOverrides)
    }

    /// Flips the Dictation switch. Surgical patch; unknown speech config survives.
    @discardableResult
    public func setDictationEnabled(_ enabled: Bool) async -> Bool {
        var patch = DaemonConfigPatch()
        patch.features = SpeechSettingsPatch(dictationEnabled: enabled).jsonValue
        return await saveFeatures(patch, refreshModelsAfter: false)
    }

    /// Flips the Voice mode switch.
    @discardableResult
    public func setVoiceModeEnabled(_ enabled: Bool) async -> Bool {
        var patch = DaemonConfigPatch()
        patch.features = SpeechSettingsPatch(voiceModeEnabled: enabled).jsonValue
        return await saveFeatures(patch, refreshModelsAfter: false)
    }

    /// Saves one site's provider settings (the provider sheet). Selecting a model changes
    /// which models are in use, so the catalog is re-read after a save (`voice-page.tsx`).
    @discardableResult
    public func save(siteID: SpeechSiteID, sitePatch: SpeechSitePatch) async -> Bool {
        var patch = DaemonConfigPatch()
        patch.features = SpeechSettingsPatch(siteID: siteID, patch: sitePatch).jsonValue
        return await saveFeatures(patch, refreshModelsAfter: true)
    }

    private func saveFeatures(_ patch: DaemonConfigPatch, refreshModelsAfter: Bool) async -> Bool {
        let saved = await hostSettings.save(patch)
        error = hostSettings.error
        if saved, refreshModelsAfter, modelsPhase == .ready || modelsPhase == .loading {
            await refreshModels()
        }
        return saved
    }

    // MARK: Local models

    /// Reads the local model catalog (`speech.local_models.list.request`,
    /// `daemon.read`). Starts the 1 s progress poll while any model is busy.
    public func loadModels() async {
        modelsPhase = .loading
        await refreshModels(fetching: true)
    }

    /// Starts (or restarts) a download (`daemon.manage`). Resolves when the download
    /// starts; progress arrives through the polled list.
    @discardableResult
    public func download(modelId: String) async -> Bool {
        modelActionErrors[modelId] = nil
        do {
            let response = try await client.send(SpeechLocalModelsDownloadRequest(modelId: modelId))
            if let error = response.error {
                modelActionErrors[modelId] = error
                return false
            }
            await refreshModels()
            return true
        } catch {
            modelActionErrors[modelId] = voiceSettingsErrorText(error)
            return false
        }
    }

    /// Deletes an installed model (`daemon.manage`).
    @discardableResult
    public func delete(modelId: String) async -> Bool {
        modelActionErrors[modelId] = nil
        do {
            let response = try await client.send(SpeechLocalModelsDeleteRequest(modelId: modelId))
            if let error = response.error {
                modelActionErrors[modelId] = error
                return false
            }
            await refreshModels()
            return true
        } catch {
            modelActionErrors[modelId] = voiceSettingsErrorText(error)
            return false
        }
    }

    /// The models of one kind (`"stt"` / `"tts"`), in catalog order.
    public func models(kind: SpeechModelKind) -> [LocalSpeechModel] {
        models.filter { $0.kind == kind.rawValue }
    }

    /// Stops the 1 s progress poll. Call when the Voice page goes away or the socket
    /// disconnects; `loadModels()` on the next visit restarts it if a download is live.
    public func stopModelPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func refreshModels(fetching: Bool = false) async {
        do {
            let response = try await client.send(SpeechLocalModelsListRequest())
            if let error = response.error {
                modelsError = error
                if fetching { modelsPhase = .failed(error) }
            } else {
                models = response.models
                modelsError = nil
                if fetching || modelsPhase == .loading || modelsPhase == .idle {
                    modelsPhase = .ready
                }
            }
        } catch {
            let message = voiceSettingsErrorText(error)
            if fetching { modelsPhase = .failed(message) }
            modelsError = message
        }
        startPollingIfBusy()
    }

    /// The daemon reports download progress through the list, so the list polls every
    /// `pollInterval` while any model is downloading or extracting (`use-local-speech-models.ts`
    /// upstream). Requests are plain request/response, so this works on a modern socket:
    /// no subscription is needed for a mechanism the daemon never pushes.
    private func startPollingIfBusy() {
        guard models.contains(where: isLocalModelBusy) else {
            stopModelPolling()
            return
        }
        guard pollTask == nil else { return }
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard let self else { return }
                await self.refreshModels()
                if !self.models.contains(where: isLocalModelBusy) {
                    self.stopModelPolling()
                    return
                }
            }
        }
    }

    // MARK: HostSession handoff

    /// Called once per `server_info`; the gate flag is read here and nowhere else.
    internal func serverInfoChanged(_ info: ServerInfo?) {
        supportsSpeechSettings = info?.hasFeature("speechSettings") ?? false
    }
}

/// One readable line for an error.
private func voiceSettingsErrorText(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}
