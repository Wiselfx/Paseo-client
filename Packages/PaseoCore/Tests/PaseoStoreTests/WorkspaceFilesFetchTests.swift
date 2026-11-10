import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// R3 §4: `WorkspaceFiles.fetch` is the inline-preview read path. It must not write the store's
/// visible state, so several images can load at once.
@Suite @MainActor
struct WorkspaceFilesFetchTests {
    /// Counts how many requests are in flight at once, so the test can prove the two reads overlap.
    private actor InFlight {
        private var current = 0
        private var peak = 0

        func entered() {
            current += 1
            peak = max(peak, current)
        }

        func left() { current -= 1 }

        var maximum: Int { peak }
    }

    private nonisolated static func response(for path: String?) throws
        -> FileExplorerRequest.Response
    {
        var response = try Load.fileRead()
        guard var file = response.file else { throw FakeDaemonClient.FakeError.unexpectedResponse("no file") }
        file.path = path ?? ""
        file.content = "bytes for \(path ?? "")"
        response.file = file
        response.path = file.path
        return response
    }

    @Test func concurrentFetchesReturnTheirOwnFilesAndLeaveTheStateAlone() async throws {
        let client = FakeDaemonClient()
        let inFlight = InFlight()
        client.on(FileExplorerRequest.self) { request in
            await inFlight.entered()
            // Hold both requests open so they really overlap.
            try? await Task.sleep(for: .milliseconds(20))
            await inFlight.left()
            return try Self.response(for: request.path)
        }

        let files = WorkspaceFiles(cwd: "/tmp/fixture-sandbox", client: client)
        async let first = files.fetch("a.png")
        async let second = files.fetch("b.png")
        let (a, b) = try await (first, second)

        #expect(a.path == "a.png")
        #expect(b.path == "b.png")
        #expect(a.content == "bytes for a.png")
        #expect(b.content == "bytes for b.png")
        let peak = await inFlight.maximum
        #expect(peak == 2, "both reads were in flight together")

        // Nothing the Files page shows was touched.
        #expect(files.file == nil)
        #expect(files.phase == .idle)
        #expect(files.path == nil)
        #expect(files.error == nil)
        #expect(files.entries.isEmpty)

        let requests = client.requests(FileExplorerRequest.self)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.mode == .file })
        #expect(requests.allSatisfy { $0.cwd == "/tmp/fixture-sandbox" })
        #expect(requests.map { $0.path ?? "" }.sorted() == ["a.png", "b.png"])
    }

    @Test func fetchUsesTheSameByteLimitAsRead() async throws {
        let client = FakeDaemonClient()
        client.on(FileExplorerRequest.self) { request in try Self.response(for: request.path) }
        let files = WorkspaceFiles(cwd: "/tmp/fixture-sandbox", client: client)

        _ = try await files.fetch("a.png", maxBytes: 4096)
        _ = try await files.fetch("b.png")

        let requests = client.requests(FileExplorerRequest.self)
        #expect(requests.first?.maxBytes == 4096)
        #expect(requests.last?.maxBytes == files.maxReadBytes)
    }

    @Test func aResponseWithoutAFileThrowsAndWritesNothing() async throws {
        let client = FakeDaemonClient()
        client.on(FileExplorerRequest.self) { _ in
            var response = try Load.fileRead()
            response.file = nil
            response.error = "No such file"
            return response
        }
        let files = WorkspaceFiles(cwd: "/tmp/fixture-sandbox", client: client)

        await #expect(throws: PaseoStoreError.missingFile(path: "x.png", message: "No such file")) {
            _ = try await files.fetch("x.png")
        }
        #expect(files.file == nil)
        #expect(files.phase == .idle)
        #expect(files.error == nil)
    }
}
