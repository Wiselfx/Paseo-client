import Foundation
import PaseoFixtures
import PaseoProtocol
@testable import PaseoStore

enum Load {
    static let decoder = JSONDecoder()

    static func page() throws -> FetchAgentTimelineRequest.Response {
        try decoder.decode(SessionPayloadEnvelope<FetchAgentTimelineRequest.Response>.self, from: Fixture.data("fetch_agent_timeline_response")).payload
    }

    static func stream() throws -> [AgentStreamPayload] {
        try Fixture.streamFrames().map { try decoder.decode(SessionPayloadEnvelope<AgentStreamPayload>.self, from: $0).payload }
    }

    /// The fixture page cut down to rows before `seq`, as if fetched just before the streamed turn.
    static func page(before seq: Int) throws -> FetchAgentTimelineRequest.Response {
        var page = try page()
        page.entries = page.entries.filter { $0.seqEnd < seq }
        page.window.maxSeq = seq - 1
        page.window.nextSeq = seq
        page.hasNewer = false
        return page
    }

    /// Projected entries mapped to rows without TimelineState, using the documented id rule.
    static func rows(_ entries: [TimelineEntry]) -> [TimelineRow] {
        entries.map { entry in
            let id: String = if case .toolCall(let call) = entry.item { "tool:\(call.callId)" } else { "seq:\(entry.seqStart)" }
            return TimelineRow(id: id, turnId: entry.turnId, item: entry.item, timestamp: entry.timestamp, seqStart: entry.seqStart, seqEnd: entry.seqEnd)
        }
    }
}
