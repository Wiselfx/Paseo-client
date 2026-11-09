import Foundation
import Observation
import PaseoProtocol

/// The conversation's prompt outline: every user prompt the daemon knows, loaded or not.
///
/// Port of upstream's chat-outline hook (`packages/app/src/agent-stream/chat-outline/`): the
/// daemon indexes the whole conversation (`agent.timeline.list_prompts`), the client refetches that
/// index when the newest loaded prompt changes, drops stale answers, and resolves the prompt the
/// reader is inside from their reading position. The rail and "Jump to message" both read it, so
/// neither ever pages all of history in.
///
/// Owned by `ConversationStore` as `promptOutline`.
@MainActor @Observable
public final class PromptOutline {
    public typealias Prompt = AgentTimelinePromptIndexRequest.Response.Prompt

    /// Every prompt, oldest first. Empty until the first accepted index (or when unsupported).
    public private(set) var prompts: [Prompt] = []
    /// Timeline identity the prompts describe. Nil while there is no index.
    public private(set) var epoch: String?
    public private(set) var isLoading = false
    /// Last index failure, for the sheet. Cleared by the next accepted index.
    public private(set) var error: String?
    /// The prompt whose turn holds the reading position (`resolveActiveSeq`). Nil before any report.
    public private(set) var activeSeq: Int?
    /// Whether this daemon serves the prompt index (`features.agentTimelinePromptIndex`).
    public private(set) var isSupported = false

    private let agentId: String
    private let client: (any DaemonClient)?
    /// The last reading position the transcript reported, kept so a late index can resolve it.
    private var readingAnchorSeq: Int?
    private var lastTimelineEpoch: String?
    private var latestSeqAtLastFetch: Int?
    private var requestId = 0

    init(agentId: String, client: (any DaemonClient)?) {
        self.agentId = agentId
        self.client = client
    }

    // MARK: Pure rules (tested directly)

    /// An index describes one timeline epoch; a different one belongs to a replaced timeline.
    /// Upstream `shouldAcceptPromptIndexEpoch` (`chat-outline/model.ts:5-7`).
    public nonisolated static func shouldAccept(timelineEpoch: String?, indexEpoch: String) -> Bool {
        timelineEpoch == indexEpoch
    }

    /// The last indexed prompt at or before the timeline position under the top of the viewport.
    /// Upstream `resolveActivePromptSeq` (`chat-outline/model.ts:33-50`): it reads the complete
    /// index, so a prompt outside the loaded window still lights up while its turn is on screen.
    public nonisolated static func resolveActiveSeq(prompts: [Prompt], anchorSeq: Int?) -> Int? {
        guard let anchorSeq else { return nil }
        var active: Int?
        for prompt in prompts {
            if prompt.seq > anchorSeq { break }
            active = prompt.seq
        }
        return active
    }

    /// The daemon's preview: whitespace collapsed, at most `previewMaxLength` characters with an
    /// ellipsis. Used for the loaded-turns fallback so both sources read the same
    /// (`timeline-prompt-index.ts:14-22`).
    public nonisolated static func previewText(_ text: String) -> String {
        // The daemon's own cut (`timeline-prompt-index.ts:3`).
        let maxLength = 120
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength - 1)) + "…"
    }

    // MARK: Store plumbing

    /// Called once per `server_info` and when a conversation opens.
    internal func update(serverInfo info: ServerInfo?) {
        isSupported = info?.hasFeature("agentTimelinePromptIndex") ?? false
        guard !isSupported else { return }
        prompts = []
        epoch = nil
        activeSeq = nil
        error = nil
        isLoading = false
        // Never answer a request from a previous capability state.
        requestId += 1
    }

    /// The timeline changed (new rows, new epoch). Refetch when the newest loaded prompt moved —
    /// upstream's `latestPromptSeq` dependency (`use-chat-outline.ts:105-145`) — because a new
    /// prompt means the index is stale.
    internal func timelineChanged(epoch: String?, latestPromptSeq: Int?) {
        guard epoch != lastTimelineEpoch else {
            latestPromptSeqChanged(latestPromptSeq, timelineEpoch: epoch)
            return
        }
        lastTimelineEpoch = epoch
        latestSeqAtLastFetch = latestPromptSeq
        prompts = []
        self.epoch = nil
        activeSeq = nil
        error = nil
        refresh(timelineEpoch: epoch)
    }

    private func latestPromptSeqChanged(_ seq: Int?, timelineEpoch: String?) {
        guard seq != latestSeqAtLastFetch else { return }
        latestSeqAtLastFetch = seq
        refresh(timelineEpoch: timelineEpoch)
    }

    /// Fetches the whole index. Fire-and-forget: the transcript keeps rendering while it lands.
    ///
    /// A response is accepted only while it is the newest request (`requestId`) and only when it
    /// describes the epoch the request was made against (`shouldAccept`); anything else is
    /// dropped, exactly like upstream's effect cleanup.
    public func refresh(timelineEpoch: String?) {
        guard isSupported, client != nil, let timelineEpoch, !timelineEpoch.isEmpty else { return }
        requestId += 1
        let id = requestId
        isLoading = true
        Task { await self.load(id: id, timelineEpoch: timelineEpoch) }
    }

    private func load(id: Int, timelineEpoch: String) async {
        guard let client else { return }
        let result: Result<AgentTimelinePromptIndexRequest.Response, Error>
        do {
            result = .success(try await client.send(AgentTimelinePromptIndexRequest(agentId: agentId)))
        } catch {
            result = .failure(error)
        }
        // A stale answer (a newer request started, or the capability went away) is dropped.
        guard id == requestId else { return }
        isLoading = false
        switch result {
        case .success(let response):
            if let message = response.error {
                error = message
                return
            }
            guard Self.shouldAccept(timelineEpoch: timelineEpoch, indexEpoch: response.epoch)
            else { return }
            prompts = response.prompts
            epoch = response.epoch
            error = nil
            activeSeq = Self.resolveActiveSeq(prompts: prompts, anchorSeq: readingAnchorSeq)
        case .failure(let cause):
            error = conversationErrorText(cause)
        }
    }

    /// The transcript's reading position as a timeline seq. Called on scroll frames; a late index
    /// resolves it again so the rail marks a tick even before the outline arrives.
    public func reportReadingPosition(anchorSeq: Int?) {
        readingAnchorSeq = anchorSeq
        let resolved = Self.resolveActiveSeq(prompts: prompts, anchorSeq: anchorSeq)
        if resolved != activeSeq { activeSeq = resolved }
    }
}
