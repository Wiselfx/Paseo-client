import Foundation

// Git extras: the modern binary diff pipeline, discard/switch mutations, the PR status payload and
// live file subscriptions.
//
// Source: messages.ts `DiffEndpointSchema`, `DiffErrorSchema`, `DiffSubscribeRequestSchema`,
// `DiffUnsubscribeRequestSchema`, `DiffSubscribeResponseSchema`, `CheckoutDiscardChangesRequestSchema`,
// `BranchSuggestionsRequestSchema`, `BranchSuggestionsResponseSchema`,
// `CheckoutSwitchBranchRequestSchema`, `CheckoutSwitchBranchResponseSchema`,
// `CheckoutPrStatusPayloadSchema`, `FileSubscribeRequestSchema`, `FileUnsubscribeRequestSchema`,
// `FileSubscribeResponseSchema`, `FileUnsubscribeResponseSchema`, `FileUpdateSchema`,
// `FileVersionSchema`, `ForgeAuthStateSchema`.
// Source: packages/protocol/src/binary-frames/diff.ts for the frame opcodes and byte layout.
//
// Forward compatibility: every union has an `.unknown` case, every field the source marks optional
// stays optional, and an unreadable frame is dropped rather than throwing through the event loop.

// MARK: - Diff subscription

/// One side of a diff comparison. Source: messages.ts `DiffEndpointSchema`.
public enum DiffEndpoint: Sendable, Hashable, Encodable, Decodable {
    case rev(String)
    case index
    case worktree
    case empty
    case unknown(kind: String)

    private enum K: String, CodingKey { case kind, rev }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        switch kind {
        case "rev": self = .rev(try c.decodeIfPresent(String.self, forKey: .rev) ?? "")
        case "index": self = .index
        case "worktree": self = .worktree
        case "empty": self = .empty
        case let other: self = .unknown(kind: other)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case .rev(let rev):
            try c.encode("rev", forKey: .kind)
            try c.encode(rev, forKey: .rev)
        case .index: try c.encode("index", forKey: .kind)
        case .worktree: try c.encode("worktree", forKey: .kind)
        case .empty: try c.encode("empty", forKey: .kind)
        case .unknown(let kind): try c.encode(kind, forKey: .kind)
        }
    }

    /// The ref for `.rev`, nil otherwise.
    public var revName: String? {
        if case .rev(let rev) = self { return rev }
        return nil
    }

    public var isWorktree: Bool { self == .worktree }
}

/// Source: messages.ts `DiffErrorSchema`.
public enum DiffErrorCode: Sendable, Hashable, Decodable {
    case notGitRepo, refNotFound, invalidCompare, tooManySubscriptions, unknownCode
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "NOT_GIT_REPO": self = .notGitRepo
        case "REF_NOT_FOUND": self = .refNotFound
        case "INVALID_COMPARE": self = .invalidCompare
        case "TOO_MANY_SUBSCRIPTIONS": self = .tooManySubscriptions
        case "UNKNOWN": self = .unknownCode
        case let other: self = .unknown(other)
        }
    }

    public var wireValue: String {
        switch self {
        case .notGitRepo: return "NOT_GIT_REPO"
        case .refNotFound: return "REF_NOT_FOUND"
        case .invalidCompare: return "INVALID_COMPARE"
        case .tooManySubscriptions: return "TOO_MANY_SUBSCRIPTIONS"
        case .unknownCode: return "UNKNOWN"
        case .unknown(let raw): return raw
        }
    }
}

/// Source: messages.ts `DiffErrorSchema`.
public struct DiffError: Sendable, Hashable, Decodable {
    public var code: DiffErrorCode
    public var message: String

