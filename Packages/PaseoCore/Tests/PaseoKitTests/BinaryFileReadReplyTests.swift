import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

/// V3: the daemon answers a binary `file_explorer_request` with `FileBegin`/`FileChunk…`/`FileEnd`
/// frames and **no** JSON response (`workspace-files-session.ts:298-331`). The connection closes
/// the request itself at `FileEnd`, exactly as upstream's client does
/// (`daemon-client.ts:7581-7675`), so the store's `send` returns and can read the assembled bytes.
@Suite struct BinaryFileReadReplyTests {
    private nonisolated static func frame(_ frame: FileTransferFrame) throws -> Data {
        try FileTransferFrameCodec.encode(frame)
    }

    private nonisolated static func begin(size: Int, requestId: String) throws -> Data {
        try frame(
            .begin(
                requestId: requestId,
                metadata: FileBeginMetadata(
                    mime: "video/mp4", size: size, encoding: .binary,
                    modifiedAt: "2026-11-15T12:00:00.000Z", revision: "rev-1")))
    }

    @Test func aBinaryFileReadIsClosedByItsEndFrame() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)
        let log = EventLog()
        let logTask = log.start(connection.events)

        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.push(text: try fixtureText("server_info"))
        _ = try await awaitValue(connectTask)

        var request = FileExplorerRequest(
            cwd: "/tmp/sandbox", mode: .file, path: "clip.mp4", maxBytes: 4096,
            acceptBinary: true)
        request.requestId = "read-1"
        let sendTask = Task { try await connection.send(request, timeout: .seconds(3)) }
        try await waitUntil {
            outboundMessage(ofType: FileExplorerRequest.type, in: transport) != nil
        }

        transport.push(.binary(try Self.begin(size: 3, requestId: "read-1")))
        transport.push(
            .binary(try Self.frame(.chunk(requestId: "read-1", payload: Data([1, 2, 3])))))
        transport.push(.binary(try Self.frame(.end(requestId: "read-1"))))

        let response = try await awaitValue(sendTask)
        #expect(response.requestId == "read-1")
        #expect(response.cwd == "/tmp/sandbox")
        #expect(response.path == "clip.mp4")
        #expect(response.mode == .file)
        // No inline file and no error: the bytes came as frames, and the store judges them.
        #expect(response.file == nil)
        #expect(response.error == nil)

        // The same frames reach the store, which assembles the file.
        try await waitUntil {
            log.events.filter {
                if case .binaryFrame = $0 { return true }
                return false
            }.count == 3
        }
        logTask.cancel()
    }

    @Test func aFileEndForAnotherRequestDoesNotSettleIt() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)
        let logTask = EventLog().start(connection.events)

        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.push(text: try fixtureText("server_info"))
        _ = try await awaitValue(connectTask)

        var request = FetchAgentsRequest()
        request.requestId = "keep-1"
        let sendTask = Task { try await connection.send(request, timeout: .seconds(3)) }
        try await waitUntil {
            outboundMessage(ofType: FetchAgentsRequest.type, in: transport) != nil
        }

        // A stray transfer with the same id: the request did not ask for one, so it stays open.
        transport.push(.binary(try Self.begin(size: 3, requestId: "keep-1")))
        transport.push(.binary(try Self.frame(.end(requestId: "keep-1"))))

        transport.push(text: try fixtureResponse("fetch_agents_response", requestId: "keep-1"))
        let response = try await awaitValue(sendTask)
        #expect(!response.entries.isEmpty)
        logTask.cancel()
    }
}
