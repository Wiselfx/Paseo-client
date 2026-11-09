import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// The project settings page's draft of one script row in `paseo.json`.
///
/// `raw` is the entry as it was read (minus nothing — see `ProjectConfigEditor.scripts`), so
/// `type`, `port` and any newer fields round-trip untouched when the command is edited.
/// `nil` for a script the user added in this session.
public struct ProjectScriptDraft: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var command: String
    /// The `scripts.<name>` object as read, or nil for a new script.
    public var raw: JSONValue?

    public init(id: UUID = UUID(), name: String, command: String, raw: JSONValue? = nil) {
        self.id = id
        self.name = name
        self.command = command
        self.raw = raw
    }
}

/// Pure transforms between the raw `paseo.json` object and the things the Project page edits.
/// Nothing outside `worktree.setup` / `worktree.teardown` / `scripts` is ever touched; every
/// other key (including ones a newer daemon adds) is carried through verbatim.
public enum ProjectConfigEditor {
    /// Split/join helpers: the UI shows one command per line.
    public static func commands(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public static func text(from commands: [String]) -> String {
        commands.joined(separator: "\n")
    }

    /// The lifecycle commands as stored on the wire: `string | string[]`, tolerated either way.
    public static func lifecycleCommands(_ value: JSONValue?) -> [String] {
        guard let value else { return [] }
        switch value {
        case .string(let s):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        case .array(let items):
            return items.compactMap { item -> String? in
                guard case .string(let s) = item,
                    !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return nil }
                return s
            }
        default:
            return []
        }
    }

    public static func worktreeCommands(_ config: JSONValue?) -> (setup: [String], teardown: [String]) {
        guard let worktree = config?["worktree"], case .object(let object) = worktree else {
            return ([], [])
        }
        return (
            lifecycleCommands(object["setup"]),
            lifecycleCommands(object["teardown"])
        )
    }

    /// Script rows in a stable (sorted) order. Empty names are kept so the UI can flag them.
    public static func scripts(_ config: JSONValue?) -> [ProjectScriptDraft] {
        guard let scriptsValue = config?["scripts"], case .object(let record) = scriptsValue else {
            return []
        }
        return record.keys.sorted().compactMap { name in
            guard let entryValue = record[name], case .object(let entry) = entryValue else {
                // An entry that isn't an object is uneditable here; skip it (it stays in `raw`
                // when the user saves, because the record is rebuilt from drafts).
                return nil
            }
            let command = entry["command"].flatMap { value -> String? in
                if case .string(let s) = value { return s }
                return nil
            } ?? ""
            return ProjectScriptDraft(
                name: name, command: command, raw: .object(entry))
        }
    }

    /// Builds the config to write. Keys this editor manages are rebuilt from the drafts;
    /// everything else is carried over from `base` unchanged.
    public static func replacing(
        config base: JSONValue?, setup: [String], teardown: [String], scripts: [ProjectScriptDraft]
    ) -> JSONValue {
        var root: [String: JSONValue] = [:]
        if case .object(let object)? = base { root = object }

        // worktree: keep unknown keys (servicePorts, terminals…), replace setup/teardown.
        var worktree: [String: JSONValue] = [:]
        if case .object(let object)? = root["worktree"] { worktree = object }
        setOrRemove(&worktree, key: "setup", value: setup)
        setOrRemove(&worktree, key: "teardown", value: teardown)
        if worktree.isEmpty { root.removeValue(forKey: "worktree") } else { root["worktree"] = .object(worktree) }

        // scripts: rebuilt from drafts; unknown per-script keys round-trip via `raw`.
        var scriptRecord: [String: JSONValue] = [:]
        for draft in scripts {
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            var entry: [String: JSONValue] = [:]
            if case .object(let object)? = draft.raw { entry = object }
            entry["command"] = .string(draft.command)
            scriptRecord[name] = .object(entry)
        }
        if scriptRecord.isEmpty { root.removeValue(forKey: "scripts") } else {
            root["scripts"] = .object(scriptRecord)
        }

        return .object(root)
    }

    private static func setOrRemove(
        _ object: inout [String: JSONValue], key: String, value: [String]
    ) {
        if value.isEmpty {
            object.removeValue(forKey: key)
        } else {
            object[key] = .array(value.map(JSONValue.string))
        }
    }
}

/// Reads and writes a project's `paseo.json` over `read_project_config_request` /
/// `write_project_config_request`, with the revision the daemon handed out as the
/// `expectedRevision` token for the next write (optimistic concurrency).
///
/// State machine of a form session: `load` → drafts rendered from `config` → `save` →
/// updated `revision` (on success) or a typed error (`stale` shows "This file changed on the
/// host" and needs `load` again to re-arm the revision).
///
/// IMPLEMENTATION TICKET: docs/tickets/M2.11-project-settings.md
@MainActor @Observable
public final class ProjectConfigStore {
    public enum Phase: Sendable, Equatable {
        case idle, loading, ready, failed
    }

    public private(set) var phase: Phase = .idle
    /// The project root the current state belongs to; nil until the first load.
    public private(set) var repoRoot: String?
    /// The raw config object as read (nil when there is no paseo.json or after a reset).
    public private(set) var config: JSONValue?
    /// The revision to pass as `expectedRevision` on the next write.
    public private(set) var revision: PaseoProjectConfigRevision?
    public private(set) var hasUncommittedWorktreeSetupChanges = false
    /// Last in-band failure, for the page's error line; cleared on the next success.
    public private(set) var error: ProjectConfigRpcError?
    /// The transport-level/send failure text when the RPC never produced a payload.
    public private(set) var sendError: String?
    public private(set) var isSaving = false
    /// `stale_project_config` from the last write: the page shows "This file changed on the
    /// host" + Reload, which calls `load` and resets the drafts.
    public private(set) var stale = false