    public init(code: DiffErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

/// A modern diff comparison: `base` vs `head`, optionally through their merge base.
public struct DiffCompare: Sendable, Hashable {
    public var cwd: String
    public var base: DiffEndpoint
    public var head: DiffEndpoint
    public var mergeBase: Bool?
    public var ignoreWhitespace: Bool?
    public var highlight: Bool?

    public init(
        cwd: String, base: DiffEndpoint, head: DiffEndpoint, mergeBase: Bool? = nil,
        ignoreWhitespace: Bool? = nil, highlight: Bool? = nil
    ) {
        self.cwd = cwd
        self.base = base
        self.head = head
        self.mergeBase = mergeBase
        self.ignoreWhitespace = ignoreWhitespace
        self.highlight = highlight
    }

    /// The uncommitted working tree: HEAD vs worktree.
    public static func working(cwd: String) -> DiffCompare {
        DiffCompare(cwd: cwd, base: .rev("HEAD"), head: .worktree)
    }

    /// The branch's changes against `baseRef`, through the merge base. This is the legacy
    /// `compare.mode == "all"` view.
    public static func againstBase(cwd: String, baseRef: String) -> DiffCompare {
        DiffCompare(cwd: cwd, base: .rev(baseRef), head: .worktree, mergeBase: true)
    }

    /// The legacy JSON comparison equivalent, or nil when the modern comparison has no legacy
    /// shape. Mirrors the SDK's `legacyCompare` (`packages/client/src/diff/index.ts`).
    public var legacyCompare: CheckoutDiffCompare? {
        if highlight == false { return nil }
        guard let rev = base.revName else { return nil }
        if rev == "HEAD", head.isWorktree {
            return CheckoutDiffCompare(mode: .uncommitted, ignoreWhitespace: ignoreWhitespace)
        }
        if mergeBase == true, head.revName == "HEAD" {
            return CheckoutDiffCompare(mode: .base, baseRef: rev, ignoreWhitespace: ignoreWhitespace)
        }
        if mergeBase == true, head.isWorktree {
            return CheckoutDiffCompare(mode: .all, baseRef: rev, ignoreWhitespace: ignoreWhitespace)
        }
        return nil
    }
}

/// Source: messages.ts `DiffSubscribeRequestSchema`, `DiffSubscribeResponseSchema`.
public struct DiffSubscribeRequest: PaseoRequest {
    public static let type = "diff.subscribe.request"
    public static let responseType = "diff.subscribe.response"
    public var requestId = ""
    public var cwd: String
    public var base: DiffEndpoint
    public var head: DiffEndpoint
    public var mergeBase: Bool?
    public var ignoreWhitespace: Bool?
    public var highlight: Bool?

    public init(compare: DiffCompare) {
        self.cwd = compare.cwd
        self.base = compare.base
        self.head = compare.head
        self.mergeBase = compare.mergeBase
        self.ignoreWhitespace = compare.ignoreWhitespace
        self.highlight = compare.highlight
    }

    public typealias Response = DiffSubscribePayload
}

/// Source: messages.ts `DiffSubscribeResponseSchema.payload`. The slot is the binary-frame
/// channel; a newer daemon could still send a value outside `UInt8`.
public struct DiffSubscribePayload: Sendable, Hashable, Decodable {
    public var requestId: String
    public var subscriptionId: String
    public var slot: Int
    public var error: DiffError?

    public init(requestId: String, subscriptionId: String, slot: Int, error: DiffError?) {
        self.requestId = requestId
        self.subscriptionId = subscriptionId
        self.slot = slot
        self.error = error
    }

    private enum K: String, CodingKey { case requestId, subscriptionId, slot, error }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        requestId = try c.decode(String.self, forKey: .requestId)
        subscriptionId = try c.decode(String.self, forKey: .subscriptionId)
        slot = try c.decode(Int.self, forKey: .slot)
        error = try c.decodeIfPresent(DiffError.self, forKey: .error)
    }

    public var slotByte: UInt8? { UInt8(exactly: slot) }
}

/// Fire-and-forget teardown of a modern diff stream. Source: messages.ts
/// `DiffUnsubscribeRequestSchema`; there is no correlated response.
public struct DiffUnsubscribeRequest: PaseoOutboundMessage {
    public static let type = "diff.unsubscribe.request"
    public var subscriptionId: String

    public init(subscriptionId: String) { self.subscriptionId = subscriptionId }
}

// MARK: - Binary diff frames

/// Source: `packages/protocol/src/binary-frames/diff.ts` `DiffOpcode`.
public enum DiffOpcode: UInt8, Sendable, Hashable {
    case begin = 0x40
    case bodies = 0x41
    case end = 0x42
}

/// Source: `packages/protocol/src/binary-frames/diff.ts` `CHANGES`.
public enum DiffEntryChange: Sendable, Hashable {
    case added, modified, deleted, renamed
    case unknown(String)

    static let wireValues = ["added", "modified", "deleted", "renamed"]
}

/// Source: `packages/protocol/src/binary-frames/diff.ts` `CONTENTS`.
public enum DiffEntryContent: Sendable, Hashable {
    case text, binary
    case unknown(String)

    static let wireValues = ["text", "binary"]
}

/// Source: `packages/protocol/src/binary-frames/diff.ts` `KINDS`.
public enum DiffStreamLineKind: Sendable, Hashable {
    case context, add, remove, header
    case unknown(String)

    static let wireValues = ["context", "add", "remove", "header"]

    var diffLineType: DiffLineType {
        switch self {
        case .context: return .context
        case .add: return .add
        case .remove: return .remove
        case .header: return .header
        case .unknown(let raw): return .unknown(raw)
        }
    }
}

/// Source: `packages/protocol/src/binary-frames/diff.ts` `DiffRun`.
public struct DiffRun: Sendable, Hashable {
    public var style: String?
    /// Length in UTF-16 code units, exactly as the JavaScript encoder measures strings.
    public var length: Int

    public init(style: String?, length: Int) {
        self.style = style
        self.length = length
    }
}

/// Source: `packages/protocol/src/binary-frames/diff.ts` `DiffEntry`.
public struct DiffEntry: Sendable, Hashable {
    public var path: String
    public var oldPath: String?
    public var change: DiffEntryChange
    public var content: DiffEntryContent
    public var additions: Int
    public var deletions: Int
    /// True when a `Bodies` frame will carry this file's hunks, or when the previous revision's
    /// hunks are inherited.
    public var body: Bool

    public init(
        path: String, oldPath: String?, change: DiffEntryChange, content: DiffEntryContent,
        additions: Int, deletions: Int, body: Bool
    ) {
        self.path = path
        self.oldPath = oldPath
        self.change = change
        self.content = content
        self.additions = additions
        self.deletions = deletions
        self.body = body
    }
}

/// Source: `packages/protocol/src/binary-frames/diff.ts` `DiffStreamLine`.
public struct DiffStreamLine: Sendable, Hashable {
    public var kind: DiffStreamLineKind
    public var content: String
    public var runs: [DiffRun]?

