import Foundation
import Observation
import PaseoKit
import PaseoProtocol

// T16: provider plan usage reports ("account-level quotas") and how the host sees them.
// Source: `usage.list_reports.request` → one `usage.list_reports.update` per report, then
// `usage.list_reports.response`; older hosts without `features.usageSources` serve a five-minute
// cached `provider.usage.list.request/response` instead, which this store maps onto the same
// report entries. Gated on `features.usageSources || features.providerUsageList` (client:
// `supportsUsageReports`) and on the host's own `usage.enabled` policy (read fresh per load).

@MainActor @Observable
public final class HostUsageStore {
    public enum Phase: Sendable, Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    /// The host's usage reports, in arrival order; replaced atomically on each load.
    public private(set) var reports: [UsageReportEntry] = []
    /// What went wrong with the last load, if anything. Cleared on the next load.
    public private(set) var error: String?
    /// `features.usageSources === true || features.providerUsageList === true`. Set once per
    /// `server_info`.
    public private(set) var isSupported = false
    /// `config.usage.enabled` from the daemon's own policy, read fresh per load. `true` until
    /// the first load (and when the config cannot be read, which fails open).
    public private(set) var usageEnabled = true
    /// When the host last answered the usage question — a `.ready` load, or its own policy saying
    /// usage is off — nil until then. The sidebar uses it to throttle its drawer-open refresh
    /// (H4 §2). A failed load (transport, correlation, timeout) never moves it, so a failure is
    /// retried the next time the drawer opens.
    public private(set) var lastLoadedAt: Date?

    /// The shortest gap between two automatic loads. One value for every caller: a drawer open is
    /// a cheap question, but a host's plan quotas move in minutes, not seconds.
    public static let automaticRefreshInterval: TimeInterval = 60

    /// The line the sidebar footer shows when the host advertises no usage support at all. One
    /// copy of the string: `load()` refuses with the same words.
    public static let unsupportedMessage = "This host does not report usage; update the host."

    /// True when an automatic load is worth doing: the host supports usage, none is in flight, and
    /// either the host has not answered yet or it answered at least `minimumInterval` ago. Callers
    /// gate on the user's own toggle; this store never decides to load on its own.
    public func needsAutomaticLoad(
        now: Date = Date(),
        minimumInterval: TimeInterval = HostUsageStore.automaticRefreshInterval
    ) -> Bool {
        guard isSupported, phase != .loading else { return false }
        guard let lastLoadedAt else { return true }
        return now.timeIntervalSince(lastLoadedAt) >= minimumInterval
    }

    private let client: any DaemonClient
    private var pendingReports: PendingLoad?

    private struct PendingLoad {
        let requestId: String
        var reports: [UsageReportEntry] = []
    }

    public init(client: any DaemonClient) {
        self.client = client
    }

    /// Loads the host's usage reports. On modern hosts the daemon streams one update per
    /// report followed by a correlated response; on legacy hosts it serves a cached per-provider
    /// snapshot, which is mapped onto the same entries. Returns true on success.
    public func load(forceRefresh: Bool = false) async -> Bool {
        guard isSupported else {
            phase = .failed(Self.unsupportedMessage)
            return false
        }
        phase = .loading
        error = nil

        // The host owns its policy; ask the daemon what is enabled before asking for reports.
        if let config = try? await client.send(GetDaemonConfigRequest()).config {
            usageEnabled = config.usage?.enabled ?? true
            guard usageEnabled else {
                phase = .failed("Usage is off on this host. Ask the daemon to turn it on.")
                // The host answered the question. The throttle applies, so opening the drawer does
                // not re-ask a policy that changes on the host's own schedule.
                lastLoadedAt = Date()
                return false
            }
        } else {
            // Cannot read the config — try anyway and let the reports socket answer.
            usageEnabled = true
        }

        if isUsageSourcesModern {
            await streamReports(forceRefresh: forceRefresh)
        } else {
            await legacyReports()
        }
        if phase == .ready { lastLoadedAt = Date() }
        return phase == .ready
    }

    private var isUsageSourcesModern = false

    /// One `usage.list_reports.update` from the daemon; only events for the in-flight request count.
    internal func handle(messageType: String, raw: Data) {
        guard messageType == "usage.list_reports.update" else { return }
        guard let pending = pendingReports,
            let update = try? JSONDecoder().decode(
                SessionPayloadEnvelope<UsageListReportsUpdate>.self, from: raw).payload,
            update.requestId == pending.requestId
        else { return }
        pendingReports?.reports.append(update.report)
    }

    internal func update(serverInfo info: ServerInfo?) {
        guard let info else { return }
        isUsageSourcesModern = info.hasFeature("usageSources")
        isSupported = isUsageSourcesModern || info.hasFeature("providerUsageList")
    }

    // MARK: Modern path

    private func streamReports(forceRefresh: Bool) async {
        var request = UsageListReportsRequest()
        request.requestId = UUID().uuidString
        request.forceRefresh = forceRefresh
        pendingReports = PendingLoad(requestId: request.requestId)
        defer { pendingReports = nil }

        do {
            let response = try await client.send(request)
            let collected = pendingReports?.reports ?? []
            if let error = response.error {
                self.error = error
                phase = .failed(error)
                return
            }
            reports = collected
            phase = .ready
        } catch {
            fail(error)
        }
    }

    // MARK: Legacy path (provider.usage.list, pre-usageSources hosts)

    private func legacyReports() async {
        do {
            let response = try await client.send(ProviderUsageListRequest())
            reports = response.providers.map { legacyEntry($0, fetchedAt: response.fetchedAt) }
            phase = .ready
        } catch {
            fail(error)
        }
    }

    private func legacyEntry(_ provider: ProviderUsage, fetchedAt: String) -> UsageReportEntry {
        let report: UsageReport
        switch provider.status {
        case .available:
            report = .available(
                AvailableUsageReport(
                    planLabel: provider.planLabel,
                    windows: provider.windows,
                    balances: provider.balances,
                    details: provider.details))
        case .error:
            report = .failure(error: provider.error ?? "")
        case .unavailable, .unknown(_):
            report = .unavailable(problem: .noQuota(detail: provider.error ?? ""))
        }
        return UsageReportEntry(
            id: provider.providerId,
            accountLabel: nil,
            fetchedAt: provider.fetchedAt ?? fetchedAt,
            sourceId: provider.providerId,
            sourceLabel: provider.displayName,
            icon: nil,
            report: report)
    }

    /// One failure path for both transports. A cancellation is not a failure: the caller withdrew
    /// (the sidebar's `.task(id:)` was replaced, the sheet closed), so the store goes back to idle
    /// and the next trigger loads again instead of showing an error the user never caused.
    private func fail(_ error: Error) {
        if error is CancellationError || Task.isCancelled {
            phase = .idle
            return
        }
        let message = hostUsageErrorText(error)
        self.error = message
        phase = .failed(message)
    }

    private func hostUsageErrorText(_ error: Error) -> String {
        switch error {
        case ConnectionError.disconnected: "Lost the connection to the daemon."
        case ConnectionError.timeout: "The daemon did not answer in time."
        case ConnectionError.protocolViolation(let message): "Unexpected reply from the daemon: \(message)"
        default: String(describing: error)
        }
    }
}