    private let client: any DaemonClient

    public init(client: any DaemonClient) {
        self.client = client
    }

    /// Loads (or reloads) the project's config. Resets any stale/error state; the caller resets
    /// its text drafts from this.
    public func load(repoRoot: String) async {
        phase = .loading
        stale = false
        error = nil
        sendError = nil
        do {
            let response = try await client.send(ReadProjectConfigRequest(repoRoot: repoRoot))
            guard response.ok else {
                self.repoRoot = repoRoot
                self.config = nil
                self.revision = nil
                self.error = response.error
                self.phase = .failed
                return
            }
            self.repoRoot = repoRoot
            self.config = response.config
            self.revision = response.revision
            self.hasUncommittedWorktreeSetupChanges =
                response.hasUncommittedWorktreeSetupChanges ?? false
            self.phase = .ready
        } catch {
            self.repoRoot = repoRoot
            self.sendError = String(describing: error)
            self.phase = .failed
        }
    }

    /// Writes the config built from the current draft state. On success the stored revision is
    /// re-armed for the next save. No throwing: failures land in `error`/`stale`/`sendError`.
    @discardableResult
    public func save(repoRoot: String, setup: [String], teardown: [String], scripts: [ProjectScriptDraft]) async -> Bool {
        isSaving = true
        stale = false
        error = nil
        sendError = nil
        // Rebuild from the *loaded* config so keys we never read round-trip untouched.
        let base = self.config
        let newConfig = ProjectConfigEditor.replacing(
            config: base, setup: setup, teardown: teardown, scripts: scripts)
        let expected = revision
        do {
            let response = try await client.send(
                WriteProjectConfigRequest(
                    repoRoot: repoRoot, config: newConfig, expectedRevision: expected))
            defer { isSaving = false }
            guard response.ok else {
                if case .staleProjectConfig? = response.error {
                    stale = true
                }
                self.error = response.error
                return false
            }
            self.config = response.config ?? newConfig
            self.revision = response.revision
            self.hasUncommittedWorktreeSetupChanges =
                response.hasUncommittedWorktreeSetupChanges ?? false
            self.phase = .ready
            return true
        } catch {
            defer { isSaving = false }
            self.sendError = String(describing: error)
            return false
        }
    }

    /// Drops the stale/error flags without touching the loaded config (used by "dismiss").
    public func clearErrors() {
        error = nil
        sendError = nil
        stale = false
    }
}

/// Project icon read/set. The read is ungated; the set is gated on
/// `features.projectCustomIcon` (the reset uses `source: { type: "automatic" }`).
///
/// IMPLEMENTATION TICKET: docs/tickets/M2.11-project-settings.md
@MainActor @Observable
public final class ProjectIconStore {
    public enum Phase: Sendable, Equatable {
        case idle, loading, ready, failed
    }

    public private(set) var phase: Phase = .idle
    /// The project the state belongs to; nil until the first load.
    public private(set) var projectId: String?
    /// Decoded icon bytes; nil means "automatic / none".
    public private(set) var iconData: Data?
    public private(set) var mimeType: String?
    public private(set) var isSaving = false
    /// Observable failure, e.g. the gate is closed or the host rejected the upload.
    public private(set) var error: String?
    /// `features.projectCustomIcon`: the set/reset actions are offered.
    public private(set) var supportsCustomIcon = false

    private let client: any DaemonClient

    public init(client: any DaemonClient) {
        self.client = client
    }

    /// Reads `features.projectCustomIcon` once per connection.
    public func update(serverInfo: ServerInfo?) {
        supportsCustomIcon = serverInfo?.hasFeature("projectCustomIcon") ?? false
    }

    public func load(projectId: String) async {
        phase = .loading
        self.projectId = projectId
        error = nil
        do {
            let response = try await client.send(ProjectIconGetRequest(projectId: projectId))
            self.iconData = response.icon.flatMap { Data(base64Encoded: $0.data) }
            self.mimeType = response.icon?.mimeType
            self.error = response.error
            self.phase = (response.error == nil) ? .ready : .failed
        } catch {
            self.error = String(describing: error)
            self.phase = .failed
        }
    }

    /// Uploads the given image bytes as the project's custom icon. Returns false (and sets
    /// `error`) on gate-closed or rejection; on success the icon is reloaded.
    public func setUpload(projectId: String, data: Data) async -> Bool {
        guard supportsCustomIcon else {
            error = "This host cannot set project icons."
            return false
        }
        return await set(projectId: projectId, source: .upload(data: data.base64EncodedString()))
    }

    /// Resets the icon to automatic discovery. Returns false (and sets `error`) on failure.
    public func reset(projectId: String) async -> Bool {
        guard supportsCustomIcon else {
            error = "This host cannot set project icons."
            return false
        }
        return await set(projectId: projectId, source: .automatic)
    }

    private func set(projectId: String, source: ProjectIconSource) async -> Bool {
        isSaving = true
        error = nil
        do {
            let response = try await client.send(
                ProjectIconSetRequest(projectId: projectId, source: source))
            guard response.accepted else {
                isSaving = false
                self.error = response.error ?? "The host rejected the icon."
                return false
            }
            isSaving = false
            await load(projectId: projectId)
            return true
        } catch {
            isSaving = false
            self.error = String(describing: error)
            return false
        }
    }
}