    public init(kind: DiffStreamLineKind, content: String, runs: [DiffRun]? = nil) {
        self.kind = kind
        self.content = content
        self.runs = runs
    }
}

/// Source: `packages/protocol/src/binary-frames/diff.ts` `DiffStreamHunk`.
public struct DiffStreamHunk: Sendable, Hashable {
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    public var lines: [DiffStreamLine]

    public init(
        oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, lines: [DiffStreamLine]
    ) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

/// Source: `packages/protocol/src/binary-frames/diff.ts` `DiffBody`.
public struct DiffBody: Sendable, Hashable {
    public var path: String
    public var hunks: [DiffStreamHunk]

    public init(path: String, hunks: [DiffStreamHunk]) {
        self.path = path
        self.hunks = hunks
    }
}

/// Opcode `0x40`: a revision's file list and resolved shas.
public struct DiffBegin: Sendable, Hashable {
    public var slot: UInt8
    public var revision: Int
    public var baseRevision: Int
    public var baseSha: String
    public var headSha: String
    public var mergeBaseSha: String
    public var entries: [DiffEntry]

    public init(
        slot: UInt8, revision: Int, baseRevision: Int, baseSha: String, headSha: String,
        mergeBaseSha: String, entries: [DiffEntry]
    ) {
        self.slot = slot
        self.revision = revision
        self.baseRevision = baseRevision
        self.baseSha = baseSha
        self.headSha = headSha
        self.mergeBaseSha = mergeBaseSha
        self.entries = entries
    }
}

/// Opcode `0x41`: hunks for the files whose `body` flag was set in `Begin`.
public struct DiffBodies: Sendable, Hashable {
    public var slot: UInt8
    public var revision: Int
    public var files: [DiffBody]

    public init(slot: UInt8, revision: Int, files: [DiffBody]) {
        self.slot = slot
        self.revision = revision
        self.files = files
    }
}

/// Opcode `0x42`: commits the revision. `End`, not a body count, is what makes a snapshot ready.
public struct DiffEnd: Sendable, Hashable {
    public var slot: UInt8
    public var revision: Int
    public var diffTooLarge: Bool
    public var omitted: [String]
    public var error: DiffError?

    public init(
        slot: UInt8, revision: Int, diffTooLarge: Bool, omitted: [String], error: DiffError?
    ) {
        self.slot = slot
        self.revision = revision
        self.diffTooLarge = diffTooLarge
        self.omitted = omitted
        self.error = error
    }
}

/// One decoded binary frame. Unknown diff opcodes in the `0x40...0x4f` range are preserved so a
/// newer daemon's additions are skipped without tearing the subscription down.
public enum DiffFrame: Sendable, Hashable {
    case begin(DiffBegin)
    case bodies(DiffBodies)
    case end(DiffEnd)
    case unknown(opcode: UInt8, slot: UInt8, payload: Data)

    public var slot: UInt8 {
        switch self {
        case .begin(let frame): return frame.slot
        case .bodies(let frame): return frame.slot
        case .end(let frame): return frame.slot
        case .unknown(_, let slot, _): return slot
        }
    }

    public var opcode: UInt8 {
        switch self {
        case .begin: return DiffOpcode.begin.rawValue
        case .bodies: return DiffOpcode.bodies.rawValue
        case .end: return DiffOpcode.end.rawValue
        case .unknown(let opcode, _, _): return opcode
        }
    }
}

/// Decodes the `0x40`–`0x4f` diff frame space. Layout:
/// `opcode | slot | version=1 | revision:varint` then opcode-specific fields.
///
/// Returns nil for a malformed known frame and for bytes outside the diff opcode range. An unknown
/// opcode inside the range decodes to `.unknown` so it can be ignored by opcode.
public enum DiffFrameCodec {
    /// Source: `packages/protocol/src/binary-frames/diff.ts` `DIFF_HIGHLIGHT_STYLES`.
    public static let highlightStyles: [String?] = [
        nil, "keyword", "comment", "string", "number", "literal", "function", "definition", "class",
        "type", "tag", "attribute", "property", "variable", "operator", "punctuation", "regexp",
        "escape", "meta", "heading", "link",
    ]

    public static func decode(_ data: Data) -> DiffFrame? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }
        let opcode = bytes[0]
        let slot = bytes[1]
        guard (0x40...0x4f).contains(opcode) else { return nil }

        guard opcode == DiffOpcode.begin.rawValue || opcode == DiffOpcode.bodies.rawValue
            || opcode == DiffOpcode.end.rawValue
        else {
            return .unknown(opcode: opcode, slot: slot, payload: Data(bytes.dropFirst(2)))
        }

        var reader = Reader(bytes)
        guard reader.byte() == opcode, reader.byte() == slot else { return nil }
        guard reader.byte() == 1 else { return nil }
        guard let revision = reader.uint() else { return nil }

