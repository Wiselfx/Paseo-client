import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

@Suite
struct GitExtrasWireTests {
    private func payload<P: Decodable & Sendable>(_ name: String, as type: P.Type) throws -> P {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<P>.self, from: Fixture.data(name, in: "git-extras")
        ).payload
    }

    @Test func decodesCapturedGitExtraResponses() throws {
        let suggestions = try payload(
            "branch_suggestions_response", as: BranchSuggestionsRequest.Response.self)
        #expect(suggestions.branches == ["feature/t11"])
        #expect(suggestions.error == nil)
        let suggestion = try #require(suggestions.suggestions.first)
        #expect(suggestion.name == "feature/t11")
        #expect(suggestion.hasLocal == true)
        #expect(suggestion.hasRemote == true)
        #expect(suggestion.localAhead == 0)
        #expect(suggestion.localBehind == 0)

        let discard = try payload(
            "checkout_discard_changes_response", as: CheckoutDiscardChangesRequest.Response.self)
        #expect(discard.success)
        #expect(discard.error == nil)

        let switched = try payload(
            "checkout_switch_branch_response", as: CheckoutSwitchBranchRequest.Response.self)
        #expect(switched.success)
        #expect(switched.branch == "feature/t11")
        #expect(switched.source == .local)

        let subscribed = try payload(
            "fs_file_subscribe_response", as: FileSubscribeRequest.Response.self)
        #expect(subscribed.subscriptionId.isEmpty == false)
        #expect(subscribed.initial.status == .ready)
        #expect(subscribed.initial.path == "README.md")
        #expect(subscribed.initial.kind == .text)
        #expect(subscribed.initial.modifiedAt != nil)

        let update = try payload("fs_file_update_00", as: FileUpdate.self)
        #expect(update.subscriptionId == subscribed.subscriptionId)
        #expect(update.version.size == 42)
        #expect(update.version.isReady)

        let unsubscribed = try payload(
            "fs_file_unsubscribe_response", as: FileUnsubscribeRequest.Response.self)
        #expect(unsubscribed.subscriptionId == subscribed.subscriptionId)

        let pr = try payload("checkout_pr_status_response", as: CheckoutPrStatusPayload.self)
        #expect(pr.status == nil)
        #expect(pr.githubFeaturesEnabled == false)
        #expect(pr.error == nil)
        #expect(pr.forgeAuthState == .noRemote)
    }

    @Test func decodesTheCapturedServerInfoWithoutTheModernDiffFlag() throws {
        let info = try payload("server_info", as: ServerInfo.self)
        #expect(info.serverId == "srv_FIXTURE")
        #expect(info.hasFeature("diffSubscription") == false)
        #expect(info.hasFeature("checkoutDiscardChanges") == true)
        #expect(info.hasFeature("workspaceFileEditing") == true)
    }

    @Test func decodesTheUpstreamBeginAndBodiesVectors() throws {
        // Fixed bytes from `packages/protocol/src/binary-frames/diff.test.ts`.
        let beginBytes: [UInt8] = [64, 0, 1, 1, 0, 0, 0, 0, 0]
        let begin = try #require(DiffFrameCodec.decode(Data(beginBytes)))
        guard case .begin(let beginFrame) = begin else {
            Issue.record("expected a Begin frame")
            return
        }
        #expect(beginFrame.slot == 0)
        #expect(beginFrame.revision == 1)
        #expect(beginFrame.baseRevision == 0)
        #expect(beginFrame.entries.isEmpty)

        let bodiesBytes: [UInt8] = [
            65, 0, 1, 1, 1, 1, 120, 1, 0, 0, 1, 1, 1, 129, 7, 240, 159, 152, 128, 101, 204, 129,
            1, 3, 4,
        ]
        let bodies = try #require(DiffFrameCodec.decode(Data(bodiesBytes)))
        guard case .bodies(let bodiesFrame) = bodies else {
            Issue.record("expected a Bodies frame")
            return
        }
        let file = try #require(bodiesFrame.files.first)
        #expect(file.path == "x")
        let line = try #require(file.hunks.first?.lines.first)
        #expect(line.kind == .add)
        #expect(line.content == "😀é")
        let token = try #require(line.tokens?.first)
        #expect(token.text == "😀é", "runs count UTF-16 units, not bytes or characters")
        #expect(token.style == "string")
    }

    @Test func rejectsTruncatedAndMalformedFrames() throws {
        let bytes: [UInt8] = [
            65, 0, 1, 1, 1, 1, 120, 1, 0, 0, 1, 1, 1, 129, 7, 240, 159, 152, 128, 101, 204, 129,
            1, 3, 4,
        ]
        for length in 0..<bytes.count {
            #expect(DiffFrameCodec.decode(Data(bytes.prefix(length))) == nil)
        }
        var wrongVersion = bytes
        wrongVersion[2] = 2
        #expect(DiffFrameCodec.decode(Data(wrongVersion)) == nil)

        var trailing = bytes
        trailing.append(0)
        #expect(DiffFrameCodec.decode(Data(trailing)) == nil)

        var badCoverage = bytes
        badCoverage[24] = 5
        #expect(DiffFrameCodec.decode(Data(badCoverage)) == nil)
    }

    @Test func keepsUnknownDiffOpcodesAndIgnoresOtherFrameSpaces() throws {
        let unknown = try #require(DiffFrameCodec.decode(Data([0x43, 7, 1, 2, 3])))
        #expect(unknown.opcode == 0x43)
        #expect(unknown.slot == 7)
        #expect(DiffFrameCodec.decode(Data([0x43])) == nil)
        #expect(DiffFrameCodec.decode(Data([0x01, 0, 0])) == nil, "terminal frames are not diff frames")
    }

    @Test func roundTripsEndAndBodyFrames() throws {
        let end = DiffFrame.end(
            DiffEnd(
                slot: 9, revision: 300, diffTooLarge: true, omitted: ["a.ts"],
                error: DiffError(code: .refNotFound, message: "missing")))
        let encodedEnd = try #require(DiffFrameCodec.encode(end))
        #expect(DiffFrameCodec.decode(encodedEnd) == end)

        let bodies = DiffFrame.bodies(
            DiffBodies(
                slot: 2, revision: 128,
                files: [
                    DiffBody(
                        path: "README.md",
                        hunks: [
                            DiffStreamHunk(
                                oldStart: 1, oldCount: 1, newStart: 1, newCount: 2,
                                lines: [
                                    DiffStreamLine(kind: .context, content: "line", runs: nil),
                                    DiffStreamLine(
                                        kind: .add, content: "line two",
                                        runs: [
                                            DiffRun(style: "string", length: 4),
                                            DiffRun(style: nil, length: 4),
                                        ]),
                                ])
                        ])
                ]))
        let encodedBodies = try #require(DiffFrameCodec.encode(bodies))
        #expect(DiffFrameCodec.decode(encodedBodies) == bodies)
    }

    @Test func assemblesBodiesAndEndIntoTheLegacyFileShape() throws {
        let begin = DiffFrame.begin(
            DiffBegin(
                slot: 4, revision: 1, baseRevision: 0, baseSha: "base", headSha: "head",
                mergeBaseSha: "merge",
                entries: [
                    DiffEntry(
                        path: "README.md", oldPath: nil, change: .modified, content: .text,
                        additions: 1, deletions: 0, body: true),
                    DiffEntry(
                        path: "image.png", oldPath: nil, change: .added, content: .binary,
                        additions: 0, deletions: 0, body: false),
                ]))
        let bodies = DiffFrame.bodies(
            DiffBodies(
                slot: 4, revision: 1,
                files: [
                    DiffBody(
                        path: "README.md",
                        hunks: [
                            DiffStreamHunk(
                                oldStart: 1, oldCount: 1, newStart: 1, newCount: 2,
                                lines: [
                                    DiffStreamLine(kind: .add, content: "hello", runs: nil)
                                ])
                        ])
                ]))
        let end = DiffFrame.end(
            DiffEnd(slot: 4, revision: 1, diffTooLarge: false, omitted: [], error: nil))

        var assembler = DiffStreamAssembler()
        guard case .loading(let entries)? = assembler.receive(begin) else {
            Issue.record("Begin should publish the loading entries")
            return
        }
        #expect(entries.count == 2)
        #expect(assembler.receive(bodies) == nil)
        guard case .ready(let snapshot)? = assembler.receive(end) else {
            Issue.record("End should commit the revision")
            return
        }
        #expect(snapshot.revision == 1)
        #expect(snapshot.baseSha == "base")
        #expect(snapshot.files.count == 2)
        let readme = try #require(snapshot.files.first)
        #expect(readme.path == "README.md")
        #expect(readme.status == .ok)
        #expect(readme.hunks.first?.lines.first?.content == "hello")
        let image = try #require(snapshot.files.last)
        #expect(image.status == .binary)
        #expect(image.hunks.isEmpty)
        #expect(assembler.committedSnapshot == snapshot)
    }

    @Test func inheritedHunksSurviveAnIncrementalRevision() throws {
        var assembler = DiffStreamAssembler()
        _ = assembler.receive(
            .begin(
                DiffBegin(
                    slot: 1, revision: 1, baseRevision: 0, baseSha: "", headSha: "",
                    mergeBaseSha: "",
                    entries: [
                        DiffEntry(
                            path: "a.ts", oldPath: nil, change: .modified, content: .text,
                            additions: 1, deletions: 0, body: true)
                    ])))
        _ = assembler.receive(
            .bodies(
                DiffBodies(
                    slot: 1, revision: 1,
                    files: [
                        DiffBody(
                            path: "a.ts",
                            hunks: [
                                DiffStreamHunk(
                                    oldStart: 1, oldCount: 1, newStart: 1, newCount: 1,
                                    lines: [DiffStreamLine(kind: .add, content: "one")])
                            ])
                    ])))
        guard case .ready(let first)? = assembler.receive(
            .end(DiffEnd(slot: 1, revision: 1, diffTooLarge: false, omitted: [], error: nil)))
        else {
            Issue.record("first revision should commit")
            return
        }
        #expect(first.files.first?.hunks.first?.lines.first?.content == "one")

        _ = assembler.receive(
            .begin(
                DiffBegin(
                    slot: 1, revision: 2, baseRevision: 1, baseSha: "", headSha: "",
                    mergeBaseSha: "",
                    entries: [
                        DiffEntry(
                            path: "a.ts", oldPath: nil, change: .modified, content: .text,
                            additions: 1, deletions: 0, body: false),
                        DiffEntry(
                            path: "b.ts", oldPath: nil, change: .added, content: .text,
                            additions: 1, deletions: 0, body: true),
                    ])))
        _ = assembler.receive(
            .bodies(
                DiffBodies(
                    slot: 1, revision: 2,
                    files: [
                        DiffBody(
                            path: "b.ts",
                            hunks: [
                                DiffStreamHunk(
                                    oldStart: 0, oldCount: 0, newStart: 1, newCount: 1,
                                    lines: [DiffStreamLine(kind: .add, content: "two")])
                            ])
                    ])))
        guard case .ready(let second)? = assembler.receive(
            .end(DiffEnd(slot: 1, revision: 2, diffTooLarge: false, omitted: [], error: nil)))
        else {
            Issue.record("second revision should commit")
            return
        }
        #expect(second.files.count == 2)
        #expect(second.files[0].hunks.first?.lines.first?.content == "one", "body=false inherits hunks")
        #expect(second.files[1].hunks.first?.lines.first?.content == "two")
    }

    @Test func anEndErrorFailsAndClearsTheCommittedRevision() throws {
        var assembler = DiffStreamAssembler()
        _ = assembler.receive(
            .begin(
                DiffBegin(
                    slot: 3, revision: 1, baseRevision: 0, baseSha: "", headSha: "",
                    mergeBaseSha: "", entries: [])))
        guard case .ready? = assembler.receive(
            .end(DiffEnd(slot: 3, revision: 1, diffTooLarge: false, omitted: [], error: nil)))
        else {
            Issue.record("empty revision should commit")
            return
        }
        _ = assembler.receive(
            .begin(
                DiffBegin(
                    slot: 3, revision: 2, baseRevision: 1, baseSha: "", headSha: "",
                    mergeBaseSha: "", entries: [])))
        guard case .failed(let error)? = assembler.receive(
            .end(
                DiffEnd(
                    slot: 3, revision: 2, diffTooLarge: false, omitted: [],
                    error: DiffError(code: .invalidCompare, message: "bad compare"))))
        else {
            Issue.record("End with an error should fail the revision")
            return
        }
        #expect(error.code == .invalidCompare)
        #expect(assembler.committedSnapshot == nil)
    }

    @Test func missingBodiesFailOnlyWhenTheEntryPromisedOne() throws {
        var assembler = DiffStreamAssembler()
        _ = assembler.receive(
            .begin(
                DiffBegin(
                    slot: 5, revision: 1, baseRevision: 0, baseSha: "", headSha: "",
                    mergeBaseSha: "",
                    entries: [
                        DiffEntry(
                            path: "a.ts", oldPath: nil, change: .modified, content: .text,
                            additions: 1, deletions: 0, body: true)
                    ])))
        guard case .failed(let error)? = assembler.receive(
            .end(DiffEnd(slot: 5, revision: 1, diffTooLarge: false, omitted: [], error: nil)))
        else {
            Issue.record("a text entry with body=true and no bodies must fail")
            return
        }
        #expect(error.message.contains("Missing diff body"))
    }

    @Test func legacyComparisonMappingMatchesTheSDK() {
        let working = DiffCompare.working(cwd: "/tmp/repo")
        #expect(working.legacyCompare?.mode == .uncommitted)
        #expect(working.legacyCompare?.baseRef == nil)

        let base = DiffCompare.againstBase(cwd: "/tmp/repo", baseRef: "main")
        #expect(base.legacyCompare?.mode == .all)
        #expect(base.legacyCompare?.baseRef == "main")

        let headVsBase = DiffCompare(
            cwd: "/tmp/repo", base: .rev("main"), head: .rev("HEAD"), mergeBase: true)
        #expect(headVsBase.legacyCompare?.mode == .base)
        #expect(headVsBase.legacyCompare?.baseRef == "main")

        let index = DiffCompare(cwd: "/tmp/repo", base: .index, head: .worktree, mergeBase: true)
        #expect(index.legacyCompare == nil)
        let noHighlight = DiffCompare(
            cwd: "/tmp/repo", base: .rev("HEAD"), head: .worktree, highlight: false)
        #expect(noHighlight.legacyCompare == nil)
    }
}
