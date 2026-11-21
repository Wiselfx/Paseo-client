import AppIntents
import Foundation

/// Opens the agent in the app through the existing deep-link route. Never sends.
struct OpenAgentIntent: AppIntent {
    static let title: LocalizedStringResource = "Open agent"
    static let description = IntentDescription("Open one of your agents.")
    static let openAppWhenRun = true

    @Parameter(title: "Agent")
    var agent: AgentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$agent)")
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        guard
            let url = URL(
                string: "paseo://h/\(agent.hostServerID)/agent/\(agent.id)")
        else {
            throw URLError(.badURL)
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}