        let frame: DiffFrame
        if opcode == DiffOpcode.begin.rawValue {
            guard let baseRevision = reader.uint(),
                let baseSha = reader.string(),
                let headSha = reader.string(),
                let mergeBaseSha = reader.string(),
                let count = reader.count()
            else { return nil }
            var entries: [DiffEntry] = []
            entries.reserveCapacity(count)
            for _ in 0..<count {
                guard let path = reader.string(),
                    let oldPath = reader.string(),
                    let changeIndex = reader.byte(),
                    let contentIndex = reader.byte(),
                    let additions = reader.uint(),
                    let deletions = reader.uint(),
                    let bodyByte = reader.byte(),
                    changeIndex < DiffEntryChange.wireValues.count,
                    contentIndex < DiffEntryContent.wireValues.count,
                    bodyByte <= 1
                else { return nil }
                let content = DiffEntryContent(
                    wireValue: DiffEntryContent.wireValues[Int(contentIndex)])
                if content == .binary, bodyByte == 1 { return nil }
                entries.append(
                    DiffEntry(
                        path: path,
                        oldPath: oldPath.isEmpty ? nil : oldPath,
                        change: DiffEntryChange(wireValue: DiffEntryChange.wireValues[Int(changeIndex)]),
                        content: content,
                        additions: additions,
                        deletions: deletions,
                        body: bodyByte == 1))
            }
            frame = .begin(
                DiffBegin(
                    slot: slot, revision: revision, baseRevision: baseRevision, baseSha: baseSha,
                    headSha: headSha, mergeBaseSha: mergeBaseSha, entries: entries))
        } else if opcode == DiffOpcode.bodies.rawValue {
            guard let count = reader.count() else { return nil }
            var files: [DiffBody] = []
            files.reserveCapacity(count)
            for _ in 0..<count {
                guard let path = reader.string(), let hunkCount = reader.count() else { return nil }
                var hunks: [DiffStreamHunk] = []
                hunks.reserveCapacity(hunkCount)
                for _ in 0..<hunkCount {
                    guard let oldStart = reader.uint(),
                        let oldCount = reader.uint(),
                        let newStart = reader.uint(),
                        let newCount = reader.uint(),
                        let lineCount = reader.count()
                    else { return nil }
                    var lines: [DiffStreamLine] = []
                    lines.reserveCapacity(lineCount)
                    for _ in 0..<lineCount {
                        guard let line = reader.line() else { return nil }
                        lines.append(line)
                    }
                    hunks.append(
                        DiffStreamHunk(
                            oldStart: oldStart, oldCount: oldCount, newStart: newStart,
                            newCount: newCount, lines: lines))
                }
                files.append(DiffBody(path: path, hunks: hunks))
            }
            frame = .bodies(DiffBodies(slot: slot, revision: revision, files: files))
        } else {
            guard let flags = reader.byte(), flags <= 1, let count = reader.count() else { return nil }
            var omitted: [String] = []
            omitted.reserveCapacity(count)
            for _ in 0..<count {
                guard let path = reader.string() else { return nil }
                omitted.append(path)
            }
            guard let codeIndex = reader.byte(), codeIndex <= 5, let message = reader.string() else {
                return nil
            }
            let error: DiffError? =
                if codeIndex == 0 {
                    nil
                } else {
                    DiffError(code: DiffErrorCode(wireValue: Self.errorWireValues[Int(codeIndex)]), message: message)
                }
            frame = .end(
                DiffEnd(
                    slot: slot, revision: revision, diffTooLarge: flags == 1, omitted: omitted,
                    error: error))
        }

        guard reader.isAtEnd else { return nil }
        return frame
    }

    /// Encodes a frame in the same layout. Returns nil when the frame would be rejected on decode
    /// (invalid run coverage, binary entry with a body, unknown enum string, …).
    public static func encode(_ frame: DiffFrame) -> Data? {
        var writer = Writer()
        writer.byte(frame.opcode)
        writer.byte(frame.slot)
        writer.byte(1)
        switch frame {
        case .begin(let begin):
            writer.uint(begin.revision)
            writer.uint(begin.baseRevision)
            writer.string(begin.baseSha)
            writer.string(begin.headSha)
            writer.string(begin.mergeBaseSha)
            writer.uint(begin.entries.count)
            for entry in begin.entries {
                guard let changeIndex = DiffEntryChange.wireValues.firstIndex(of: entry.change.wireValue),
                    let contentIndex = DiffEntryContent.wireValues.firstIndex(of: entry.content.wireValue),
                    !(entry.content == .binary && entry.body)
                else { return nil }
                writer.string(entry.path)
                writer.string(entry.oldPath ?? "")
                writer.byte(UInt8(changeIndex))
                writer.byte(UInt8(contentIndex))
                writer.uint(entry.additions)
                writer.uint(entry.deletions)
                writer.byte(entry.body ? 1 : 0)
            }

        case .bodies(let bodies):
            writer.uint(bodies.revision)
            writer.uint(bodies.files.count)
            for file in bodies.files {
                writer.string(file.path)
                writer.uint(file.hunks.count)
                for hunk in file.hunks {
                    writer.uint(hunk.oldStart)
                    writer.uint(hunk.oldCount)
                    writer.uint(hunk.newStart)
                    writer.uint(hunk.newCount)
                    writer.uint(hunk.lines.count)
                    for line in hunk.lines {
                        guard let kindIndex = DiffStreamLineKind.wireValues.firstIndex(of: line.kind.wireValue),
                            writer.writeLine(line, kindIndex: kindIndex)
                        else { return nil }
                    }
                }
            }

        case .end(let end):
            writer.uint(end.revision)
            writer.byte(end.diffTooLarge ? 1 : 0)
            writer.uint(end.omitted.count)
            for path in end.omitted { writer.string(path) }
            if let error = end.error {
                guard let index = Self.errorWireValues.firstIndex(of: error.code.wireValue) else {
                    return nil
                }
                writer.byte(UInt8(index))
                writer.string(error.message)
            } else {
                writer.byte(0)
                writer.string("")
            }

        case .unknown:
            // Unknown frames are decoded for their slot only; re-encoding the opaque payload is
            // not a supported shape.
            return nil
        }
        return writer.finish()
    }

