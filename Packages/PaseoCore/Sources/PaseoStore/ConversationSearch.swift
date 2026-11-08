import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// In-conversation search state for one agent. Search results are locations; the view scrolls to
/// the message at `seq` and verifies the occurrence count against the rendered text.
///
/// Owned by `ConversationStore` as `search`.
@MainActor @Observable
public final class ConversationSearch {
    /// The query currently shown for the last completed (or in-flight) search.
    public private(set) var query = ""
    /// Every located message, in timeline order across all fetched pages.
    public private(set) var locations: [AgentTimelineSearchRequest.Location] = []
    /// Timeline identity the locations belong to. A newer epoch means search again.
    public private(set) var epoch: String?
    /// Non-nil when the daemon capped the result set; call `loadMore()` for the next page.
    public private(set) var nextCursor: Int?
    public private(set) var isSearching = false
    /// Last search or page failure, for the find bar. Cleared by the next successful search.
    public private(set) var error: String?

    private let agentId: String
    private let client: (any DaemonClient)?

    init(agentId: String, client: (any DaemonClient)?) {
        self.agentId = agentId
        self.client = client
    }

    /// Total estimated occurrences across every located message. Older daemons omit `count`.
    public var matchCount: Int { locations.reduce(0) { $0 + ($1.count ?? 1) } }

    /// Runs a fresh search and follows `nextCursor` until the result set is complete. An empty or
    /// whitespace-only query clears the results. Failures land in `error`.
    @discardableResult
    public func search(_ query: String, followPages: Bool = true) async -> ConversationSearchResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.query = trimmed
        locations = []
        epoch = nil
        nextCursor = nil
        error = nil
        guard !trimmed.isEmpty else { return nil }
        guard let client else {
            error = "This conversation is not connected to a daemon."
            return nil
        }

        isSearching = true
        defer { isSearching = false }

        var cursor: Int?
        var expectedEpoch: String?
        while true {
            do {
                let response = try await client.send(
                    AgentTimelineSearchRequest(agentId: agentId, query: trimmed, cursor: cursor))
                if let message = response.error {
                    error = message
                    return nil
                }
                if let expectedEpoch, expectedEpoch != response.epoch {
                    error = "The conversation changed while searching. Search again."
                    return nil
                }
                expectedEpoch = response.epoch
                epoch = response.epoch
                locations.append(contentsOf: response.locations)
                guard followPages, let next = response.nextCursor, next != cursor else {
                    nextCursor = followPages ? nil : response.nextCursor
                    break
                }
                nextCursor = next
                cursor = next
            } catch let cause {
                error = conversationErrorText(cause)
                return nil
            }
        }

        return ConversationSearchResult(
            query: trimmed, epoch: epoch ?? "", locations: locations, nextCursor: nextCursor)
    }

    /// Appends the next daemon-capped page, keeping the locations already shown.
    public func loadMore() async {
        guard let client, let cursor = nextCursor, !isSearching else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let response = try await client.send(
                AgentTimelineSearchRequest(agentId: agentId, query: query, cursor: cursor))
            if let message = response.error {
                error = message
                return
            }
            if let epoch, epoch != response.epoch {
                error = "The conversation changed while searching. Search again."
                return
            }
            epoch = response.epoch
            let known = Set(locations)
            locations.append(contentsOf: response.locations.filter { !known.contains($0) })
            nextCursor = response.nextCursor == cursor ? nil : response.nextCursor
            error = nil
        } catch let cause {
            error = conversationErrorText(cause)
        }
    }

    /// Drops the results and closes the find bar.
    public func clear() {
        query = ""
        locations = []
        epoch = nil
        nextCursor = nil
        error = nil
        isSearching = false
    }
}

/// One readable line for an error in the conversation extensions.
internal func conversationErrorText(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}
