import Foundation
import Observation

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

    /// Every key whose draft is still active: what a restore or an attachment cleanup may touch.
    /// `Upstream: packages/app/src/stores/draft-store/index.ts:458-460`.
    public var activeKeys: [String] {
        records.compactMap { key, record in record.lifecycle == .active ? key : nil }
    }

    // MARK: Writing

    /// The input's own edit, on every keystroke. An edit that empties the draft abandons it
    /// without losing the record until its TTL runs out.
    /// `Upstream: packages/app/src/stores/draft-store/state.ts:40-54`.
    public func editText(_ text: String, for key: String) {
        migrateLegacyDraft(for: key)
        let previous = records[key]
        if previous?.lifecycle == .active, previous?.input.text == text { return }
        let attachments = previous?.lifecycle == .active ? previous?.input.attachments ?? [] : []
        records[key] = DraftRecord(
            input: DraftInput(text: text, attachments: attachments),
            lifecycle: text.isEmpty && attachments.isEmpty ? .abandoned : .active,
            updatedAt: Self.nowMs(),
            version: (previous?.version ?? 0) + 1)
        schedulePersist()
    }

    /// The full input, for a caller that writes text and attachments together (upstream
    /// `saveDraftInput`, `index.ts:311-326`). An empty input abandons the draft.
    public func save(_ input: DraftInput, for key: String) {
        guard input.hasContent else {
            clear(key, lifecycle: .abandoned)
            return
        }
        migrateLegacyDraft(for: key)
        let previous = records[key]
        records[key] = DraftRecord(
            input: input, lifecycle: .active, updatedAt: Self.nowMs(),
            version: (previous?.version ?? 0) + 1)
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
        guard let data = try? encoder.encode(StoredFile(drafts: records)) else { return }
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

        init(drafts: [String: DraftRecord]) {
            self.drafts = drafts
        }
    }
}
