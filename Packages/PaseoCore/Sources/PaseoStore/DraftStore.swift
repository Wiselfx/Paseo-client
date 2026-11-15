import Foundation
import Observation
import PaseoProtocol

/// One attachment kept beside a draft's text. The record shape mirrors upstream's
/// `DraftInput.attachments` (`Upstream: packages/app/src/stores/draft-store/state.ts:15-18`);
/// our composer's attachments are uploaded files, so that is the reference it keeps
/// (`AgentAttachment.UploadedFileAttachment`).
public struct DraftAttachment: Codable, Hashable, Sendable {
    public var id: String
    public var fileName: String
    public var mimeType: String
    public var size: Int
    public var path: String

    public init(id: String, fileName: String, mimeType: String, size: Int, path: String) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.size = size
        self.path = path
    }
}

/// What the composer holds: the text and the attachments that ride with the first send.
/// `Upstream: packages/app/src/stores/draft-store/state.ts:15-18`.
public struct DraftInput: Codable, Hashable, Sendable {
    public var text: String
    public var attachments: [DraftAttachment]

    public init(text: String = "", attachments: [DraftAttachment] = []) {
        self.text = text
        self.attachments = attachments
    }

    /// An emptied draft is nothing to carry: upstream abandons it (`state.ts:49`).
    public var hasContent: Bool { !text.isEmpty || !attachments.isEmpty }
}

/// One persisted draft. `Upstream: packages/app/src/stores/draft-store/state.ts:33-38`.
public struct DraftRecord: Codable, Hashable, Sendable {
    /// What happened to the draft. Finished records are kept briefly, then dropped
    /// (`FINALIZED_DRAFT_TTL_MS`); active ones are kept indefinitely.
    /// `Upstream: packages/app/src/stores/draft-store/state.ts:10,20`.
    public enum Lifecycle: String, Codable, Sendable {
        case active
        case abandoned
        case sent
    }

    public var input: DraftInput
    public var lifecycle: Lifecycle
    /// Milliseconds since the epoch, as upstream stores `Date.now()` (`state.ts:83`).
    public var updatedAt: Int
    public var version: Int

    public init(input: DraftInput, lifecycle: Lifecycle, updatedAt: Int, version: Int) {
        self.input = input
        self.lifecycle = lifecycle
        self.updatedAt = updatedAt
        self.version = version
    }
}

/// Every draft has its own key, so two unsent new-session drafts never overwrite each other and
/// an open conversation keeps its own text.
/// `Upstream: packages/app/src/stores/draft-keys.ts:36-45`. Upstream also carries the server id
/// because it shows several hosts at once; this client has one live host and its unsent text has
/// always been keyed by agent id alone (`paseo.draft.<agentId>`), so keys keep that shape.
public enum DraftKey {
    public static func agent(_ agentId: String) -> String { "agent:\(agentId)" }
    public static func draft(_ draftId: String) -> String { "draft:\(draftId)" }
}

/// The choices a new-session draft opens with, remembered per provider so the next draft starts
/// where the last one left off. `Upstream: packages/app/src/create-agent-preferences/preferences.ts:8-24`.
public struct FormPreferences: Codable, Hashable, Sendable {
    /// One provider's last picks. `Upstream: preferences.ts:5-13`.
    public struct Provider: Codable, Hashable, Sendable {
        public var model: String?
        public var mode: String?
        /// The thinking level last picked for each model (`thinkingByModel`).
        public var thinkingByModel: [String: String]?
        /// The provider's option controls as last set (`options`, formerly `featureValues`).
        public var options: [String: JSONValue]?

        public init(
            model: String? = nil, mode: String? = nil,
            thinkingByModel: [String: String]? = nil, options: [String: JSONValue]? = nil
        ) {
            self.model = model
            self.mode = mode
            self.thinkingByModel = thinkingByModel
            self.options = options
        }

        /// The thinking level this provider remembers for `model`.
        public func thinking(for model: String?) -> String? {
            guard let model else { return nil }
            return thinkingByModel?[model]
        }
    }

    /// The provider the last draft used.
    public var provider: String?
    public var providerPreferences: [String: Provider]

    public init(provider: String? = nil, providerPreferences: [String: Provider] = [:]) {
        self.provider = provider
        self.providerPreferences = providerPreferences
    }

    /// The flat picks `DraftSession.seed` starts from. `Upstream: preferences.ts:196-227`.
    public var draftPreferences: DraftPreferences {
        guard let provider, let picks = providerPreferences[provider] else {
            return DraftPreferences()
        }
        let model = picks.model
        return DraftPreferences(
            providerId: provider, modelId: model,
            thinkingOptionId: picks.thinking(for: model), modeId: picks.mode)
    }
}

