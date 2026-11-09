import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Forge issue/PR search for the composer's "Add issue or PR" picker.
///
/// Transport follows upstream's `use-forge-search-query.ts`: with
/// `features.forgeSearch` the modern `forge.search.request`; without it the legacy
/// `github_search_request` (COMPAT githubSearchRpc), whose legacy kind spellings and
/// `featuresEnabled` auth fallback are normalized here exactly as upstream normalizes them
/// (`pr` → `change_request`; `github-issue` → `issue`; features disabled means
/// unauthenticated, enabled means authenticated unless `authState` says otherwise).
/// `authState` is opaque on the wire: unrecognised values stay `.unknown`, never a crash.
///
/// IMPLEMENTATION TICKET: docs/tickets/M12-forge-attach-sound.md
@MainActor @Observable
public final class ForgeSearchStore {
    /// `features.forgeSearch` (COMPAT forgeSearch). False means the legacy GitHub RPC.
    public private(set) var supportsForgeSearch = false
    /// Last transport failure, for the picker's error state. Response-level `error`
    /// fields come back inside the payload instead (upstream shows those in place).
    public private(set) var error: String?

    private let client: any DaemonClient

    public init(client: any DaemonClient) {
        self.client = client
    }

    /// One search, normalized across both transports. Returns nil only on transport
    /// failure, with `error` set; a daemon-reported failure returns its payload.
    public func search(
        cwd: String, query: String, kinds: [ForgeSearchItem.Kind]? = nil, limit: Int = 20
    ) async -> ForgeSearchResult? {
        do {
            if supportsForgeSearch {
                let response = try await client.send(
                    ForgeSearchRequest(
                        cwd: cwd, query: query, limit: limit,
                        kinds: kinds?.map(\.wireValue)))
                error = nil
                return ForgeSearchResult(
                    items: response.items,
                    authState: ForgeAuthState(raw: response.authState?.stringValue) ?? .unauthenticated,
                    error: response.error)
            }
            let response = try await client.send(
                GitHubSearchRequest(
                    cwd: cwd, query: query, limit: limit,
                    kinds: kinds?.map(\.legacyWireValue)))
            error = nil
            let featuresEnabled = response.featuresEnabled ?? response.githubFeaturesEnabled ?? true
            let authState: ForgeAuthState
            if let wire = response.authState?.stringValue, !wire.isEmpty {
                authState = ForgeAuthState(raw: wire) ?? .unauthenticated
            } else {
                authState = featuresEnabled ? .authenticated : .unauthenticated
            }
            return ForgeSearchResult(
                items: response.items, authState: authState, error: response.error)
        } catch {
            self.error = forgeSearchErrorText(error)
            return nil
        }
    }

    // MARK: HostSession handoff

    /// Called once per `server_info`; the capability is read here and nowhere else.
    internal func serverInfoChanged(_ info: ServerInfo?) {
        guard let info else { return }
        supportsForgeSearch = info.hasFeature("forgeSearch")
    }
}

/// The normalized search outcome both transports produce.
public struct ForgeSearchResult: Sendable, Hashable {
    public var items: [ForgeSearchItem]
    public var authState: ForgeAuthState
    public var error: String?

    public init(items: [ForgeSearchItem], authState: ForgeAuthState, error: String?) {
        self.items = items
        self.authState = authState
        self.error = error
    }
}

/// One readable line for an error.
private func forgeSearchErrorText(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}
