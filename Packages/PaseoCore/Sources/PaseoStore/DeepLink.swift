import Foundation
import PaseoKit

// M20: the `paseo://` links this client understands, parsed as pure values so the app and the
// tests share one definition. Upstream routes live in `packages/app/src/utils/host-routes.ts`
// (`parseHostAgentRouteFromPathname`, `parseHostWorkspaceRouteFromPathname`,
// `parseWorkspaceOpenIntent`) and `packages/protocol/src/agent-deep-link.ts`
// (`parseAgentDeepLink`, `buildAgentDeepLink`).
//
// The credential link shapes (`#offer=`, `#connect=`, `relay://`) are already validated by
// `ConnectionOffer` (R17/R18); this parser only classifies them so the app can hand one to the
// existing confirmation sheet. A link is never logged, persisted or put in an error.

/// One workspace-open intent from upstream's `?open=` query (host-routes.ts:127-173).
public enum WorkspaceOpenIntent: Sendable, Equatable {
    case agent(String)
    case terminal(String)
    case file(String)
    case draft(String)
    case setup(String)
}

/// A parsed `paseo://` link, or a pairing-offer link in any of its three shapes.
public enum DeepLink: Sendable, Equatable {
    /// `#offer=`, `#connect=` or `relay://` — the credential; route it to the pairing flow.
    case offer(ConnectionOffer)
    /// `/open-project` or `/h/<serverID>/open-project`. `serverID` is present on host routes.
    case openProject(serverID: String?)
    /// `/h/<serverID>/agent/<agentID>`.
    case agent(serverID: String, agentID: String)
    /// `/h/<serverID>/workspace/<workspaceID>` with its optional `?open=` intent.
    case workspace(serverID: String, workspaceID: String, open: WorkspaceOpenIntent?)
    /// `/h/<serverID>` — the host's own root (upstream redirects to the last workspace).
    case host(serverID: String)
    /// A route upstream has but this client does not (sessions, settings, schedules, new, welcome,
    /// plugin surfaces). Carries the route slug for a plain message, never the whole link.
    case unsupported(String)

    // MARK: Parsing

    /// Parse an incoming URL (the `.onOpenURL` entry point). Malformed or unknown links are nil:
    /// they are ignored rather than surfaced.
    public init?(url: URL) {
        guard let link = DeepLink.parse(url.absoluteString) else { return nil }
        self = link
    }

    /// Parse a pasted or scanned string.
    public init?(string: String) {
        guard let link = DeepLink.parse(string) else { return nil }
        self = link
    }

    /// The daemon identity a navigation link targets, when it names one (upstream always names
    /// one for agent and workspace routes; `open-project` may not).
    public var targetServerID: String? {
        switch self {
        case .agent(let serverID, _), .workspace(let serverID, _, _), .host(let serverID):
            return serverID
        case .openProject(let serverID):
            return serverID
        case .offer, .unsupported:
            return nil
        }
    }

    /// Navigation links (agent, workspace, host root, open project) route inside a shell.
    /// Offers go to the pairing flow; unsupported routes only get a message.
    public var isNavigation: Bool {
        switch self {
        case .offer, .unsupported:
            return false
        case .agent, .workspace, .host, .openProject:
            return true
        }
    }

    private static func parse(_ raw: String) -> DeepLink? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Credential shapes first: a base URL with a fragment, or a relay URI. The offer parser
        // validates every field; a bad one is ignored instead of becoming a saved host.
        if trimmed.contains(ConnectionOffer.offerFragmentPrefix)
            || trimmed.contains(ConnectionOffer.connectFragmentPrefix)
            || trimmed.hasPrefix(ConnectionOffer.relayURIScheme)
        {
            guard let offer = try? ConnectionOffer(link: trimmed) else { return nil }
            return .offer(offer)
        }

