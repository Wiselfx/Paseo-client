import Foundation
import Testing

@testable import PaseoStore

/// The persisted draft store (R1.A). Upstream is the spec:
/// `packages/app/src/stores/draft-store/{state,persistence}.ts`.
@Suite @MainActor
struct DraftPersistenceTests {
    /// A file of its own per test, so nothing touches the app's drafts.
    private func scratchURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "paseo-draft-tests/\(UUID().uuidString)/drafts.json")
    }

    private func read(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    private func storedKeys(_ url: URL) -> [String] {
        guard let data = read(url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let drafts = object["drafts"] as? [String: Any]
        else { return [] }
        return Array(drafts.keys)
    }

    @Test func textSavesAsActiveAndAnEmptyDraftIsAbandoned() {
        let store = DraftStore(fileURL: nil)

        store.editText("hello", for: DraftKey.agent("a1"))

        #expect(store.input(for: DraftKey.agent("a1"))?.text == "hello")
        #expect(store.record(for: DraftKey.agent("a1"))?.lifecycle == .active)
        #expect(store.record(for: DraftKey.agent("a1"))?.version == 1)

        store.editText("", for: DraftKey.agent("a1"))

        #expect(store.input(for: DraftKey.agent("a1")) == nil, "an emptied draft abandons")
        #expect(store.record(for: DraftKey.agent("a1"))?.lifecycle == .abandoned)
        #expect(store.record(for: DraftKey.agent("a1"))?.version == 2)
    }

    @Test func eachDraftKeepsItsOwnRecord() {
        let store = DraftStore(fileURL: nil)

        store.editText("first", for: DraftKey.draft("d1"))
        store.editText("second", for: DraftKey.draft("d2"))
        store.editText("agent text", for: DraftKey.agent("a1"))

        #expect(store.input(for: DraftKey.draft("d1"))?.text == "first")
        #expect(store.input(for: DraftKey.draft("d2"))?.text == "second")
        #expect(store.input(for: DraftKey.agent("a1"))?.text == "agent text")
    }

    @Test func writesAreCoalescedAndFlushWritesTheLatestText() async throws {
        let url = scratchURL()
        let store = DraftStore(fileURL: url)

        // The first change after the store was loaded is written at once (upstream's storage
        // only waits when the previous write was recent). The write happens on the writer's queue,
        // off the main actor, so the file appears a moment after the call returns.
        store.editText("one", for: DraftKey.agent("a1"))
        let written = await eventually { storedKeys(url) == [DraftKey.agent("a1")] }
        #expect(written)

        store.editText("two", for: DraftKey.agent("a1"))
        store.editText("three", for: DraftKey.agent("a1"))
        // Still inside the 200 ms interval: nothing newer on disk yet.
        #expect(store.input(for: DraftKey.agent("a1"))?.text == "three")

        store.flush()

        let reloaded = DraftStore(fileURL: url)
        #expect(reloaded.input(for: DraftKey.agent("a1"))?.text == "three")
    }

    @Test func backgroundFlushKeepsTheLastKeystrokes() async throws {
        let url = scratchURL()
        let store = DraftStore(fileURL: url)
        store.editText("typed", for: DraftKey.draft("d1"))

        // A second keystroke only lands in memory until the interval passes or the app flushes.
        store.editText("typed more", for: DraftKey.draft("d1"))
        store.flush()
        try await Task.sleep(for: .milliseconds(20))

        #expect(DraftStore(fileURL: url).input(for: DraftKey.draft("d1"))?.text == "typed more")
    }

    @Test func sendingClearsTheTextAndPruneDropsTheFinishedRecord() {
        let store = DraftStore(fileURL: nil)
        store.editText("send me", for: DraftKey.agent("a1"))

        store.markSent(DraftKey.agent("a1"))

        #expect(store.input(for: DraftKey.agent("a1")) == nil)
        #expect(store.record(for: DraftKey.agent("a1"))?.lifecycle == .sent)
        #expect(store.record(for: DraftKey.agent("a1"))?.input.text == "")

        let later = Date().addingTimeInterval(DraftStore.finalizedTTL + 1)
        #expect(store.pruneFinalized(now: later))
        #expect(store.record(for: DraftKey.agent("a1")) == nil, "finished drafts drop after 5 min")
    }

    @Test func activeDraftsAreNeverPruned() {
        let store = DraftStore(fileURL: nil)
        store.editText("keep me", for: DraftKey.draft("d1"))

        let muchLater = Date().addingTimeInterval(60 * 60 * 24 * 30)
        #expect(!store.pruneFinalized(now: muchLater))
        #expect(store.input(for: DraftKey.draft("d1"))?.text == "keep me")
    }

    @Test func legacyUserDefaultsDraftMovesIntoTheStoreAndItsKeyGoesAway() {
        let agentId = "legacy-\(UUID().uuidString)"
        let legacyKey = DraftStore.legacyAgentPrefix + agentId
        UserDefaults.standard.set("old unsent text", forKey: legacyKey)
        let store = DraftStore(fileURL: nil)

        #expect(store.input(for: DraftKey.agent(agentId))?.text == "old unsent text")
        #expect(UserDefaults.standard.string(forKey: legacyKey) == nil, "the old key is migrated")
        #expect(store.record(for: DraftKey.agent(agentId))?.lifecycle == .active)
    }

    @Test func aRecordTheStoreAlreadyHasWinsOverALegacyKey() {
        let agentId = "legacy-\(UUID().uuidString)"
        let legacyKey = DraftStore.legacyAgentPrefix + agentId
        UserDefaults.standard.set("stale", forKey: legacyKey)
        let store = DraftStore(fileURL: nil)
        store.editText("newer", for: DraftKey.agent(agentId))

        #expect(store.input(for: DraftKey.agent(agentId))?.text == "newer")
        #expect(UserDefaults.standard.string(forKey: legacyKey) == nil)
    }

    // MARK: Last screen (R1.C)

    @Test func theLastScreenSurvivesAReload() {
        let url = scratchURL()
        let store = DraftStore(fileURL: url)
        let agentScreen = LastScreen(hostId: "h1", workspaceId: "ws-1", agentId: "a1")
        store.remember(agentScreen)
        store.flush()

        #expect(DraftStore(fileURL: url).lastScreen == agentScreen)

        let draftScreen = LastScreen(hostId: "h1", workspaceId: "ws-2", draftId: "d1")
        store.remember(draftScreen)
        store.flush()

        #expect(DraftStore(fileURL: url).lastScreen == draftScreen)
        #expect(DraftStore(fileURL: url).input(for: DraftKey.draft("d1")) == nil)
    }

    // MARK: New-session drafts (R1.B)

    /// Two providers: `claude` ready with one model, `codex` ready with two models, one carrying
    /// thinking levels, plus two modes and a default mode.
    nonisolated private static let snapshot = #"""
        {"requestId":"r","entries":[
          {"provider":"claude","status":"ready","enabled":true,
           "models":[{"provider":"claude","id":"sonnet","label":"Sonnet","isDefault":true}]},
          {"provider":"codex","status":"ready","enabled":true,"defaultModeId":"plan",
           "models":[
             {"provider":"codex","id":"fast","label":"Fast","isDefault":true},
             {"provider":"codex","id":"deep","label":"Deep","defaultThinkingOptionId":"medium",
              "thinkingOptions":[
                {"id":"low","label":"Low"},
                {"id":"medium","label":"Medium"},
                {"id":"high","label":"High"}]}],
           "modes":[{"id":"plan","label":"Plan"},{"id":"write","label":"Write"}]}
        ]}
        """#

    private func catalogue() async throws -> AgentControlStore {
        let client = FakeDaemonClient()
        client.onSend(GetProvidersSnapshotRequest.self) { _ in
            try JSONDecoder().decode(
                GetProvidersSnapshotRequest.Response.self,
                from: Data(DraftPersistenceTests.snapshot.utf8))
        }
        let catalog = AgentControlStore(client: client)
        await catalog.loadCatalog(cwd: "/tmp/draft")
        return catalog
    }

    @Test func aNewSessionDraftReopensWithItsUnsentText() {
        let store = DraftStore(fileURL: nil)
        let first = DraftSession(
            workspaceId: "ws-1", cwd: "/tmp/draft", draftId: "d1", drafts: store)
        first.text = "unsent prompt"

        let reopened = DraftSession(
            workspaceId: "ws-1", cwd: "/tmp/draft", draftId: "d1", drafts: store)

        #expect(reopened.text == "unsent prompt")
        #expect(reopened.key == DraftKey.draft("d1"))
    }

    @Test func twoNewSessionDraftsDoNotOverwriteEachOther() {
        let store = DraftStore(fileURL: nil)
        let one = DraftSession(workspaceId: "ws-1", cwd: "/tmp", draftId: "d1", drafts: store)
        let two = DraftSession(workspaceId: "ws-1", cwd: "/tmp", draftId: "d2", drafts: store)

        one.text = "about the first thing"
        two.text = "about something else"

        #expect(store.input(for: DraftKey.draft("d1"))?.text == "about the first thing")
        #expect(store.input(for: DraftKey.draft("d2"))?.text == "about something else")
        #expect(DraftSession.makeDraftId() != DraftSession.makeDraftId())
    }

    @Test func aSentDraftLeavesNothingBehind() {
        let store = DraftStore(fileURL: nil)
        let draft = DraftSession(workspaceId: "ws-1", cwd: "/tmp", draftId: "d1", drafts: store)
        draft.text = "send me"

        draft.markSent()

        #expect(store.input(for: DraftKey.draft("d1")) == nil)
        #expect(store.record(for: DraftKey.draft("d1"))?.lifecycle == .sent)
    }

    @Test func picksAreRememberedPerProviderAndTheNextDraftStartsWithThem() async throws {
        let catalog = try await catalogue()
        let store = DraftStore(fileURL: nil)
        let draft = DraftSession(workspaceId: "ws-1", cwd: "/tmp", draftId: "d1", drafts: store)
        draft.seed(catalog: catalog)
        draft.selectProvider("codex", catalog: catalog)
        draft.selectModel("deep", catalog: catalog)
        draft.selectThinking("high")
        draft.selectMode("write")

        let next = DraftSession(
            workspaceId: "ws-1", cwd: "/tmp",
            preferences: store.formPreferences.draftPreferences, draftId: "d2", drafts: store)
        next.seed(catalog: catalog)

        #expect(next.providerId == "codex")
        #expect(next.modelId == "deep")
        #expect(next.thinkingOptionId == "high")
        #expect(next.modeId == "write")
    }

    @Test func switchingProviderBackRestoresThatProvidersPicks() async throws {
        let catalog = try await catalogue()
        let store = DraftStore(fileURL: nil)
        let draft = DraftSession(workspaceId: "ws-1", cwd: "/tmp", draftId: "d1", drafts: store)
        draft.seed(catalog: catalog)
        draft.selectProvider("codex", catalog: catalog)
        draft.selectModel("deep", catalog: catalog)
        draft.selectThinking("high")

        draft.selectProvider("claude", catalog: catalog)
        #expect(draft.modelId == "sonnet", "claude's own default")

        draft.selectProvider("codex", catalog: catalog)
        #expect(draft.modelId == "deep", "codex remembers the model it was left on")
        #expect(draft.thinkingOptionId == "high")
    }

    @Test func formPreferencesSurviveAReload() async throws {
        let url = scratchURL()
        let catalog = try await catalogue()
        let store = DraftStore(fileURL: url)
        let draft = DraftSession(workspaceId: "ws-1", cwd: "/tmp", draftId: "d1", drafts: store)
        draft.seed(catalog: catalog)
        draft.selectProvider("codex", catalog: catalog)
        draft.selectMode("write")
        store.flush()

        let reloaded = DraftStore(fileURL: url)

        #expect(reloaded.formPreferences.draftPreferences.providerId == "codex")
        #expect(reloaded.formPreferences.draftPreferences.modeId == "write")
    }

    @Test func aCorruptFileStartsEmptyInsteadOfCrashing() throws {
        let url = scratchURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        let store = DraftStore(fileURL: url)

        #expect(store.records.isEmpty)
        store.editText("still works", for: DraftKey.draft("d1"))
        #expect(store.input(for: DraftKey.draft("d1"))?.text == "still works")
    }
}
