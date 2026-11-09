import Testing

import PaseoProtocol

/// U3: the daemon matches hello capability names exactly
/// (`packages/protocol/src/client-capabilities.ts`: `providerSubagents: "provider_subagents"`).
/// A camelCase key passes the hello schema's `passthrough()` and is then never read, so provider
/// subagent updates were never pushed and the chat's subagent pill never appeared.
@Suite struct ProviderSubagentCapabilityTests {
    @Test func advertisesTheDaemonsSnakeCaseCapability() {
        #expect(ClientCapabilities.providerSubagents == "provider_subagents")
        #expect(ClientCapabilities.implemented["provider_subagents"] == true)
    }
}
