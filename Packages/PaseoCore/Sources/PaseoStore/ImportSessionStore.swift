import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Listing and importing recent provider sessions from the host (`fetch_recent_provider_sessions_*`
/// + `import_agent_request`), as upstream's import sheet does
/// (`packages/app/src/components/import-session-sheet.tsx` + `import-session-sheet-view-model.ts`):
/// one list request per enabled provider, aggregated newest-first and de-duplicated by
/// `providerId:providerHandleId`; paging grows the per-provider limit (15 → 45 → 90 → 200)
/// instead of carrying an offset. Search (`query`) is only sent when
/// `features.importSessionSearch`; the workspace target is only sent when
/// `features.importSessionWorkspaceTarget` and the row's directory matches the workspace.
/// The base gate is `features.providersSnapshot` (older daemons get the "update host" state).
///
/// IMPLEMENTATION TICKET: docs/tickets/M11-import-session.md
@MainActor @Observable
public final class ImportSessionStore {
    public enum Phase: Sendable, Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    /// Aggregated, newest first, de-duplicated by `providerId:providerHandleId`.
    public private(set) var entries: [RecentProviderSessionDescriptor] = []
    /// One row per provider that could not list (request failure or a daemon-reported
    /// `providerErrors` entry). The sheet retries these on Refresh.
    public private(set) var providerErrors: [ProviderError] = []
    /// Sessions the daemon filtered out as already imported, summed across providers.
    public private(set) var alreadyImportedCount = 0
    /// True when a provider returned a full page and a larger limit exists (upstream
    /// `hasMoreSessions`): the sheet's Load more grows the limit.
    public private(set) var hasMore = false
    /// Last import failure ("Could not import selected session." or the daemon's error).
    public private(set) var actionError: String?
    /// The entry being imported, by descriptor id; nil when idle.
    public private(set) var importingId: String?

    /// `features.importSessionSearch`: only then is `query` sent.
    public private(set) var supportsSearch = false
    /// `features.importSessionWorkspaceTarget`: only then is `workspaceId` sent on import.
    public private(set) var supportsWorkspaceTarget = false
    /// `features.providersSnapshot`: the base gate; without it the sheet shows the
    /// "Update the host to import sessions." state instead of listing.
    public private(set) var supportsSnapshot = true

    private let client: any DaemonClient

    public init(client: any DaemonClient) {
        self.client = client
    }

    /// Per-provider page limits, upstream's `PAGE_LIMITS`.
    public static let pageLimits = [15, 45, 90, 200]

    /// The next larger page limit, or the same at the ceiling (upstream `nextPageLimit`).
    public static func nextPageLimit(_ limit: Int) -> Int {
        pageLimits.first { $0 > limit } ?? limit
    }

    /// Lists recent sessions, one request per provider, replacing what we hold.
    /// `cwd` scopes to one directory ("This workspace"); nil lists the whole host.
    /// `query` is sent only when `supportsSearch`.
    public func load(providers: [String], cwd: String?, query: String = "", limit: Int = 15) async {
        phase = .loading
        let trimmedQuery = supportsSearch ? query.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        var collected: [String: RecentProviderSessionDescriptor] = [:]
        var errors: [ProviderError] = []
        var alreadyImported = 0
        var more = false
        var failures = 0
        for provider in providers {
            do {
                let response = try await client.send(
                    FetchRecentProviderSessionsRequest(
                        cwd: cwd, providers: [provider], limit: limit,
                        query: trimmedQuery.isEmpty ? nil : trimmedQuery))
                if response.entries.count >= limit, Self.nextPageLimit(limit) != limit {
                    more = true
                }
                alreadyImported += response.filteredAlreadyImportedCount ?? 0
                for entry in response.entries where collected[entry.id] == nil {
                    collected[entry.id] = entry
                }
                for error in response.providerErrors ?? [] {
                    errors.append(ProviderError(provider: error.provider, message: error.message))
                }
            } catch {
                failures += 1
                errors.append(ProviderError(provider: provider, message: importErrorText(error)))
            }
        }
        entries = collected.values.sorted { lhs, rhs in
            (PaseoDate.parse(lhs.lastActivityAt) ?? .distantPast)
                > (PaseoDate.parse(rhs.lastActivityAt) ?? .distantPast)
        }
        providerErrors = errors
        alreadyImportedCount = alreadyImported
        hasMore = more
        if !providers.isEmpty, failures == providers.count, entries.isEmpty {
            phase = .failed(errors.first?.message ?? "Could not load sessions.")
        } else {
            phase = .ready
        }
    }

    /// Imports one session and returns the new agent, or nil with `actionError` set
    /// ("Could not import selected session." when the daemon gives no reason). Single
    /// flight: a second call while one is running returns nil immediately.
    @discardableResult
    public func importSession(
        _ entry: RecentProviderSessionDescriptor, cwd: String? = nil, workspaceId: String? = nil
    ) async -> AgentSnapshot? {
        guard importingId == nil else { return nil }
        importingId = entry.id
        defer { importingId = nil }
        do {
            let response = try await client.send(
                ImportAgentRequest(
                    providerId: entry.providerId, providerHandleId: entry.providerHandleId,
                    cwd: cwd, workspaceId: workspaceId))
            if let agent = response.agent {
                actionError = nil
                return agent
            }
            actionError = response.error ?? "Could not import selected session."
            return nil
        } catch {
            actionError = importErrorText(error)
            return nil
        }
    }

    /// The workspace id to send for one row, per upstream `resolveImportTarget`: a scoped
    /// listing is already matched by the daemon, so the id goes out; an unscoped ("Show all")
    /// listing is compared by path. Returns nil when the daemon can't take a target.
    private static func normalized(_ path: String) -> String {
        path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
    }

    public static func importTargetWorkspaceId(
        entryCwd: String, workspaceCwd: String?, workspaceId: String?,
        isScopedListing: Bool, supportsWorkspaceTarget: Bool
    ) -> String? {
        guard supportsWorkspaceTarget, let workspaceId, let workspaceCwd else { return nil }
        if isScopedListing { return workspaceId }
        return normalized(entryCwd) == normalized(workspaceCwd) ? workspaceId : nil
    }

    /// One provider that could not list its sessions.
    public struct ProviderError: Sendable, Hashable {
        public var provider: String
        public var message: String
        public init(provider: String, message: String) {
            self.provider = provider
            self.message = message
        }
    }

    // MARK: HostSession handoff

    /// Called once per `server_info`; the capability flags are read here and nowhere else.
    internal func serverInfoChanged(_ info: ServerInfo?) {
        guard let info else { return }
        supportsSearch = info.hasFeature("importSessionSearch")
        supportsWorkspaceTarget = info.hasFeature("importSessionWorkspaceTarget")
        supportsSnapshot = info.hasFeature("providersSnapshot")
    }
}

/// One readable line for an error.
private func importErrorText(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}

// MARK: - Display fallbacks (upstream `getSessionTitle` / `getPromptPreview`, en.ts wording)

public extension RecentProviderSessionDescriptor {
    /// `title`, else the first prompt, else "Untitled session".
    var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let first = firstPromptPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
            !first.isEmpty
        {
            return first
        }
        return "Untitled session"
    }

    /// The last prompt, else the first, else "No prompt preview".
    var promptPreview: String {
        if let last = lastPromptPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
            !last.isEmpty
        {
            return last
        }
        if let first = firstPromptPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
            !first.isEmpty
        {
            return first
        }
        return "No prompt preview"
    }
}
