import AppIntents
import Foundation

/// Starts a new agent draft and focuses its composer. Never sends: creation stays
/// user-driven — the draft waits for the reader.
struct NewAgentIntent: AppIntent {
    static let title: LocalizedStringResource = "New agent"
    static let description = IntentDescription("Start a new agent.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "paseo://new-agent") else {
            throw URLError(.badURL)
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}
