import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct WorkspaceFilesTests {
    @Test func listsDirectoriesFirstThenNames() async throws {
        let client = FakeDaemonClient()
        let listing = try Load.fileListing()
        client.on(FileExplorerRequest.self) { _ in listing }

        let files = WorkspaceFiles(cwd: "/tmp/fixture-sandbox", client: client)
        await files.list()

        #expect(files.phase == .ready)
        #expect(files.error == nil)
        #expect(files.path == ".")
        #expect(files.file == nil)
        let entries = files.entries
        #expect(entries.first?.name == ".git")
        #expect(entries.first?.kind == .directory)
        #expect(entries.contains { $0.name == "convert.py" })
        #expect(entries.dropFirst().allSatisfy { $0.kind == .file })

        let request = try #require(client.requests(FileExplorerRequest.self).last)
        #expect(request.mode == .list)
        #expect(request.path == nil)
    }

    @Test func readsTextWithAByteLimit() async throws {
        let client = FakeDaemonClient()
        let read = try Load.fileRead()
        client.on(FileExplorerRequest.self) { _ in read }

        let files = WorkspaceFiles(cwd: "/tmp/fixture-sandbox", client: client)
        await files.read("convert.py", maxBytes: 1024)

        #expect(files.phase == .ready)
        let file = try #require(files.file)
        #expect(file.path == "convert.py")
        #expect(file.kind == .text)
        #expect(file.textContent?.contains("def f_to_c") == true)
        #expect(files.entries.isEmpty)

        let request = try #require(client.requests(FileExplorerRequest.self).last)
        #expect(request.mode == .file)
        #expect(request.path == "convert.py")
        #expect(request.maxBytes == 1024)
    }

    @Test func defaultReadLimitIsBounded() async throws {
        let client = FakeDaemonClient()
        client.on(FileExplorerRequest.self) { _ in try Load.fileRead() }

        let files = WorkspaceFiles(cwd: "/tmp/fixture-sandbox", client: client)
        await files.read("convert.py")

        let request = try #require(client.requests(FileExplorerRequest.self).last)
        #expect(request.maxBytes == files.maxReadBytes)
        #expect(files.maxReadBytes > 0)
    }

    @Test func daemonErrorLandsInPhaseAndError() async throws {
        let client = FakeDaemonClient()
        let response = FileExplorerRequest.Response(
            requestId: "r", cwd: "/tmp/fixture-sandbox", path: "missing", mode: .list,
            directory: nil, file: nil, error: "not found")
        client.on(FileExplorerRequest.self) { _ in response }

        let files = WorkspaceFiles(cwd: "/tmp/fixture-sandbox", client: client)
        await files.list("missing")

        #expect(files.phase == .failed("not found"))
        #expect(files.error == "not found")
    }

    @Test func transportErrorLandsInPhaseAndError() async throws {
        let client = FakeDaemonClient()
        client.on(FileExplorerRequest.self) { _ in throw FakeDaemonClient.FakeError.noHandler("file") }

        let files = WorkspaceFiles(cwd: "/tmp/fixture-sandbox", client: client)
        await files.read("x")

        guard case .failed(let message) = files.phase else {
            Issue.record("expected a failed phase")
            return
        }
        #expect(!message.isEmpty)
        #expect(files.error == message)
    }

    @Test func clearFileReturnsToTheListing() async throws {
        let client = FakeDaemonClient()
        client.on(FileExplorerRequest.self) { _ in try Load.fileRead() }

        let files = WorkspaceFiles(cwd: "/tmp/fixture-sandbox", client: client)
        await files.read("convert.py")
        #expect(files.file != nil)
        files.clearFile()
        #expect(files.file == nil)
    }
}
