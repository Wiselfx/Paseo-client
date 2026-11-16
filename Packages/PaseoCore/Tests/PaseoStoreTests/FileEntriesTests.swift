import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct FileEntriesTests {
    private func makeFiles(
        _ client: FakeDaemonClient,
        entryOps: Bool = true, duplicate: Bool = true, editing: Bool = true
    ) -> WorkspaceFiles {
        let files = WorkspaceFiles(cwd: "/tmp/fixture-sandbox", client: client)
        files.update(
            supportsEntryOps: entryOps, supportsEntryDuplicate: duplicate,
            supportsFileEditing: editing)
        return files
    }

    nonisolated private func listingResponse(_ path: String? = nil) -> Data {
        let pathJson = path.map { "\"\($0)\"" } ?? "\".\""
        return Data(
            """
            {"type":"session","message":{"type":"file_explorer_response","payload":{
              "cwd":"/tmp/fixture-sandbox","path":\(pathJson),"mode":"list",
              "directory":{"path":\(pathJson),"entries":[]},"file":null,"error":null,
              "requestId":"fixture"
            }}}
            """.utf8)
    }

    nonisolated private func fixture(_ name: String) throws -> Data {
        try Fixture.data(name, in: "git-ops")
    }

    private func decode<P: Decodable & Sendable>(_ type: P.Type, from data: Data) throws -> P {
        try JSONDecoder().decode(SessionPayloadEnvelope<P>.self, from: data).payload
    }

    nonisolated private func registerListing(_ client: FakeDaemonClient) {
        client.on(FileExplorerRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<FileExplorerRequest.Response>.self,
                from: listingResponse()).payload
        }
    }

    // MARK: Live fixtures

    @Test func createFixtureDecodesAndReportsSuccess() throws {
        let response = try decode(
            FileEntryCreateRequest.Response.self, from: fixture("fs_entry_create_response"))
        #expect(response.success == true)
        #expect(response.path == ".t15-fixture/scratch.txt")
        #expect(response.parentPath == ".t15-fixture")
        #expect(response.error == nil)
    }

    @Test func renameFixtureDecodesAndReportsNewPath() throws {
        let response = try decode(
            FileEntryRenameRequest.Response.self, from: fixture("fs_entry_rename_response"))
        #expect(response.success == true)
        #expect(response.renamedPath == ".t15-fixture/renamed.txt")
    }

    @Test func duplicateFixtureDecodesAndReportsNewPath() throws {
        let response = try decode(
            FileEntryDuplicateRequest.Response.self, from: fixture("fs_entry_duplicate_response"))
        #expect(response.success == true)
        #expect(response.duplicatedPath == ".t15-fixture/renamed copy.txt")
    }

    @Test func deleteFixtureDecodesAndReportsSuccess() throws {
        let response = try decode(
            FileEntryDeleteRequest.Response.self, from: fixture("fs_entry_delete_response"))
        #expect(response.success == true)
        #expect(response.path == ".t15-fixture/renamed.txt")
    }

    // MARK: Operations

    @Test func renameRejectsAPathAsTheNewName() async throws {
        let client = FakeDaemonClient()
        let files = makeFiles(client)
        let result = await files.rename(path: "a.txt", to: "dir/b.txt")
        #expect(result == nil)
        #expect(files.error == "Rename takes a new name, not a path. Move it with the daemon instead.")
        #expect(client.requests(FileEntryRenameRequest.self).isEmpty)
    }

    @Test func createReEntryListsTheParentDirectory() async throws {
        let client = FakeDaemonClient()
        let files = makeFiles(client)
        let data = try fixture("fs_entry_create_response")
        client.on(FileEntryCreateRequest.self) { request in
            #expect(request.parentPath == ".t15-fixture")
            #expect(request.name == "scratch.txt")
            #expect(request.kind == .file)
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<FileEntryCreateRequest.Response>.self, from: data).payload
        }
        registerListing(client)
        let path = await files.createEntry(parentPath: ".t15-fixture", name: "scratch.txt", kind: .file)
        #expect(path == ".t15-fixture/scratch.txt")
        #expect(files.error == nil)
        // The listing after the mutation happened.
        #expect(client.requests(FileExplorerRequest.self).count == 1)
        #expect(files.phase == .ready)
    }

    @Test func renameReListsTheParentDirectory() async throws {
        let client = FakeDaemonClient()
        let files = makeFiles(client)
        let data = try fixture("fs_entry_rename_response")
        client.on(FileEntryRenameRequest.self) { request in
            #expect(request.path == ".t15-fixture/scratch.txt")
            #expect(request.name == "renamed.txt")
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<FileEntryRenameRequest.Response>.self, from: data).payload
        }
        registerListing(client)
        let path = await files.rename(path: ".t15-fixture/scratch.txt", to: "renamed.txt")
        #expect(path == ".t15-fixture/renamed.txt")
        #expect(client.requests(FileExplorerRequest.self).count == 1)
    }

    @Test func duplicateReturnsNewPathAndReLists() async throws {
        let client = FakeDaemonClient()
        let files = makeFiles(client)
        let data = try fixture("fs_entry_duplicate_response")
        client.on(FileEntryDuplicateRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<FileEntryDuplicateRequest.Response>.self, from: data).payload
        }
        registerListing(client)
        let path = await files.duplicate(path: ".t15-fixture/renamed.txt")
        #expect(path == ".t15-fixture/renamed copy.txt")
        #expect(client.requests(FileExplorerRequest.self).count == 1)
    }

    @Test func deleteReportsSuccessAndReLists() async throws {
        let client = FakeDaemonClient()
        let files = makeFiles(client)
        let data = try fixture("fs_entry_delete_response")
        client.on(FileEntryDeleteRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<FileEntryDeleteRequest.Response>.self, from: data).payload
        }
        registerListing(client)
        let ok = await files.delete(path: ".t15-fixture/renamed.txt")
        #expect(ok == true)
        #expect(files.error == nil)
        #expect(client.requests(FileExplorerRequest.self).count == 1)
    }

    @Test func collisionSurfacesTheDaemonsErrorTextVerbatim() async throws {
        let client = FakeDaemonClient()
        let files = makeFiles(client)
        client.on(FileEntryCreateRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<FileEntryCreateRequest.Response>.self,
                from: Data("""
                    {"type":"session","message":{"type":"fs.entry.create.response","payload":{
                      "cwd":"/tmp/fixture-sandbox","parentPath":".","path":null,
                      "success":false,"error":"ENOENT: no such directory","requestId":"fixture"
                    }}}
                    """.utf8)).payload
        }
        let path = await files.createEntry(parentPath: nil, name: "scratch.txt", kind: .file)
        #expect(path == nil)
        #expect(files.error == "ENOENT: no such directory")
    }

    @Test func gatingWithoutTheFeatureMakesNoRequests() async throws {
        let client = FakeDaemonClient()
        let files = makeFiles(client, entryOps: false, duplicate: false, editing: false)
        let created = await files.createEntry(parentPath: nil, name: "a", kind: .file)
        let renamed = await files.rename(path: "a", to: "b")
        let deleted = await files.delete(path: "a")
        let duplicated = await files.duplicate(path: "a")
        #expect(created == nil && renamed == nil && deleted == false && duplicated == nil)
        #expect(client.requests(FileEntryCreateRequest.self).isEmpty)
        #expect(client.requests(FileEntryRenameRequest.self).isEmpty)
        #expect(client.requests(FileEntryDeleteRequest.self).isEmpty)
        #expect(client.requests(FileEntryDuplicateRequest.self).isEmpty)
    }

    @Test func duplicateIsGatedSeparatelyFromEntryOps() async throws {
        let client = FakeDaemonClient()
        let files = makeFiles(client, entryOps: true, duplicate: false, editing: true)
        let duplicated = await files.duplicate(path: "a")
        #expect(duplicated == nil)
        #expect(files.error == "This daemon cannot duplicate entries.")
        #expect(client.requests(FileEntryDuplicateRequest.self).isEmpty)
    }

    @Test func writeWrittenOutcomeReListsAndClearsError() async throws {
        let client = FakeDaemonClient()
        let files = makeFiles(client)
        let data = try fixture("fs_file_write_response")
        client.on(FileWriteRequest.self) { request in
            #expect(request.path == ".t15-fixture/scratch.txt")
            #expect(request.expectedModifiedAt == "2026-11-08T22:00:00.000Z")
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<FileWriteRequest.Response>.self, from: data).payload
        }
        registerListing(client)
        let outcome = await files.write(
            path: ".t15-fixture/scratch.txt", content: "after write\n",
            expectedModifiedAt: "2026-11-08T22:00:00.000Z")
        guard case .written(_, let size, _) = outcome else {
            Issue.record("expected .written, got \(outcome)")
            return
        }
        #expect(size == 12)
        #expect(files.error == nil)
        #expect(client.requests(FileExplorerRequest.self).count == 1)
    }

    @Test func writeConflictCarriesTheCurrentModifiedAt() async throws {
        let client = FakeDaemonClient()
        let files = makeFiles(client)
        client.on(FileWriteRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<FileWriteRequest.Response>.self,
                from: Data("""
                    {"type":"session","message":{"type":"fs.file.write.response","payload":{
                      "result":{"status":"conflict","version":{
                        "status":"ready","cwd":"/tmp/fixture-sandbox","path":"a.txt",
                        "size":10,"modifiedAt":"2026-11-09T00:00:00.000Z"
                      }},
                      "requestId":"fixture"
                    }}}
                    """.utf8)).payload
        }
        let outcome = await files.write(
            path: "a.txt", content: "x", expectedModifiedAt: "2026-11-08T00:00:00.000Z")
        #expect(outcome == .conflict(modifiedAt: "2026-11-09T00:00:00.000Z"))
    }

    @Test func writeErrorSurfacesTheDaemonsTextVerbatim() async throws {
        let client = FakeDaemonClient()
        let files = makeFiles(client)
        client.on(FileWriteRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<FileWriteRequest.Response>.self,
                from: Data("""
                    {"type":"session","message":{"type":"fs.file.write.response","payload":{
                      "result":{"status":"error","error":"EACCES: permission denied"},
                      "requestId":"fixture"
                    }}}
                    """.utf8)).payload
        }
        let outcome = await files.write(
            path: "a.txt", content: "x", expectedModifiedAt: "2026-11-08T00:00:00.000Z")
        #expect(outcome == .failed("EACCES: permission denied"))
        #expect(files.error == "EACCES: permission denied")
    }

    @Test func writeGateBlocksWithoutTheFeature() async throws {
        let client = FakeDaemonClient()
        let files = makeFiles(client, editing: false)
        let outcome = await files.write(
            path: "a.txt", content: "x", expectedModifiedAt: "2026-11-08T00:00:00.000Z")
        #expect(outcome == .failed("This daemon cannot edit files."))
        #expect(client.requests(FileWriteRequest.self).isEmpty)
    }
}