    static let errorWireValues = [
        "", "NOT_GIT_REPO", "REF_NOT_FOUND", "INVALID_COMPARE", "TOO_MANY_SUBSCRIPTIONS", "UNKNOWN",
    ]

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        var remaining: Int { bytes.count - offset }
        var isAtEnd: Bool { offset == bytes.count }

        mutating func byte() -> UInt8? {
            guard offset < bytes.count else { return nil }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func uint() -> Int? {
            var value = 0
            var factor = 1
            for _ in 0..<8 {
                guard let byte = byte() else { return nil }
                let digit = Int(byte & 0x7f)
                if digit > 0, factor > (Int.max - value) / digit { return nil }
                value += digit * factor
                if byte < 0x80 { return value }
                if factor > Int.max / 128 { return nil }
                factor *= 128
            }
            return nil
        }

        mutating func count() -> Int? {
            guard let value = uint(), value <= remaining else { return nil }
            return value
        }

        mutating func string() -> String? {
            guard let size = count() else { return nil }
            let start = offset
            offset += size
            guard let value = String(bytes: bytes[start..<offset], encoding: .utf8) else { return nil }
            return value
        }

        mutating func line() -> DiffStreamLine? {
            guard let flags = byte() else { return nil }
            let kindIndex = Int(flags & 0x7f)
            let hasRuns = flags & 0x80 != 0
            guard kindIndex < DiffStreamLineKind.wireValues.count,
                let content = string(),
                let count = count()
            else { return nil }
            if !hasRuns {
                guard count == 0 else { return nil }
                return DiffStreamLine(
                    kind: DiffStreamLineKind(wireValue: DiffStreamLineKind.wireValues[kindIndex]),
                    content: content, runs: nil)
            }

            var runs: [DiffRun] = []
            runs.reserveCapacity(count)
            var coverage = 0
            for _ in 0..<count {
                guard let styleIndex = byte(), let length = uint(), length > 0 else { return nil }
                let style = Int(styleIndex) < DiffFrameCodec.highlightStyles.count
                    ? DiffFrameCodec.highlightStyles[Int(styleIndex)] : nil
                coverage += length
                runs.append(DiffRun(style: style, length: length))
            }
            if coverage != content.utf16.count { return nil }
            return DiffStreamLine(
                kind: DiffStreamLineKind(wireValue: DiffStreamLineKind.wireValues[kindIndex]),
                content: content, runs: runs)
        }
    }

    private struct Writer {
        private var bytes: [UInt8] = []

        mutating func byte(_ value: UInt8) { bytes.append(value) }

        mutating func uint(_ value: Int) {
            var value = max(0, value)
            repeat {
                let next = UInt8(value % 128)
                value /= 128
                byte(next + (value > 0 ? UInt8(128) : 0))
            } while value > 0
        }

        mutating func string(_ value: String) {
            let encoded = Array(value.utf8)
            uint(encoded.count)
            bytes.append(contentsOf: encoded)
        }

        mutating func writeLine(_ line: DiffStreamLine, kindIndex: Int) -> Bool {
            if let runs = line.runs {
                let coverage = runs.reduce(0) { $0 + $1.length }
                guard coverage == line.content.utf16.count, runs.allSatisfy({ $0.length > 0 }) else {
                    return false
                }
            }
            byte(UInt8(kindIndex) | (line.runs == nil ? 0 : 0x80))
            string(line.content)
            guard let runs = line.runs else {
                uint(0)
                return true
            }
            uint(runs.count)
            for run in runs {
                let index = run.style.flatMap { DiffFrameCodec.highlightStyles.firstIndex(of: $0) } ?? 0
                byte(UInt8(index))
                uint(run.length)
            }
            return true
        }

        func finish() -> Data { Data(bytes) }
    }
}

extension DiffEntryChange {
    init(wireValue: String) {
        switch wireValue {
        case "added": self = .added
        case "modified": self = .modified
        case "deleted": self = .deleted
        case "renamed": self = .renamed
        case let other: self = .unknown(other)
        }
    }

    var wireValue: String {
        switch self {
        case .added: return "added"
        case .modified: return "modified"
        case .deleted: return "deleted"
        case .renamed: return "renamed"
        case .unknown(let raw): return raw
        }
    }
}

extension DiffEntryContent {
    init(wireValue: String) {
        switch wireValue {
        case "text": self = .text
        case "binary": self = .binary
        case let other: self = .unknown(other)
        }
    }

    var wireValue: String {
        switch self {
        case .text: return "text"
        case .binary: return "binary"
        case .unknown(let raw): return raw
        }
    }
}

extension DiffStreamLineKind {
    init(wireValue: String) {
        switch wireValue {
        case "context": self = .context
        case "add": self = .add
        case "remove": self = .remove
        case "header": self = .header
        case let other: self = .unknown(other)
        }
    }

