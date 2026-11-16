import Testing

@testable import PaseoStore

// Upstream: packages/app/src/file-explorer/preview-target.ts:60-107
@MainActor struct ReadCwdTests {
    private func files(_ cwd: String) -> WorkspaceFiles {
        WorkspaceFiles(cwd: cwd, client: FakeDaemonClient())
    }

    @Test func insideWorkspaceReadsFromWorkspace() {
        #expect(files("/work/app").readCwd(for: "/work/app/a.png") == "/work/app")
        #expect(files("/work/app").readCwd(for: "a.png") == "/work/app")
    }

    @Test func outsideWorkspaceReadsFromFilesystemRoot() {
        #expect(files("/work/app").readCwd(for: "/tmp/shot.png") == "/")
        #expect(files("/work/app").readCwd(for: "/work/app2/a.png") == "/")
    }

    @Test func homeRelativeReadsFromHome() {
        #expect(files("/work/app").readCwd(for: "~/pic.png") == "~")
    }
}
