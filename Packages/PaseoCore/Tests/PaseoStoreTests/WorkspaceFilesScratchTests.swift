import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct WorkspaceFilesScratchTests {
    @Test func scratchListingLeavesTheSharedInstanceAlone() async throws {
        let client = FakeDaemonClient()
        let listing = try Load.fileListing()
        client.on(FileExplorerRequest.self) { _ in listing }

        let shared = WorkspaceFiles(cwd: "/tmp/fixture-sandbox", client: client)
        let scratch = shared.makeScratch()
        #expect(scratch !== shared)
        #expect(scratch.cwd == shared.cwd)

        await scratch.list()
        #expect(scratch.phase == .ready)
        #expect(!scratch.entries.isEmpty)
        #expect(shared.phase == .idle)
        #expect(shared.path == nil)
        #expect(shared.entries.isEmpty)
    }
}