    var wireValue: String {
        switch self {
        case .context: return "context"
        case .add: return "add"
        case .remove: return "remove"
        case .header: return "header"
        case .unknown(let raw): return raw
        }
    }
}

/// Source: messages.ts `DiffErrorSchema` code enum, positionally as the binary End frame indexes it.
extension DiffErrorCode {
    init(wireValue: String) {
        switch wireValue {
        case "NOT_GIT_REPO": self = .notGitRepo
        case "REF_NOT_FOUND": self = .refNotFound
        case "INVALID_COMPARE": self = .invalidCompare
        case "TOO_MANY_SUBSCRIPTIONS": self = .tooManySubscriptions
        case "UNKNOWN": self = .unknownCode
        case let other: self = .unknown(other)
        }
    }
}

// MARK: - Assembled diff

/// A committed revision, materialized into the same `ParsedDiffFile` the legacy JSON stream uses.
public struct DiffSnapshot: Sendable, Hashable {
    public var revision: Int
    public var baseRevision: Int
    public var baseSha: String
    public var headSha: String
    public var mergeBaseSha: String
    public var files: [ParsedDiffFile]
    public var diffTooLarge: Bool
    public var omitted: [String]

    public init(
        revision: Int, baseRevision: Int, baseSha: String, headSha: String, mergeBaseSha: String,
        files: [ParsedDiffFile], diffTooLarge: Bool, omitted: [String]
    ) {
        self.revision = revision
        self.baseRevision = baseRevision
        self.baseSha = baseSha
        self.headSha = headSha
        self.mergeBaseSha = mergeBaseSha
        self.files = files
        self.diffTooLarge = diffTooLarge
        self.omitted = omitted
    }

    public var additions: Int { files.reduce(0) { $0 + $1.additions } }
    public var deletions: Int { files.reduce(0) { $0 + $1.deletions } }
}

/// What `DiffStreamAssembler.receive` produces. `End` commits a revision; partial frames before it
/// only update the loading state.
public enum DiffStreamEvent: Sendable, Hashable {
    case loading(entries: [DiffEntry])
    case ready(DiffSnapshot)
    case failed(DiffError)
}

/// Owns revision assembly for one slot. This mirrors `DiffStream` in
/// `packages/client/src/diff/stream.ts`: bodies are buffered until `End`, and text files whose
/// `body` flag is false inherit the previous revision's hunks.
public struct DiffStreamAssembler: Sendable {
    private struct Pending {
        var begin: DiffBegin
        var bodies: [String: DiffBody]
    }

    private var pending: Pending?
    private var committed: DiffSnapshot?

    public init() {}

    public var committedSnapshot: DiffSnapshot? { committed }

    public mutating func reset() {
        pending = nil
        committed = nil
    }

    public mutating func receive(_ frame: DiffFrame) -> DiffStreamEvent? {
        switch frame {
        case .begin(let begin):
            if begin.baseRevision != 0, begin.baseRevision != committed?.revision {
                return failed("Unknown diff base revision")
            }
            if Set(begin.entries.map(\.path)).count != begin.entries.count {
                return failed("Duplicate diff entry")
            }
            pending = Pending(begin: begin, bodies: [:])
            if committed == nil {
                return .loading(entries: begin.entries)
            }
            return nil

        case .bodies(let bodies):
            guard var current = pending, bodies.revision == current.begin.revision else { return nil }
            for body in bodies.files {
                if current.bodies[body.path] != nil { return failed("Duplicate diff body") }
                guard let entry = current.begin.entries.first(where: { $0.path == body.path }),
                    entry.body
                else {
                    return failed("Unexpected diff body")
                }
                current.bodies[body.path] = body
            }
            pending = current
            return nil

        case .end(let end):
            guard let current = pending, end.revision == current.begin.revision else { return nil }
            pending = nil
            if let error = end.error {
                committed = nil
                return .failed(error)
            }
            let omitted = Set(end.omitted)
            guard omitted.allSatisfy({ path in current.begin.entries.contains { $0.path == path } })
            else {
                return failed("Unknown omitted diff path")
            }

            let previous = Dictionary(
                (committed?.files ?? []).map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            var files: [ParsedDiffFile] = []
            files.reserveCapacity(current.begin.entries.count)
            for entry in current.begin.entries {
                let old = previous[entry.path]
                let body = current.bodies[entry.path]
                let isOmitted = omitted.contains(entry.path)
                if entry.content == .text, !isOmitted, entry.body, body == nil {
                    return failed("Missing diff body: \(entry.path)")
                }
                if entry.content == .text, !entry.body, !isOmitted,
                    old == nil || current.begin.baseRevision == 0
                {
                    return failed("Missing inherited diff: \(entry.path)")
                }
                var file = DiffMaterializer.file(
                    entry: entry, body: body, omitted: isOmitted)
                if entry.content == .text, !entry.body, !isOmitted, let old {
                    file.hunks = old.hunks
                    file.status = old.status
                }
                files.append(file)
            }

            let snapshot = DiffSnapshot(
                revision: current.begin.revision,
                baseRevision: current.begin.baseRevision,
                baseSha: current.begin.baseSha,
                headSha: current.begin.headSha,
                mergeBaseSha: current.begin.mergeBaseSha,
                files: files,
                diffTooLarge: end.diffTooLarge,
                omitted: end.omitted)
            committed = snapshot
            return .ready(snapshot)

        case .unknown:
            return nil
        }
    }

    private mutating func failed(_ message: String) -> DiffStreamEvent {
        pending = nil
        return .failed(DiffError(code: .unknownCode, message: message))
    }
}

/// Turns a diff entry plus its hunks into the legacy `ParsedDiffFile` shape, so the UI renders one
/// type for both pipelines.
public enum DiffMaterializer {
    public static func file(entry: DiffEntry, body: DiffBody?, omitted: Bool) -> ParsedDiffFile {
        let status: ParsedDiffFileStatus =
            switch entry.content {
            case .binary: .binary
            case .unknown: .binary
            case .text: omitted ? .tooLarge : .ok
            }
        let hunks = (body?.hunks ?? []).map { hunk in
            DiffHunk(
                oldStart: hunk.oldStart, oldCount: hunk.oldCount, newStart: hunk.newStart,
                newCount: hunk.newCount,
                lines: hunk.lines.map { line in
                    DiffLine(
                        type: line.kind.diffLineType, content: line.content,
                        tokens: line.runs.map { tokens(for: $0, content: line.content) })
                })
        }
        return ParsedDiffFile(
            path: entry.path,
            oldPath: entry.oldPath,
            isNew: entry.change == .added,
            isDeleted: entry.change == .deleted,
            additions: entry.additions,
            deletions: entry.deletions,
            hunks: hunks,
            status: status)
    }

