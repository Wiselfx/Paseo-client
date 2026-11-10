#if canImport(UIKit)
import Foundation
import Observation

/// The sidebar's comma-joined preferences, parsed once and written back on change (§3).
///
/// The storage keys and their comma-joined values are unchanged, so every existing preference
/// carries over; only the reads stop splitting strings in `body`.
@MainActor
@Observable
final class SidebarPreferences {
    private enum Storage {
        static let hiddenWorkspaces = "paseo.sidebar.hiddenWorkspaces"
        static let manualUnread = "paseo.sidebar.manualUnread"
        static let collapsedProjects = "paseo.sidebar.collapsedProjects"
        static let collapsedDateGroups = "paseo.sidebar.collapsedDateGroups"
        static let setupCalloutDismissed = "paseo.sidebar.setupCalloutDismissed"
    }

    private(set) var hiddenWorkspaces: Set<String>
    private(set) var manualUnread: Set<String>
    private(set) var collapsedProjects: Set<String>
    private(set) var collapsedDateGroups: Set<String>
    private(set) var setupCalloutDismissed: Set<String>

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hiddenWorkspaces = Self.read(Storage.hiddenWorkspaces, from: defaults)
        manualUnread = Self.read(Storage.manualUnread, from: defaults)
        collapsedProjects = Self.read(Storage.collapsedProjects, from: defaults)
        collapsedDateGroups = Self.read(Storage.collapsedDateGroups, from: defaults)
        setupCalloutDismissed = Self.read(Storage.setupCalloutDismissed, from: defaults)
    }

    // MARK: Hidden workspaces

    func isHidden(_ workspaceId: String) -> Bool {
        hiddenWorkspaces.contains(workspaceId)
    }

    func toggleHidden(_ workspaceId: String) {
        hiddenWorkspaces = Self.toggled(workspaceId, in: hiddenWorkspaces)
        write(hiddenWorkspaces, to: Storage.hiddenWorkspaces)
    }

    // MARK: Manual unread marks (DSH `manual-unread`)

    func isUnread(_ workspaceId: String) -> Bool {
        manualUnread.contains(workspaceId)
    }

    func toggleUnread(_ workspaceId: String) {
        manualUnread = Self.toggled(workspaceId, in: manualUnread)
        write(manualUnread, to: Storage.manualUnread)
    }

    /// Cleared when the workspace is opened.
    func clearUnread(_ workspaceId: String) {
        guard manualUnread.remove(workspaceId) != nil else { return }
        write(manualUnread, to: Storage.manualUnread)
    }

    // MARK: Collapse state

    func isCollapsed(projectId: String) -> Bool {
        collapsedProjects.contains(projectId)
    }

    func toggleCollapsed(projectId: String) {
        collapsedProjects = Self.toggled(projectId, in: collapsedProjects)
        write(collapsedProjects, to: Storage.collapsedProjects)
    }

    func isDateGroupCollapsed(_ id: String) -> Bool {
        collapsedDateGroups.contains(id)
    }

    func toggleDateGroupCollapsed(_ id: String) {
        collapsedDateGroups = Self.toggled(id, in: collapsedDateGroups)
        write(collapsedDateGroups, to: Storage.collapsedDateGroups)
    }

    // MARK: "Set up worktree scripts" callout

    func isSetupCalloutDismissed(projectId: String) -> Bool {
        setupCalloutDismissed.contains(projectId)
    }

    func dismissSetupCallout(projectId: String) {
        guard setupCalloutDismissed.insert(projectId).inserted else { return }
        write(setupCalloutDismissed, to: Storage.setupCalloutDismissed)
    }

    // MARK: Storage

    private static func read(_ key: String, from defaults: UserDefaults) -> Set<String> {
        let raw = defaults.string(forKey: key) ?? ""
        return Set(
            raw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private static func toggled(_ id: String, in set: Set<String>) -> Set<String> {
        var next = set
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        return next
    }

    /// The comma-joined form the sidebar has always written, sorted so the stored value is stable.
    private func write(_ set: Set<String>, to key: String) {
        defaults.set(set.sorted().joined(separator: ","), forKey: key)
    }
}
#endif