/// The screen the app was on, so a cold launch reopens it: the workspace, and either the agent or
/// the unsent new-session draft with its draft id.
/// `Upstream: packages/app/src/stores/last-workspace-selection.ts:3-9` (the last navigated
/// workspace) and `docs/expo-router.md:37-45` (restored after the remembered selection has
/// hydrated, based on what was opened, never on connection state).
public struct LastScreen: Codable, Hashable, Sendable {
    /// The daemon the screen belonged to; nil when the record was written before the handshake.
    public var hostId: String?
    public var workspaceId: String?
    /// The open conversation, or nil for a draft.
    public var agentId: String?
    /// The open new-session draft's id, or nil for a conversation.
    public var draftId: String?

    public init(
        hostId: String? = nil, workspaceId: String? = nil, agentId: String? = nil,
        draftId: String? = nil
    ) {
        self.hostId = hostId
        self.workspaceId = workspaceId
        self.agentId = agentId
        self.draftId = draftId
    }
}

/// Unsent composer text, kept as you type.
///
/// One record per key, written to Application Support/Paseo/drafts.json (the app's file-draft
/// style, as `WorkspaceReviewDrafts` does) at most once per `persistInterval`, and flushed when
/// the app goes to the background so the last keystrokes survive.
/// `Upstream: packages/app/src/stores/draft-store/persistence.ts:3,57-108`.
///
/// Reading is done in `init`, before any view exists, so the composer starts with the saved text
/// and never flashes empty and fills in later.
/// `Upstream: packages/app/src/composer/draft/input-draft.ts:240-255`.
@MainActor @Observable
public final class DraftStore {
    public static let shared = DraftStore()

    /// `DRAFT_PERSIST_INTERVAL_MS`: consecutive writes are coalesced to one per interval.
    /// `Upstream: packages/app/src/stores/draft-store/persistence.ts:3`.
    public static let persistInterval: TimeInterval = 0.2
    /// `FINALIZED_DRAFT_TTL_MS`: sent and abandoned records are dropped after five minutes.
    /// `Upstream: packages/app/src/stores/draft-store/state.ts:10`.
    public static let finalizedTTL: TimeInterval = 5 * 60
    /// The key the app kept unsent text under before this store (`SavedDraftStore`).
    public static let legacyAgentPrefix = "paseo.draft."
    private static let agentPrefix = "agent:"

    /// Every record, keyed by `DraftKey`. Read it through `input(for:)` unless you need the
    /// lifecycle.
    public private(set) var records: [String: DraftRecord] = [:]
    /// The last choices made in a new-session draft.
    /// `Upstream: packages/app/src/create-agent-preferences/preferences.ts:16-24`.
    public private(set) var formPreferences = FormPreferences()
    /// The screen to reopen at launch.
    public private(set) var lastScreen: LastScreen?

    private let fileURL: URL?
    private var pendingWrite: Task<Void, Never>?
    private var lastWriteAt = Date.distantPast

    /// `nil` keeps the store in memory (tests, previews).
    public init(fileURL: URL? = DraftStore.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode(StoredFile.self, from: data)
        {
            records = stored.drafts
            if let storedPreferences = stored.formPreferences {
                formPreferences = storedPreferences
            }
            lastScreen = stored.lastScreen
        }
        pruneFinalized()
    }

    public nonisolated static var defaultFileURL: URL? {
        guard
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return support.appendingPathComponent("Paseo/drafts.json")
    }

    // MARK: Reading

    /// The draft to put back in a composer, or nil when there is nothing to show.
    /// `Upstream: packages/app/src/stores/draft-store/state.ts:129-146`.
    public func input(for key: String) -> DraftInput? {
        migrateLegacyDraft(for: key)
        guard let record = records[key], record.lifecycle == .active else { return nil }
        return record.input
    }

    /// The whole record, whatever its lifecycle.
    public func record(for key: String) -> DraftRecord? {
        migrateLegacyDraft(for: key)
        return records[key]
    }

    // MARK: Writing

    /// The input's own edit, on every keystroke. An edit that empties the draft abandons it
    /// without losing the record until its TTL runs out; the attachments of an active draft stay
    /// with its text.
    /// `Upstream: packages/app/src/stores/draft-store/state.ts:40-54`.
    public func editText(_ text: String, for key: String) {
        migrateLegacyDraft(for: key)
        let previous = records[key]
        if previous?.lifecycle == .active, previous?.input.text == text { return }
        let attachments = previous?.lifecycle == .active ? previous?.input.attachments ?? [] : []
        let input = DraftInput(text: text, attachments: attachments)
        records[key] = DraftRecord(
            input: input, lifecycle: input.hasContent ? .active : .abandoned,
            updatedAt: Self.nowMs(), version: (previous?.version ?? 0) + 1)
        schedulePersist()
    }

    /// Sending marks the record `sent`; the text and attachments go with it, so the next open
    /// starts empty.
    /// `Upstream: packages/app/src/stores/draft-store/state.ts:167-182`.
    public func markSent(_ key: String) {
        clear(key, lifecycle: .sent)
    }