    /// Splits a line by run lengths measured in UTF-16 code units, as the JS encoder does.
    public static func tokens(for runs: [DiffRun], content: String) -> [DiffHighlightToken] {
        let units = Array(content.utf16)
        var tokens: [DiffHighlightToken] = []
        var offset = 0
        for run in runs {
            let end = min(offset + max(run.length, 0), units.count)
            guard offset <= end else { break }
            let slice = units[offset..<end]
            tokens.append(
                DiffHighlightToken(
                    text: String(decoding: slice, as: UTF16.self), style: run.style))
            offset = end
        }
        return tokens
    }
}

extension DiffStreamLine {
    /// Tokens for this line, or nil when it carries no runs.
    public var tokens: [DiffHighlightToken]? {
        guard let runs else { return nil }
        return DiffMaterializer.tokens(for: runs, content: content)
    }
}

// MARK: - Git mutations

/// Source: messages.ts `CheckoutDiscardChangesRequestSchema`,
/// `CheckoutDiscardChangesResponseSchema`.
public struct CheckoutDiscardChangesRequest: PaseoRequest {
    public static let type = "checkout.discard_changes.request"
    public static let responseType = "checkout.discard_changes.response"
    public var requestId = ""
    public var cwd: String
    public var paths: [String]

    public init(cwd: String, paths: [String]) {
        self.cwd = cwd
        self.paths = paths
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var cwd: String
        public var success: Bool
        public var error: CheckoutError?

        public init(requestId: String, cwd: String, success: Bool, error: CheckoutError?) {
            self.requestId = requestId
            self.cwd = cwd
            self.success = success
            self.error = error
        }
    }
}

/// Source: messages.ts `BranchSuggestionsResponseSchema.branchDetails`.
public struct BranchSuggestion: Sendable, Hashable, Decodable {
    public var name: String
    /// Unix seconds, as the daemon sends it.
    public var committerDate: Double
    public var hasLocal: Bool?
    public var hasRemote: Bool?
    public var localAhead: Int?
    public var localBehind: Int?

    public init(
        name: String, committerDate: Double = 0, hasLocal: Bool? = nil, hasRemote: Bool? = nil,
        localAhead: Int? = nil, localBehind: Int? = nil
    ) {
        self.name = name
        self.committerDate = committerDate
        self.hasLocal = hasLocal
        self.hasRemote = hasRemote
        self.localAhead = localAhead
        self.localBehind = localBehind
    }
}

/// Source: messages.ts `BranchSuggestionsRequestSchema`, `BranchSuggestionsResponseSchema`.
public struct BranchSuggestionsRequest: PaseoRequest {
    public static let type = "branch_suggestions_request"
    public static let responseType = "branch_suggestions_response"
    public var requestId = ""
    public var cwd: String
    public var query: String?
    public var limit: Int?
    public var refMode: String?

    public init(cwd: String, query: String? = nil, limit: Int? = nil, refMode: String? = nil) {
        self.cwd = cwd
        self.query = query
        self.limit = limit
        self.refMode = refMode
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var branches: [String]
        public var branchDetails: [BranchSuggestion]?
        public var error: String?

        public init(
            requestId: String, branches: [String], branchDetails: [BranchSuggestion]?,
            error: String?
        ) {
            self.requestId = requestId
            self.branches = branches
            self.branchDetails = branchDetails
            self.error = error
        }

        public var suggestions: [BranchSuggestion] {
            if let branchDetails, !branchDetails.isEmpty { return branchDetails }
            return branches.map { BranchSuggestion(name: $0) }
        }
    }
}

/// Source: messages.ts `CheckoutSwitchBranchResponseSchema.source`.
public enum CheckoutBranchSource: Sendable, Hashable, Decodable {
    case local, remote
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "local": self = .local
        case "remote": self = .remote
        case let other: self = .unknown(other)
        }
    }
}

