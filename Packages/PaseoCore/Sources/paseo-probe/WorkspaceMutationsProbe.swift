import Foundation
import PaseoKit
import PaseoProtocol
import PaseoStore

// Live smoke test for the workspace-mutations store methods. Creates a throwaway project in
// /tmp/fixture-mutations, adds it, renames it, clears the rename, pins and unpins the
// /tmp/fixture-sandbox workspace, reports archive-undo support (absent on this daemon), and
// removes the throwaway project afterwards. Never touches anything outside those two sandboxes.
@MainActor
func runWorkspaceMutations(_ connection: DaemonConnection) async throws {
    let sandboxDir = "/tmp/fixture-sandbox"
    let mutationsDir = "/tmp/fixture-mutations"
    try FileManager.default.createDirectory(atPath: mutationsDir, withIntermediateDirectories: true)
    try Data("# fixture mutations\n".utf8).write(to: URL(fileURLWithPath: mutationsDir + "/README.md"))

    try await connection.connect()
    let session = HostSession(client: connection)
    await session.start()
    guard await waitForDirectory(session) else {
        throw ProbeError("workspace directory did not load: \(session.workspaceDirectory.error ?? "unknown")")
    }
    let directory = session.workspaceDirectory

    print(
        "features: pinning=\(directory.supportsWorkspacePinning) "
            + "baseBranch=\(directory.supportsWorkspaceBaseBranch) "
            + "archiveUndo=\(directory.supportsWorkspaceArchiveUndo)"
    )

    guard let sandbox = directory.workspaces.first(where: { $0.cwd == sandboxDir }) else {
        throw ProbeError("sandbox workspace not found at \(sandboxDir)")
    }
    print("sandbox \(sandbox.id) name=\(sandbox.name) pinned=\(sandbox.isPinned)")

    // Pin / unpin, restoring the original state at the end.
    let pin = await directory.setPinned(sandbox.id, true)
    print("pin -> ok=\(pin) pinned=\(directory.workspace(id: sandbox.id)?.isPinned == true)")
    let unpin = await directory.setPinned(sandbox.id, false)
    print("unpin -> ok=\(unpin) pinned=\(directory.workspace(id: sandbox.id)?.isPinned == true)")

    // Throwaway project: add, rename, clear, remove.
    guard let added = await directory.addProject(cwd: mutationsDir) else {
        throw ProbeError("project.add failed: \(directory.actionError ?? "unknown")")
    }
    let projectId = added.projectId
    print("added project \(projectId)")
    let renamed = await directory.renameProject(projectId, to: "Mutation fixture")
    print(
        "rename -> ok=\(renamed) customName=\(directory.project(id: projectId)?.projectCustomName ?? "-")"
    )
    let cleared = await directory.renameProject(projectId, to: nil)
    print(
        "clear rename -> ok=\(cleared) customName=\(directory.project(id: projectId)?.projectCustomName ?? "nil")"
    )
    let removed = await directory.removeProject(projectId)
    print("removed -> ok=\(removed) projects=\(directory.projects.count)")

    // Archive undo: report what this daemon supports; do not archive the sandbox workspace live.
    if directory.supportsWorkspaceArchiveUndo {
        print("archiveUndo: supported; not exercised live (skipped per sandbox rule)")
    } else {
        print("archiveUndo: NOT supported by this daemon (features.workspaceArchiveUndo absent); not exercised live")
    }
    if let error = directory.actionError { print("actionError: \(error)") }
}
