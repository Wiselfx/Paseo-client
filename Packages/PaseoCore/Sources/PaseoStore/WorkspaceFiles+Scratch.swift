import PaseoKit

extension WorkspaceFiles {
    /// A separate `WorkspaceFiles` on the same checkout and connection, for background walks
    /// (the composer's @-mention index) that must not move the directory the Files panel shows.
    public func makeScratch() -> WorkspaceFiles {
        WorkspaceFiles(cwd: cwd, client: client)
    }
}
