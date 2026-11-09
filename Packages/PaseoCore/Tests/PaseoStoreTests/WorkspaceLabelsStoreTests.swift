import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// M2.12: the label catalog store. Fixtures were captured from the fixture sandbox daemon with
/// `Tools/capture-workspace-labels.mjs` (one throwaway "M2.12 capture label", assigned/renamed/
/// deleted; the sandbox workspace ended with no labels).
@Suite @MainActor
struct WorkspaceLabelsStoreTests {
    private func listPayload(_ name: String) throws -> WorkspaceLabelListRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<WorkspaceLabelListRequest.Response>.self,
            from: Fixture.data(name, in: "labels")
        ).payload
    }

    private func assignPayload() throws -> WorkspaceLabelAssignmentSetRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<WorkspaceLabelAssignmentSetRequest.Response>.self,
            from: Fixture.data("label_assign_response", in: "labels")
        ).payload
    }

    private func updatePayload() throws -> WorkspaceLabelUpdateRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<WorkspaceLabelUpdateRequest.Response>.self,
            from: Fixture.data("label_update_response", in: "labels")
        ).payload
    }

    private func deletePayload() throws -> WorkspaceLabelDeleteRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<WorkspaceLabelDeleteRequest.Response>.self,
            from: Fixture.data("label_delete_response", in: "labels")
        ).payload
    }

    private func inspectPayload() throws -> WorkspaceLabelDeleteInspectRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<WorkspaceLabelDeleteInspectRequest.Response>.self,
            from: Fixture.data("label_delete_inspect_response", in: "labels")
        ).payload
    }

    private struct CapturedEvents: Decodable {
        /// Each entry is a full `session` envelope, the same shape HostSession routes.
        var events: [SessionPayloadEnvelope<WorkspaceLabelUpdate>]
    }

    private func updateEvents() throws -> [WorkspaceLabelUpdate] {
        let file = try JSONDecoder().decode(
            CapturedEvents.self, from: Fixture.data("label_update_events", in: "labels"))
        return file.events.map(\.payload)
    }

    private func makeStore(
        client: FakeDaemonClient, serverInfo: ServerInfo? = nil
    ) throws -> WorkspaceLabelsStore {
        let store = WorkspaceLabelsStore(client: client)
        store.update(serverInfo: try (serverInfo ?? Load.workspaceServerInfo()))
        return store
    }

    // MARK: Fixture decoding

    @Test func listResponsesDecode() throws {
        let before = try listPayload("label_list_before")
        #expect(before.labels.isEmpty)
        #expect(before.sync.mode == .snapshot)
        #expect(before.sync.headSeq == 0)

        let afterAssign = try listPayload("label_list_after_assign")
        #expect(afterAssign.labels == [
            WorkspaceLabelDefinition(name: "M2.12 capture label", color: .teal)
        ])
        #expect(afterAssign.sync.headSeq == 1)

        let afterDelete = try listPayload("label_list_after_delete")
        #expect(afterDelete.labels.isEmpty)
        #expect(afterDelete.sync.headSeq == 3)
    }

    @Test func assignmentSetAndUpdateAndDeleteDecode() throws {
        #expect(try assignPayload().workspaceLabels == ["M2.12 capture label"])
        #expect(try assignPayload().label.color == .teal)
        #expect(try updatePayload().label.name == "M2.12 capture renamed")
        #expect(try updatePayload().affectedWorkspaceCount == 1)
        #expect(try deletePayload().affectedWorkspaceCount == 1)
        #expect(try inspectPayload().affectedWorkspaceCount == 1)
    }

    @Test func updateEventsDecodeInOrder() throws {
        let events = try updateEvents()
        #expect(events.map(\.seq) == [1, 2, 3])
        #expect(events[0] == .upsert(
            WorkspaceLabelDefinition(name: "M2.12 capture label", color: .teal),
            previousName: nil, generation: "fixture-generation", seq: 1))
        #expect(events[1] == .upsert(
            WorkspaceLabelDefinition(name: "M2.12 capture renamed", color: .sky),
            previousName: "M2.12 capture label", generation: "fixture-generation", seq: 2))
        #expect(events[2] == .remove(
            name: "M2.12 capture renamed", generation: "fixture-generation", seq: 3))
    }

    @Test func unknownColorAndKindAreTolerated() throws {
        let json = Data("""
        {"kind":"upsert","label":{"name":"Mystery","color":"magenta"},
         "generation":"fixture-generation","seq":9}
        """.utf8)
        let decoded = try JSONDecoder().decode(WorkspaceLabelUpdate.self, from: json)
        guard case .upsert(let label, _, _, _) = decoded else {
            Issue.record("expected upsert")
            return
        }
        #expect(label.color.rawValue == "magenta")
        #expect(!label.color.isKnown)

        let unknownKind = Data(
            #"{"kind":"future-kind","generation":"fixture-generation","seq":8}"#.utf8)
        #expect(try JSONDecoder().decode(WorkspaceLabelUpdate.self, from: unknownKind) ==
            .unknown("future-kind", generation: "fixture-generation", seq: 8))
    }

    // MARK: load

    @Test func loadListsCatalogAndSubscribes() async throws {
        let response = try listPayload("label_list_after_assign")
        let client = FakeDaemonClient()
        client.on(WorkspaceLabelListRequest.self) { _ in response }
        let store = try makeStore(client: client)

        await store.load()

        #expect(store.phase == .ready)
        #expect(store.labels == [
            WorkspaceLabelDefinition(name: "M2.12 capture label", color: .teal)
        ])
        #expect(store.error == nil)
        let request = try #require(client.requests(WorkspaceLabelListRequest.self).last)
        #expect(request.subscribe != nil)
    }

    @Test func loadEmptyCatalogStaysReady() async throws {
        let response = try listPayload("label_list_before")
        let client = FakeDaemonClient()
        client.on(WorkspaceLabelListRequest.self) { _ in response }
        let store = try makeStore(client: client)

        await store.load()

        #expect(store.phase == .ready)
        #expect(store.labels.isEmpty)
    }

    @Test func loadIsANoOpOnDaemonsWithoutTheFeature() async throws {
        let client = FakeDaemonClient()
        let store = WorkspaceLabelsStore(client: client)
        store.update(serverInfo: nil)

        await store.load()

        #expect(store.phase == .ready)
        #expect(store.labels.isEmpty)
        #expect(client.requests(WorkspaceLabelListRequest.self).isEmpty)
    }

    @Test func loadFailureSurfacesErrorAndFailedPhase() async throws {
        let client = FakeDaemonClient()
        client.on(WorkspaceLabelListRequest.self) { _ in throw FakeDaemonClient.FakeError.noHandler("boom") }
        let store = try makeStore(client: client)

        await store.load()

        #expect(store.error != nil)
        guard case .failed = store.phase else {
            Issue.record("expected phase .failed, got \(store.phase)")
            return
        }
    }

    // MARK: Assignment

    @Test func assignMintsLabelAndPatchesWorkspaceDescriptor() async throws {
        let directoryClient = FakeDaemonClient()
        let wired = WorkspaceDirectory(client: directoryClient)
        wired.update(serverInfo: try Load.workspaceServerInfo())
        directoryClient.on(ProjectListRequest.self) { _ in try Load.projectList() }
        directoryClient.on(FetchWorkspacesRequest.self) { _ in try Load.workspaceDirectory() }
        await wired.start()
        #expect(wired.workspace(id: "wks_6adc97aa7e1e49e3")?.labels == nil)

        let assign = try assignPayload()
        let client = FakeDaemonClient()
        client.on(WorkspaceLabelAssignmentSetRequest.self) { _ in assign }
        let store = try makeStore(client: client)
        store.workspaceDirectory = wired

        let ok = await store.setAssignment(
            workspaceId: "wks_6adc97aa7e1e49e3",
            label: WorkspaceLabelDefinition(name: "M2.12 capture label", color: .teal),
            assigned: true)

        #expect(ok)
        #expect(store.actionError == nil)
        #expect(wired.workspace(id: "wks_6adc97aa7e1e49e3")?.labels == ["M2.12 capture label"])
        #expect(store.labels == [
            WorkspaceLabelDefinition(name: "M2.12 capture label", color: .teal)
        ])
    }

    @Test func unassignClearsWorkspaceDescriptorLabels() async throws {
        // An unassign response with an empty label set.
        let directoryClient = FakeDaemonClient()
        let directory = WorkspaceDirectory(client: directoryClient)
        directory.update(serverInfo: try Load.workspaceServerInfo())
        directoryClient.on(ProjectListRequest.self) { _ in try Load.projectList() }
        directoryClient.on(FetchWorkspacesRequest.self) { _ in try Load.workspaceDirectory() }
        await directory.start()
        directory.patchLabels("wks_6adc97aa7e1e49e3", ["M2.12 capture label"])
        #expect(directory.workspace(id: "wks_6adc97aa7e1e49e3")?.labels == ["M2.12 capture label"])

        let client = FakeDaemonClient()
        client.on(WorkspaceLabelAssignmentSetRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<WorkspaceLabelAssignmentSetRequest.Response>.self,
                from: Data("""
                {"type":"session","message":{"type":"workspace.label.assignment.set.response",
                 "payload":{"requestId":"off","label":{"name":"M2.12 capture label","color":"teal"},
                 "workspaceLabels":[]}}}
                """.utf8)
            ).payload
        }
        let store = try makeStore(client: client)
        store.workspaceDirectory = directory

        let ok = await store.setAssignment(
            workspaceId: "wks_6adc97aa7e1e49e3",
            label: WorkspaceLabelDefinition(name: "M2.12 capture label", color: .teal),
            assigned: false)

        #expect(ok)
        #expect(directory.workspace(id: "wks_6adc97aa7e1e49e3")?.labels == nil)
    }

    @Test func assignmentUnsupportedOnOldDaemonSendsNothing() async throws {
        let client = FakeDaemonClient()
        let store = WorkspaceLabelsStore(client: client)
        // No serverInfo → capability flags stay false.

        let ok = await store.setAssignment(
            workspaceId: "wks_6adc97aa7e1e49e3",
            label: WorkspaceLabelDefinition(name: "Any", color: .blue),
            assigned: true)

        #expect(!ok)
        #expect(store.actionError != nil)
        #expect(client.requests(WorkspaceLabelAssignmentSetRequest.self).isEmpty)
    }

    @Test func assignmentRejectsEmptyName() async throws {
        let client = FakeDaemonClient()
        let store = try makeStore(client: client)

        let ok = await store.setAssignment(
            workspaceId: "wks_6adc97aa7e1e49e3",
            label: WorkspaceLabelDefinition(name: "   ", color: .blue),
            assigned: true)

        #expect(!ok)
        #expect(store.actionError != nil)
        #expect(client.requests(WorkspaceLabelAssignmentSetRequest.self).isEmpty)
    }

    // MARK: Live catalog events

    @Test func updateEventsCarryCatalogForward() async throws {
        let before = try listPayload("label_list_before")
        let client = FakeDaemonClient()
        client.on(WorkspaceLabelListRequest.self) { _ in before }
        let store = try makeStore(client: client)
        await store.load()
        let events = try updateEvents()

        store.handle(events[0])
        #expect(store.labels == [
            WorkspaceLabelDefinition(name: "M2.12 capture label", color: .teal)
        ])
        #expect(store.needsResync == false)

        store.handle(events[1])
        #expect(store.labels == [
            WorkspaceLabelDefinition(name: "M2.12 capture renamed", color: .sky)
        ])
        #expect(store.needsResync == false)

        store.handle(events[2])
        #expect(store.labels.isEmpty)
        #expect(store.needsResync == false)
    }

    @Test func outOfOrderPushAsksForCatchUp() async throws {
        let before = try listPayload("label_list_before")
        let client = FakeDaemonClient()
        client.on(WorkspaceLabelListRequest.self) { _ in before }
        let store = try makeStore(client: client)
        await store.load()
        let events = try updateEvents()

        store.handle(events[1]) // seq 2 arrives with cursor at 0

        #expect(store.needsResync)
        #expect(store.labels.isEmpty)

        // The catch-up path: a `sync` request answers with just the changes since our cursor.
        client.on(WorkspaceLabelListRequest.self) { request in
            let json = Data("""
            {"type":"session","message":{"type":"workspace.label.list.response","payload":{
             "requestId":"catchup","labels":[{"name":"M2.12 capture renamed","color":"sky"}],
             "sync":{"mode":"changes","generation":"fixture-generation","headSeq":3,
             "removals":[{"name":"M2.12 capture label","seq":2}]}}}}
            """.utf8)
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<WorkspaceLabelListRequest.Response>.self, from: json
            ).payload
        }

        await store.resyncIfNeeded()

        #expect(store.needsResync == false)
        let request = try #require(client.requests(WorkspaceLabelListRequest.self).last)
        #expect(request.sync?.afterSeq == 0)
        #expect(request.sync?.generation == "fixture-generation")
        #expect(store.labels == [
            WorkspaceLabelDefinition(name: "M2.12 capture renamed", color: .sky)
        ])
    }

    @Test func unknownUpdateKindAsksForCatchUp() async throws {
        let before = try listPayload("label_list_before")
        let client = FakeDaemonClient()
        client.on(WorkspaceLabelListRequest.self) { _ in before }
        let store = try makeStore(client: client)
        await store.load()

        store.handle(.unknown("future-kind", generation: "fixture-generation", seq: 1))

        #expect(store.needsResync)

        // An unknown kind can't be replayed from the cursor: the resync must be a full load.
        await store.resyncIfNeeded()

        #expect(store.needsResync == false)
        let request = try #require(client.requests(WorkspaceLabelListRequest.self).last)
        #expect(request.sync == nil)
    }

    @Test func pushBeforeBaselineForcesFullReload() async throws {
        let afterAssign = try listPayload("label_list_after_assign")
        let client = FakeDaemonClient()
        client.on(WorkspaceLabelListRequest.self) { _ in afterAssign }
        let store = try makeStore(client: client)
        // Deliberately no load(): a push arrived before any baseline could be established.

        let events = try updateEvents()
        store.handle(events[0])

        #expect(store.needsResync)

        await store.resyncIfNeeded()

        let request = try #require(client.requests(WorkspaceLabelListRequest.self).last)
        #expect(request.sync == nil)
        #expect(store.labels == [
            WorkspaceLabelDefinition(name: "M2.12 capture label", color: .teal)
        ])
    }

    // MARK: Rename / recolor / delete

    @Test func renameAndRecolorGoAsOneRpcAndPatchCatalog() async throws {
        let afterAssign = try listPayload("label_list_after_assign")
        let update = try updatePayload()
        let client = FakeDaemonClient()
        client.on(WorkspaceLabelListRequest.self) { _ in afterAssign }
        client.on(WorkspaceLabelUpdateRequest.self) { _ in update }
        let store = try makeStore(client: client)
        await store.load()

        let ok = await store.updateLabel(
            name: "M2.12 capture label", newName: "M2.12 capture renamed", color: .sky)

        #expect(ok)
        let request = try #require(client.requests(WorkspaceLabelUpdateRequest.self).last)
        #expect(request.name == "M2.12 capture label")
        #expect(request.newName == "M2.12 capture renamed")
        #expect(request.color == .sky)
        #expect(store.labels == [
            WorkspaceLabelDefinition(name: "M2.12 capture renamed", color: .sky)
        ])
    }

    @Test func updateWithoutChangesIsRejected() async throws {
        let client = FakeDaemonClient()
        let store = try makeStore(client: client)

        let ok = await store.updateLabel(name: "Any")

        #expect(!ok)
        #expect(store.actionError != nil)
        #expect(client.requests(WorkspaceLabelUpdateRequest.self).isEmpty)
    }

    @Test func deleteRemovesLabelFromCatalog() async throws {
        let afterAssign = try listPayload("label_list_after_assign")
        let delete = try deletePayload()
        let client = FakeDaemonClient()
        client.on(WorkspaceLabelListRequest.self) { _ in afterAssign }
        client.on(WorkspaceLabelDeleteRequest.self) { _ in delete }
        let store = try makeStore(client: client)
        await store.load()

        let ok = await store.deleteLabel(name: "M2.12 capture label")

        #expect(ok)
        let request = try #require(client.requests(WorkspaceLabelDeleteRequest.self).last)
        #expect(request.name == "M2.12 capture label")
        #expect(store.labels.isEmpty)
    }

    @Test func inspectDeleteReturnsWorkspaceCount() async throws {
        let inspect = try inspectPayload()
        let client = FakeDaemonClient()
        client.on(WorkspaceLabelDeleteInspectRequest.self) { _ in inspect }
        let store = try makeStore(client: client)

        #expect(await store.inspectDelete(name: "M2.12 capture renamed") == 1)
        let request = try #require(client.requests(WorkspaceLabelDeleteInspectRequest.self).last)
        #expect(request.name == "M2.12 capture renamed")
    }

    @Test func assignmentFailureLandsInActionErrorAndResetsWorking() async throws {
        let client = FakeDaemonClient()
        client.on(WorkspaceLabelAssignmentSetRequest.self) { _ in
            throw FakeDaemonClient.FakeError.noHandler("daemon offline")
        }
        let store = try makeStore(client: client)

        let ok = await store.setAssignment(
            workspaceId: "wks_6adc97aa7e1e49e3",
            label: WorkspaceLabelDefinition(name: "Any", color: .blue),
            assigned: true)

        #expect(!ok)
        #expect(store.actionError != nil)
        #expect(store.isWorking == false)
    }
}
