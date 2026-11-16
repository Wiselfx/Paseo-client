import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// U5: the prompt outline (`agent.timeline.list_prompts`) and the prompt jump.
///
/// Upstream reference: `packages/app/src/agent-stream/chat-outline/` (`model.ts` for the epoch and
/// active-prompt rules, `use-chat-outline.ts` for the fetch/drop behaviour and the jump) and
/// `packages/app/src/timeline/timeline-sync-plan.ts:77-88` (`planTimelinePromptJump`).
@Suite @MainActor
struct PromptOutlineTests {
    // MARK: Fixtures

    /// A projected page of one-row entries; "user" rows become prompts, "assistant" rows prose.
    nonisolated private static func page(
        direction: String, epoch: String, rows: [(seq: Int, role: String)], hasOlder: Bool
    ) throws -> FetchAgentTimelineRequest.Response {
        let entries = rows.map { row in
            let item =
                row.role == "user"
                ? #"{"type":"user_message","text":"prompt \#(row.seq)"}"#
                : #"{"type":"assistant_message","text":"answer \#(row.seq)"}"#
            return #"""
                {"provider":"opencode","turnId":"turn-\#(row.seq)","item":\#(item),
                 "timestamp":"2026-11-08T21:00:00.000Z","seqStart":\#(row.seq),"seqEnd":\#(row.seq)}
                """#
        }
        let minSeq = rows.map(\.seq).min() ?? 0
        let maxSeq = rows.map(\.seq).max() ?? 0
        let json = #"""
            {"requestId":"r","agentId":"agent-outline","direction":"\#(direction)","epoch":"\#(epoch)",
             "reset":false,"staleCursor":false,"gap":false,
             "window":{"minSeq":\#(minSeq),"maxSeq":\#(maxSeq),"nextSeq":\#(maxSeq + 1)},
             "hasOlder":\#(hasOlder),"hasNewer":false,
             "entries":[\#(entries.joined(separator: ","))],"error":null}
            """#
        return try JSONDecoder().decode(
            FetchAgentTimelineRequest.Response.self, from: Data(json.utf8))
    }

    nonisolated private static func index(
        epoch: String, seqs: [Int], previews: [String]? = nil, error: String? = nil
    ) throws -> AgentTimelinePromptIndexRequest.Response {
        let prompts = seqs.enumerated().map { index, seq in
            let preview = previews?[index] ?? "prompt \(seq)"
            return #"{"seq":\#(seq),"timestamp":"2026-11-08T21:00:00.000Z","preview":"\#(preview)"}"#
        }
        let errorJSON = error.map { #""\#($0)""# } ?? "null"
        let json = #"""
            {"type":"session","message":{"type":"agent.timeline.list_prompts.response","payload":{
              "requestId":"idx","agentId":"agent-outline","epoch":"\#(epoch)",
              "prompts":[\#(prompts.joined(separator: ","))],"error":\#(errorJSON)}}}
            """#
        return try JSONDecoder().decode(
            SessionPayloadEnvelope<AgentTimelinePromptIndexRequest.Response>.self,
            from: Data(json.utf8)
        ).payload
    }

    private static func info(promptIndex: Bool?) throws -> ServerInfo {
        var info = try Load.serverInfo()
        if let promptIndex {
            info.features?["agentTimelinePromptIndex"] = .bool(promptIndex)
        }
        return info
    }

    /// Opens the conversation against a fake daemon. The session must outlive the test body: it
    /// owns the event loop that routes pushed stream frames.
    private func openStore(
        _ client: FakeDaemonClient, info: ServerInfo,
        timeline: @escaping @Sendable (FetchAgentTimelineRequest) async throws ->
            FetchAgentTimelineRequest.Response
    ) async throws -> (session: HostSession, store: ConversationStore) {
        let agents = try Load.agents()
        let agentId = try Load.fixtureAgentId()
        client.push(.connected(info))
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline(timeline)
        client.onSetSubscription { _ in try Load.subscription() }

        let session = HostSession(client: client)
        await session.start()
        _ = await eventually { session.connection == .connected(info) }
        let store = session.conversation(for: agentId)
        let ready = await eventually { store.phase == .ready }
        #expect(ready)
        return (session, store)
    }

    nonisolated private static var fixtureEpoch: String {
        get throws { try Load.page().epoch }
    }

    // MARK: Pure rules

    @Test func activePromptIsTheLastOneAtOrBeforeTheReadingPosition() {
        let prompts = (0..<4).map {
            PromptOutline.Prompt(seq: [3, 8, 40, 91][$0], timestamp: "t", preview: "p")
        }
        #expect(PromptOutline.resolveActiveSeq(prompts: prompts, anchorSeq: nil) == nil)
        #expect(PromptOutline.resolveActiveSeq(prompts: prompts, anchorSeq: 2) == nil)
        #expect(PromptOutline.resolveActiveSeq(prompts: prompts, anchorSeq: 3) == 3)
        #expect(PromptOutline.resolveActiveSeq(prompts: prompts, anchorSeq: 39) == 8)
        #expect(PromptOutline.resolveActiveSeq(prompts: prompts, anchorSeq: 40) == 40)
        #expect(PromptOutline.resolveActiveSeq(prompts: prompts, anchorSeq: 10_000) == 91)
        #expect(PromptOutline.resolveActiveSeq(prompts: [], anchorSeq: 5) == nil)
    }

    @Test func anIndexOnlyDescribesItsOwnEpoch() {
        #expect(PromptOutline.shouldAccept(timelineEpoch: "e1", indexEpoch: "e1"))
        #expect(!PromptOutline.shouldAccept(timelineEpoch: "e1", indexEpoch: "e2"))
        #expect(!PromptOutline.shouldAccept(timelineEpoch: nil, indexEpoch: "e1"))
        #expect(!PromptOutline.shouldAccept(timelineEpoch: "e1", indexEpoch: ""))
    }

    @Test func previewsCollapseWhitespaceAndCutAtTheDaemonsLimit() {
        #expect(
            PromptOutline.previewText("  fix\n the   flake\tplease  ") == "fix the flake please")
        #expect(PromptOutline.previewText(String(repeating: "a", count: 120)).count == 120)
        let long = PromptOutline.previewText(String(repeating: "a", count: 200))
        #expect(long.count == 120)
        #expect(long.hasSuffix("…"))
    }

    // MARK: Store behaviour

    @Test func theDaemonFixtureAdvertisesThePromptIndex() throws {
        // The recorded `server_info` is daemon 0.15.2, which serves the outline.
        #expect(try Load.serverInfo().hasFeature("agentTimelinePromptIndex"))
    }

    @Test func fetchesTheWholeIndexWhenTheConversationOpens() async throws {
        let client = FakeDaemonClient()
        let epoch = try Self.fixtureEpoch
        client.on(AgentTimelinePromptIndexRequest.self) { _ in
            try Self.index(epoch: epoch, seqs: [8, 900, 1200])
        }
        let opened = try await openStore(
            client, info: try Self.info(promptIndex: true), timeline: { _ in try Load.page() })

        let store = opened.store
        #expect(await eventually { store.promptOutline.prompts.map(\.seq) == [8, 900, 1200] })
        #expect(store.promptOutline.epoch == epoch)
        #expect(store.promptOutline.isSupported)
        #expect(client.requests(AgentTimelinePromptIndexRequest.self).count == 1)
        // The index is the whole conversation: the timeline still holds one page.
        #expect(client.requests(FetchAgentTimelineRequest.self).count == 1)
    }

    @Test func refetchesWhenTheNewestPromptMoves() async throws {
        let client = FakeDaemonClient()
        let epoch = try Self.fixtureEpoch
        client.on(AgentTimelinePromptIndexRequest.self) { _ in
            try Self.index(epoch: epoch, seqs: [8])
        }
        // Open with the turn cut off, then stream it in: the newest prompt goes nil -> 8.
        let opened = try await openStore(
            client, info: try Self.info(promptIndex: true),
            timeline: { request in
                request.direction == .tail ? try Load.page(before: 8) : try Load.page()
            })
        let store = opened.store
        #expect(await eventually { client.requests(AgentTimelinePromptIndexRequest.self).count == 1 })

        for payload in try Load.stream() {
            client.push(.agentStream(payload))
        }
        #expect(await eventually { store.turns.count == 2 })
        #expect(store.timeline.rows.map(\.seqStart).contains(8))
        #expect(await eventually { client.requests(AgentTimelinePromptIndexRequest.self).count == 2 })
        #expect(await eventually { store.promptOutline.prompts.map(\.seq) == [8] })
    }

    @Test func anIndexFromAnotherEpochIsDropped() async throws {
        let client = FakeDaemonClient()
        client.on(AgentTimelinePromptIndexRequest.self) { _ in
            try Self.index(epoch: "some-other-timeline", seqs: [1, 2])
        }
        let opened = try await openStore(
            client, info: try Self.info(promptIndex: true), timeline: { _ in try Load.page() })

        let store = opened.store
        #expect(await eventually { !store.promptOutline.isLoading })
        #expect(store.promptOutline.prompts.isEmpty)
        #expect(store.promptOutline.epoch == nil)
    }

    @Test func anAnswerSupersededByANewerRequestIsDropped() async throws {
        // Drive the outline directly so the order of the two requests is under test control.
        let client = FakeDaemonClient()
        let outline = PromptOutline(agentId: "agent-outline", client: client)
        outline.update(serverInfo: try Load.serverInfo())
        let epoch = "epoch-stale"
        let gate = Gate()
        let entered = Gate()
        let counter = CallCounter()
        client.on(AgentTimelinePromptIndexRequest.self) { _ in
            let call = await counter.next()
            if call == 1 {
                await entered.open()
                await gate.wait()
            }
            return try Self.index(epoch: epoch, seqs: [call == 1 ? 10 : 30])
        }

        outline.refresh(timelineEpoch: epoch)
        await entered.wait()
        outline.refresh(timelineEpoch: epoch)
        #expect(await eventually { outline.prompts.map(\.seq) == [30] })

        // The held answer was requested first; it must not overwrite the newer one.
        await gate.open()
        try await Task.sleep(for: .milliseconds(50))
        #expect(outline.prompts.map(\.seq) == [30], "the older answer must not land")
        #expect(!outline.isLoading)
    }

    @Test func withoutTheCapabilityThereIsNoRequestAndNoIndex() async throws {
        let client = FakeDaemonClient()
        let opened = try await openStore(
            client, info: try Self.info(promptIndex: false), timeline: { _ in try Load.page() })

        let store = opened.store
        #expect(!store.promptOutline.isSupported)
        #expect(await eventually { store.promptOutline.prompts.isEmpty })
        #expect(client.requests(AgentTimelinePromptIndexRequest.self).isEmpty)
    }

    @Test func reportsTheActivePromptFromTheReadingPosition() async throws {
        let client = FakeDaemonClient()
        let epoch = try Self.fixtureEpoch
        client.on(AgentTimelinePromptIndexRequest.self) { _ in
            try Self.index(epoch: epoch, seqs: [8, 60, 120])
        }
        let opened = try await openStore(
            client, info: try Self.info(promptIndex: true), timeline: { _ in try Load.page() })
        let store = opened.store
        #expect(await eventually { store.promptOutline.prompts.count == 3 })

        store.promptOutline.reportReadingPosition(anchorSeq: 70)
        #expect(store.promptOutline.activeSeq == 60)
        // A late index resolves the position the transcript already reported.
        store.promptOutline.reportReadingPosition(anchorSeq: nil)
        #expect(store.promptOutline.activeSeq == nil)
        store.promptOutline.reportReadingPosition(anchorSeq: 8)
        #expect(store.promptOutline.activeSeq == 8)
    }

    // MARK: The jump

    @Test func jumpingToALoadedPromptDoesNotFetch() async throws {
        let client = FakeDaemonClient()
        let epoch = try Self.fixtureEpoch
        client.on(AgentTimelinePromptIndexRequest.self) { _ in
            try Self.index(epoch: epoch, seqs: [8])
        }
        let opened = try await openStore(
            client, info: try Self.info(promptIndex: true), timeline: { _ in try Load.page() })
        let store = opened.store
        #expect(store.promptRowId(forPromptSeq: 8) != nil)

        let jumped = await store.jump(toPromptSeq: 8)
        #expect(jumped == "row:8")
        #expect(client.requests(FetchAgentTimelineRequest.self).count == 1)
    }

    @Test func jumpingToAnUnloadedPromptFetchesOneWindowAndScrollsThere() async throws {
        let client = FakeDaemonClient()
        let epoch = try Self.fixtureEpoch
        client.on(AgentTimelinePromptIndexRequest.self) { _ in
            try Self.index(epoch: epoch, seqs: [8, 1000])
        }
        let opened = try await openStore(
            client, info: try Self.info(promptIndex: true),
            timeline: { request in
                if request.direction == .tail { return try Load.page() }
                return try Self.page(
                    direction: "before", epoch: epoch,
                    rows: [(1000, "user"), (1001, "assistant")], hasOlder: true)
            })
        let store = opened.store
        #expect(store.promptRowId(forPromptSeq: 1000) == nil)
        let floor = try #require(store.timeline.rows.first?.seqStart)

        let jumped = await store.jump(toPromptSeq: 1000)
        #expect(jumped == "row:1000")
        #expect(store.promptRowId(forPromptSeq: 1000) == "row:1000")
        // One window, not the rest of the conversation: half a page above the prompt.
        let beforePages = client.requests(FetchAgentTimelineRequest.self).filter {
            $0.direction == .before
        }
        #expect(beforePages.count == 1)
        let fetch = try #require(beforePages.first)
        #expect(fetch.cursor?.epoch == epoch)
        #expect(fetch.cursor?.seq == 1000 + 40 / 2 + 1)
        #expect(fetch.limit == 40)
        #expect(fetch.wholeTurns == true)
        #expect(fetch.mergeWindow == true)
        // The floor is still the old one: the jumped window is newer than the loaded history.
        #expect(!store.timeline.hasOlder)
        #expect(store.timeline.startCursor?.seq == floor)
    }

    @Test func aMergedWindowDoesNotMoveTheOlderFloor() throws {
        let epoch = "epoch-floor"
        var timeline = TimelineState()
        timeline.applyPage(
            try Self.page(direction: "tail", epoch: epoch, rows: [(10, "user")], hasOlder: true))
        #expect(timeline.hasOlder)

        timeline.applyPage(
            try Self.page(
                direction: "before", epoch: epoch, rows: [(50, "user")], hasOlder: false))
        #expect(timeline.hasOlder, "rows above the floor say nothing about older history")
        #expect(timeline.startCursor?.seq == 10)

        // A window below the floor does move it, and its flag is the truth.
        timeline.applyPage(
            try Self.page(
                direction: "before", epoch: epoch, rows: [(5, "user")], hasOlder: false))
        #expect(!timeline.hasOlder)
        #expect(timeline.startCursor?.seq == 5)
    }
}

/// Distinguishes prompt-index calls so a test can hold the first answer open.
private actor CallCounter {
    private var count = 0
    func next() -> Int {
        count += 1
        return count
    }
}