    /// Clears a draft. A lifecycle keeps the record (briefly) for another device's merge; no
    /// lifecycle drops it at once (an agent the daemon has deleted).
    /// `Upstream: packages/app/src/stores/draft-store/index.ts:390-418`.
    public func clear(_ key: String, lifecycle: DraftRecord.Lifecycle? = nil) {
        guard let existing = records[key] else { return }
        if let lifecycle, lifecycle != .active {
            records[key] = DraftRecord(
                input: DraftInput(), lifecycle: lifecycle, updatedAt: Self.nowMs(),
                version: existing.version + 1)
        } else {
            records[key] = nil
        }
        pruneFinalized()
        schedulePersist()
    }

    // MARK: Form preferences

    /// Remembers a pick from the draft's controls. The provider's other models keep the level
    /// they were given.
    /// `Upstream: packages/app/src/create-agent-preferences/preferences.ts:196-227`.
    public func recordSelection(
        provider: String, model: String?, mode: String?, thinking: String?
    ) {
        var picks = formPreferences.providerPreferences[provider] ?? FormPreferences.Provider()
        picks.model = model
        picks.mode = mode
        if let model, let thinking {
            var byModel = picks.thinkingByModel ?? [:]
            byModel[model] = thinking
            picks.thinkingByModel = byModel
        }
        formPreferences.provider = provider
        formPreferences.providerPreferences[provider] = picks
        schedulePersist()
    }

    // MARK: Last screen

    /// Remembers the screen to reopen. The same screen again does not touch the disk.
    /// `Upstream: packages/app/src/stores/last-workspace-selection.ts:50-63`.
    public func remember(_ screen: LastScreen) {
        guard lastScreen != screen else { return }
        lastScreen = screen
        schedulePersist()
    }

    // MARK: Persistence

    /// Drops finished records whose TTL has run out. Returns true when something was dropped.
    /// `Upstream: packages/app/src/stores/draft-store/state.ts:148-165`.
    @discardableResult
    public func pruneFinalized(now: Date = .now) -> Bool {
        let cutoff = Self.ms(now) - Int(Self.finalizedTTL * 1000)
        let kept = records.filter { _, record in
            record.lifecycle == .active || record.updatedAt > cutoff
        }
        guard kept.count != records.count else { return false }
        records = kept
        return true
    }

    /// Writes now, whatever the interval says. The app calls this when it goes to the background.
    /// `Upstream: packages/app/src/app/_layout.tsx:997` (the `AppState` flush).
    public func flush() {
        pendingWrite?.cancel()
        pendingWrite = nil
        pruneFinalized()
        write()
    }

    /// Coalesces writes to one per `persistInterval`, and writes the first change at once, as
    /// upstream's storage does (`persistence.ts:73-92`).
    private func schedulePersist() {
        guard fileURL != nil, pendingWrite == nil else { return }
        let delay = Self.persistInterval - Date.now.timeIntervalSince(lastWriteAt)
        guard delay > 0 else {
            write()
            return
        }
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.pendingWrite = nil
            self.write()
        }
    }

    private func write() {
        guard let fileURL else { return }
        lastWriteAt = .now
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard
            let data = try? encoder.encode(
                StoredFile(
                    drafts: records, formPreferences: formPreferences, lastScreen: lastScreen))
        else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence must never break typing; the drafts stay live in memory.
        }
    }

    // MARK: Legacy migration

    /// Before this store, unsent text lived in UserDefaults under `paseo.draft.<agentId>`
    /// (`SavedDraftStore`). The first read of an agent key moves it into the record store so the
    /// text is not lost; a record this store already holds wins, and the old key goes away
    /// either way.
    private func migrateLegacyDraft(for key: String) {
        guard key.hasPrefix(Self.agentPrefix) else { return }
        let agentId = String(key.dropFirst(Self.agentPrefix.count))
        let legacyKey = Self.legacyAgentPrefix + agentId
        let defaults = UserDefaults.standard
        guard let text = defaults.string(forKey: legacyKey) else { return }
        defaults.removeObject(forKey: legacyKey)
        guard !text.isEmpty, records[key] == nil else { return }
        records[key] = DraftRecord(
            input: DraftInput(text: text), lifecycle: .active, updatedAt: Self.nowMs(), version: 1)
        schedulePersist()
    }

    // MARK: Helpers

    private static func nowMs() -> Int { ms(.now) }

    private static func ms(_ date: Date) -> Int { Int(date.timeIntervalSince1970 * 1000) }

    /// The file's shape. `version` leaves room for a migration, as upstream's persisted state
    /// carries `DRAFT_STORE_VERSION` (`stores/draft-store/state.ts:7`).
    private struct StoredFile: Codable {
        var version = 1
        var drafts: [String: DraftRecord]
        var formPreferences: FormPreferences?
        var lastScreen: LastScreen?

        init(drafts: [String: DraftRecord], formPreferences: FormPreferences, lastScreen: LastScreen?) {
            self.drafts = drafts
            self.formPreferences = formPreferences
            self.lastScreen = lastScreen
        }
    }
}