/// Source: messages.ts `CheckoutSwitchBranchRequestSchema`,
/// `CheckoutSwitchBranchResponseSchema`. The request type is still the flat legacy name.
public struct CheckoutSwitchBranchRequest: PaseoRequest {
    public static let type = "checkout_switch_branch_request"
    public static let responseType = "checkout_switch_branch_response"
    public var requestId = ""
    public var cwd: String
    public var branch: String

    public init(cwd: String, branch: String) {
        self.cwd = cwd
        self.branch = branch
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var cwd: String
        public var success: Bool
        public var branch: String
        public var source: CheckoutBranchSource?
        public var error: CheckoutError?

        public init(
            requestId: String, cwd: String, success: Bool, branch: String,
            source: CheckoutBranchSource?, error: CheckoutError?
        ) {
            self.requestId = requestId
            self.cwd = cwd
            self.success = success
            self.branch = branch
            self.source = source
            self.error = error
        }
    }
}

// MARK: - PR status auth state

/// Source: messages.ts `ForgeAuthStateSchema` — `z.unknown()` on the wire, so decode the string but
/// never fail on an unrecognised value.
public enum ForgeAuthState: Sendable, Hashable {
    case authenticated, unauthenticated, cliMissing, noRemote, error
    case unknown(String)

    public init?(raw: String?) {
        guard let raw else { return nil }
        switch raw {
        case "authenticated": self = .authenticated
        case "unauthenticated": self = .unauthenticated
        case "cli_missing": self = .cliMissing
        case "no_remote": self = .noRemote
        case "error": self = .error
        default: self = .unknown(raw)
        }
    }
}

extension CheckoutPrStatusPayload {
    /// The forge auth state as a typed value, or nil when the daemon sent none.
    public var forgeAuthState: ForgeAuthState? { ForgeAuthState(raw: authStateText) }
}

// MARK: - Live files

/// Source: messages.ts `FileVersionSchema` status union.
public enum FileVersionStatus: Sendable, Hashable, Decodable {
    case ready, missing, error
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "ready": self = .ready
        case "missing": self = .missing
        case "error": self = .error
        case let other: self = .unknown(other)
        }
    }
}

/// Source: messages.ts `FileVersionSchema`. All three union branches are flattened; fields that do
/// not belong to a branch are nil.
public struct FileVersion: Sendable, Hashable, Decodable {
    public var status: FileVersionStatus
    public var cwd: String
    public var path: String
    public var size: Int?
    public var modifiedAt: String?
    public var revision: String?
    public var kind: FileExplorerFileKind?
    public var mimeType: String?
    public var error: String?

    public init(
        status: FileVersionStatus, cwd: String, path: String, size: Int? = nil,
        modifiedAt: String? = nil, revision: String? = nil, kind: FileExplorerFileKind? = nil,
        mimeType: String? = nil, error: String? = nil
    ) {
        self.status = status
        self.cwd = cwd
        self.path = path
        self.size = size
        self.modifiedAt = modifiedAt
        self.revision = revision
        self.kind = kind
        self.mimeType = mimeType
        self.error = error
    }

    private enum K: String, CodingKey {
        case status, cwd, path, size, modifiedAt, revision, kind, mimeType, error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        status = try c.decode(FileVersionStatus.self, forKey: .status)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        size = try c.decodeIfPresent(Int.self, forKey: .size)
        modifiedAt = try c.decodeIfPresent(String.self, forKey: .modifiedAt)
        revision = try c.decodeIfPresent(String.self, forKey: .revision)
        kind = try c.decodeIfPresent(FileExplorerFileKind.self, forKey: .kind)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    public var isReady: Bool { status == .ready }
    public var isMissing: Bool { status == .missing }
}

/// Source: messages.ts `FileSubscribeRequestSchema`, `FileSubscribeResponseSchema`.
public struct FileSubscribeRequest: PaseoRequest {
    public static let type = "fs.file.subscribe.request"
    public static let responseType = "fs.file.subscribe.response"
    public var requestId = ""
    public var cwd: String
    public var path: String
    public var subscriptionId: String?

    public init(cwd: String, path: String, subscriptionId: String? = nil) {
        self.cwd = cwd
        self.path = path
        self.subscriptionId = subscriptionId
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var subscriptionId: String
        public var initial: FileVersion

        public init(requestId: String, subscriptionId: String, initial: FileVersion) {
            self.requestId = requestId
            self.subscriptionId = subscriptionId
            self.initial = initial
        }
    }
}

/// Source: messages.ts `FileUnsubscribeRequestSchema`, `FileUnsubscribeResponseSchema`.
public struct FileUnsubscribeRequest: PaseoRequest {
    public static let type = "fs.file.unsubscribe.request"
    public static let responseType = "fs.file.unsubscribe.response"
    public var requestId = ""
    public var subscriptionId: String

    public init(subscriptionId: String) { self.subscriptionId = subscriptionId }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var subscriptionId: String

        public init(requestId: String, subscriptionId: String) {
            self.requestId = requestId
            self.subscriptionId = subscriptionId
        }
    }
}

/// Source: messages.ts `FileUpdateSchema`.
public struct FileUpdate: Sendable, Hashable, Decodable {
    public var subscriptionId: String
    public var version: FileVersion

    public init(subscriptionId: String, version: FileVersion) {
        self.subscriptionId = subscriptionId
        self.version = version
    }
}
