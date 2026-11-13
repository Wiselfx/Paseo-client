import Foundation
import PaseoProtocol
import Testing

/// L3 Part A: what the hello advertises. The allow-list is upstream's `CLIENT_CAPS` wire strings
/// (packages/protocol/src/client-capabilities.ts, 23 entries) plus `voice`, which upstream defines
/// in the hello schema (packages/protocol/src/messages.ts:8118) and not in `CLIENT_CAPS`.
@Suite struct HandshakeCapabilitiesTests {
    /// Upstream wire names, copied from client-capabilities.ts.
    static let upstreamNames: Set<String> = [
        "terminal_chunked_replay",
        "binary_chunking_v1",
        "hello_rejection",
        "owned_subscriptions",
        "explicit_event_subscriptions",
        "all_providers",
        "selective_agent_timeline",
        "reasoning_merge_enum",
        "custom_mode_icons",
        "terminal_reflowable_snapshot",
        "provider_subagents",
        "projected_subagent_timeline",
        "project_updates",
        "compact_provider_snapshots",
        "provider_snapshot_references",
        "timeline_replacement_invalidation",
        "timeline_notifications",
        "plugin_timeline_items",
        "workspace_setup_observation",
        "plugin_binary_payloads",
        "workspace_setup_blocked",
        "background_agents",
        "browser_host",
        "voice",
    ]

    /// The exact set this client advertises today. Changing it is a protocol decision: update this
    /// list together with the audit table above `ClientCapabilities.implemented`.
    static let advertisedNames: Set<String> = [
        "hello_rejection",
        "terminal_chunked_replay",
        "provider_subagents",
        "projected_subagent_timeline",
        "owned_subscriptions",
        "workspace_setup_observation",
        "voice",
    ]

    @Test func advertisedNamesArePinned() {
        #expect(Set(ClientCapabilities.implemented.keys) == Self.advertisedNames)
        #expect(ClientCapabilities.implemented.values.allSatisfy { $0 })
    }

    @Test func everyAdvertisedNameIsAnUpstreamWireName() {
        for name in ClientCapabilities.implemented.keys {
            #expect(Self.upstreamNames.contains(name), "\(name) is not an upstream capability")
        }
    }

    @Test func theAllowListHasTheUpstreamCount() {
        // 23 CLIENT_CAPS entries + `voice` (hello schema). The ledger's count of 22 was a grep miss.
        #expect(Self.upstreamNames.count == 24)
    }

    @Test func helloCarriesEveryAdvertisedCapabilityAsTrue() throws {
        let hello = Hello(clientId: "client-1", appVersion: "0.1.0", credential: nil)
        let data = try JSONEncoder().encode(hello)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        let capabilities = try #require(value["capabilities"])
        for name in ClientCapabilities.implemented.keys {
            #expect(capabilities[name] == .bool(true), "hello is missing \(name)")
        }
        guard case .object(let object) = capabilities else {
            Issue.record("hello capabilities is not a JSON object")
            return
        }
        #expect(Set(object.keys) == Self.advertisedNames)
    }
}
