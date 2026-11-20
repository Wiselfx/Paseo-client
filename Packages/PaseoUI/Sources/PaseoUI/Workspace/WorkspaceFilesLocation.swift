#if canImport(UIKit)
import Foundation

/// Where the Files page was, per workspace: the folder stack, the open file, and the top row of
/// each folder on that stack. The page is rebuilt whenever the panel switches tabs or closes, so
/// its `@State` alone forgot all of it; this survives those and app launches.
///
/// Stack entries are the daemon's own folder paths, stored as they came, so the stack is
/// rebuilt exactly instead of being re-derived from a path string.
@MainActor
enum WorkspaceFilesLocation {
    struct Snapshot: Codable, Equatable {
        var stack: [String] = []
        var openFile: String?
        /// The top visible row per folder ("" is the root), as the list's row id.
        var topRows: [String: String] = [:]
    }

    private static var cache: [String: Snapshot] = [:]

    private static func key(_ workspaceId: String) -> String {
        "paseo.files.location.\(workspaceId)"
    }

    static func load(_ workspaceId: String) -> Snapshot {
        if let cached = cache[workspaceId] { return cached }
        let snapshot =
            UserDefaults.standard.data(forKey: key(workspaceId))
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
        cache[workspaceId] = snapshot
        return snapshot
    }

    static func setStack(_ stack: [String], openFile: String?, in workspaceId: String) {
        var snapshot = load(workspaceId)
        snapshot.stack = stack
        snapshot.openFile = openFile
        // Only folders still on the stack keep a scroll position.
        let live = Set(stack + [""])
        snapshot.topRows = snapshot.topRows.filter { live.contains($0.key) }
        store(snapshot, in: workspaceId)
    }

    static func topRow(folder: String, in workspaceId: String) -> String? {
        load(workspaceId).topRows[folder]
    }

    /// Kept in memory on every change; written to disk only when the page leaves (`flush`), so a
    /// scroll never writes defaults per row.
    static func setTopRow(_ row: String?, folder: String, in workspaceId: String) {
        var snapshot = load(workspaceId)
        snapshot.topRows[folder] = row
        cache[workspaceId] = snapshot
    }

    static func flush(_ workspaceId: String) {
        store(load(workspaceId), in: workspaceId)
    }

    private static func store(_ snapshot: Snapshot, in workspaceId: String) {
        cache[workspaceId] = snapshot
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key(workspaceId))
        }
    }
}
#endif