        guard let route = paseoRoute(trimmed) else { return nil }
        return deepLink(for: route)
    }

    // MARK: paseo:// route

    private struct PaseoRoute {
        /// Authority slug, lowercased (`h` for host routes, a screen name otherwise, or empty).
        var host: String
        /// Percent-decoded path segments, empty ones dropped.
        var segments: [String]
        /// Raw query (no `?`), still percent-encoded.
        var query: String?
    }

    /// Manual parsing on purpose: `URL` decodes `%2F` into a path separator, and upstream's
    /// routes keep a server or agent id containing a slash inside one segment
    /// (`agent-deep-link.test.ts:13-17`).
    private static func paseoRoute(_ string: String) -> PaseoRoute? {
        guard string.lowercased().hasPrefix("paseo:") else { return nil }
        var remainder = string.dropFirst("paseo:".count)
        if remainder.hasPrefix("//") {
            remainder = remainder.dropFirst(2)
        } else if remainder.hasPrefix("/") {
            remainder = remainder.dropFirst()
        }

        let authorityEnd =
            remainder.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" })
            ?? remainder.endIndex
        let authority = String(remainder[remainder.startIndex..<authorityEnd])
        remainder = remainder[authorityEnd...]

        // Upstream's `new URL(...)` parser refuses userinfo and an explicit port for the agent
        // route; the same rule applied to every paseo route keeps this parser honest.
        guard !authority.contains("@"), !authority.contains(":") else { return nil }
        // Navigation links carry no fragment (the fragment is where offers live).
        guard !remainder.contains("#") else { return nil }

        var pathPart = remainder[...]
        var query: String?
        if let question = remainder.firstIndex(of: "?") {
            pathPart = remainder[remainder.startIndex..<question]
            query = String(remainder[remainder.index(after: question)...])
            if query?.isEmpty == true { query = nil }
        }

        var segments: [String] = []
        for rawSegment in pathPart.split(separator: "/", omittingEmptySubsequences: true) {
            // Invalid percent escapes are a malformed link, same as upstream's decodeURIComponent
            // throwing in `parseAgentDeepLink`.
            guard let decoded = String(rawSegment).removingPercentEncoding else { return nil }
            segments.append(decoded.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return PaseoRoute(host: authority.lowercased(), segments: segments, query: query)
    }

    private static func deepLink(for route: PaseoRoute) -> DeepLink? {
        switch route.host {
        case "h":
            return hostRoute(route)
        case "":
            guard let screen = route.segments.first else { return nil }
            return screenRoute(screen, serverID: nil)
        default:
            // `paseo://open-project` / `paseo://settings` style links (the screen is the
            // authority when there is no `/h/` prefix).
            return screenRoute(route.host, serverID: nil)
        }
    }

    private static func screenRoute(_ screen: String, serverID: String?) -> DeepLink? {
        switch screen {
        case "open-project":
            return .openProject(serverID: serverID)
        case "new", "sessions", "schedules", "settings", "welcome", "plugin":
            return .unsupported(screen)
        default:
            return nil
        }
    }

    private static func hostRoute(_ route: PaseoRoute) -> DeepLink? {
        guard let serverID = route.segments.first, !serverID.isEmpty else { return nil }
        let rest = Array(route.segments.dropFirst())
        guard let section = rest.first else { return .host(serverID: serverID) }

        switch section {
        case "agent":
            // Upstream's strict agent route: exactly one id and no query.
            guard rest.count == 2, route.query == nil else { return nil }
            let agentID = rest[1]
            guard !agentID.isEmpty else { return nil }
            return .agent(serverID: serverID, agentID: agentID)
        case "workspace":
            guard rest.count == 2 else { return nil }
            guard let workspaceID = decodeWorkspaceID(rest[1]) else { return nil }
            let open = parseOpenIntent(queryValue(route.query, "open"))
            return .workspace(serverID: serverID, workspaceID: workspaceID, open: open)
        case "open-project":
            guard rest.count == 1 else { return nil }
            return .openProject(serverID: serverID)
        case "sessions", "settings", "plugin":
            return .unsupported(section)
        default:
            return nil
        }
    }

    // MARK: ?open= intent

    private static func parseOpenIntent(_ raw: String?) -> WorkspaceOpenIntent? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = normalized.firstIndex(of: ":") else { return nil }
        let kind = String(normalized[normalized.startIndex..<separator])
        let payload = String(normalized[normalized.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return nil }

        switch kind {
        case "agent": return .agent(payload)
        case "terminal": return .terminal(payload)
        case "draft": return .draft(payload)
        case "file":
            guard let path = strictBase64URLString(payload) else { return nil }
            return .file(path)
        case "setup":
            guard let workspaceID = decodeWorkspaceID(payload) else { return nil }
            return .setup(workspaceID)
        default:
            return nil
        }
    }

    private static func queryValue(_ query: String?, _ name: String) -> String? {
        guard let query, !query.isEmpty else { return nil }
        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = parts.first else { continue }
            // URLSearchParams (what upstream uses) decodes `+` as a space in query values.
            guard let key = decodeQueryComponent(String(rawKey)), key == name else { continue }
            return decodeQueryComponent(parts.count > 1 ? String(parts[1]) : "")
        }
        return nil
    }

    private static func decodeQueryComponent(_ value: String) -> String? {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }

    // MARK: Workspace ids and paths (upstream host-routes.ts:192-253)

    /// `decodeWorkspaceIdFromPathSegment`: a `b64_`-prefixed id is decoded; older path-shaped ids
    /// were base64url of the path, so those are recovered too; anything else is the id verbatim.
    static func decodeWorkspaceID(_ raw: String) -> String? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if normalized.hasPrefix("b64_") {
            let payload = String(normalized.dropFirst(4))
            guard let decoded = strictBase64URLString(payload) ?? relaxedBase64URLString(payload)
            else { return nil }
            let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        for decoded in [strictBase64URLString(normalized), relaxedBase64URLString(normalized)] {
            if let decoded, isCleanLegacyPath(decoded) { return decoded }
        }
        return normalized
    }

    private static func isCleanLegacyPath(_ value: String) -> Bool {
        guard value.contains("/") || value.contains("\\") else { return false }
        for scalar in value.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F || scalar.value == 0xFFFD {
                return false
            }
        }
        return true
    }

    private static func isBase64URLCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber || character == "-" || character == "_"
    }

    private static func base64URLData(_ value: String) -> Data? {
        guard !value.isEmpty, value.allSatisfy(isBase64URLCharacter) else { return nil }
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        if padding > 0 { base64 += String(repeating: "=", count: padding) }
        return Data(base64Encoded: base64)
    }

    private static func base64URLString(_ value: String) -> String? {
        guard let data = value.data(using: .utf8) else { return nil }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Upstream's `tryDecodeBase64UrlNoPadUtf8`: the decoded string must re-encode to the input,
    /// so ordinary ids like `workspace-1` are not mistaken for base64.
    private static func strictBase64URLString(_ value: String) -> String? {
        guard let data = base64URLData(value),
            let decoded = String(data: data, encoding: .utf8),
            base64URLString(decoded) == value
        else { return nil }
        return decoded
    }

    private static func relaxedBase64URLString(_ value: String) -> String? {
        guard let data = base64URLData(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Which host a link needs

/// A saved host as the deep-link router sees it (see `SavedHosts` in `App/`).
public struct DeepLinkHost: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let label: String
    /// Relay hosts carry the daemon identity; direct hosts saved before R18 may not.
    public let serverID: String?
    /// The saved endpoint, shown when there is no server id.
    public let url: String
    public let isRelay: Bool
    public let isCurrent: Bool
    /// Upstream puts the local daemon first (`orderHostsLocalFirst`,
    /// `types/host-connection.ts:97-115`). On iOS "local" means a loopback direct endpoint.
    public let isLocal: Bool

    public init(
        id: UUID, label: String, serverID: String?, url: String, isRelay: Bool, isCurrent: Bool,
        isLocal: Bool
    ) {
        self.id = id
        self.label = label
        self.serverID = serverID
        self.url = url
        self.isRelay = isRelay
        self.isCurrent = isCurrent
        self.isLocal = isLocal
    }

    public init(saved: SavedHost, isCurrent: Bool, liveServerID: String? = nil) {
        self.init(
            id: saved.id, label: saved.label, serverID: saved.serverID ?? liveServerID,
            url: saved.url, isRelay: saved.isRelay, isCurrent: isCurrent,
            isLocal: DeepLinkHost.isLocal(saved))
    }

    /// The line under the label: the daemon identity when there is one, else the endpoint.
    public var detail: String { serverID ?? url }

    private static func isLocal(_ saved: SavedHost) -> Bool {
        if let serverID = saved.serverID, serverID.hasPrefix("local:") { return true }
        guard let host = URL(string: saved.url)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    // MARK: Chooser ordering and search (upstream hosts/host-chooser.tsx:43-101)

    /// Stable local-first order: move the first local host to the front, keep the rest in order.
    public static func localFirst(_ hosts: [DeepLinkHost]) -> [DeepLinkHost] {
        guard let index = hosts.firstIndex(where: { $0.isLocal }), index > 0 else { return hosts }
        var ordered = hosts
        let local = ordered.remove(at: index)
        ordered.insert(local, at: 0)
        return ordered
    }

    /// Label or server id, case-insensitive substring; empty query matches everything.
    public static func matches(_ host: DeepLinkHost, query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        if host.label.lowercased().contains(normalized) { return true }
        return host.serverID?.lowercased().contains(normalized) ?? false
    }
}

/// What opening a navigation link needs from the saved-host list.
public enum DeepLinkHostResolution: Sendable, Equatable {
    /// Use this host; it is the current one or must be connected first.
    case target(DeepLinkHost)
    /// The link names no host and more than one is saved: ask (upstream `useHostChooser`).
    case chooseHost([DeepLinkHost])
    /// A host route names a daemon that is not saved on this device.
    case unknownHost(String)
    /// The link needs a host and none is saved.
    case noHosts
}

public enum DeepLinkRouter {
    /// Resolves the host for a navigation link (`nil` for offers and unsupported routes).
    /// Upstream: `useHostChooser` (`hosts/host-chooser.tsx:55-96`) for host-less flows, and
    /// `agentPanel.unavailable.unknownHost` when a named host is not configured (en.ts:266-268).
    public static func resolveHost(
        for link: DeepLink, savedHosts: [DeepLinkHost]
    ) -> DeepLinkHostResolution? {
        guard link.isNavigation else { return nil }
        if let serverID = link.targetServerID {
            if let match = savedHosts.first(where: { $0.serverID == serverID }) {
                return .target(match)
            }
            return .unknownHost(serverID)
        }
        let ordered = DeepLinkHost.localFirst(savedHosts)
        switch ordered.count {
        case 0: return .noHosts
        case 1: return .target(ordered[0])
        default: return .chooseHost(ordered)
        }
    }
}
