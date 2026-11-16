import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct ProjectConfigTests {
    // MARK: Fixture decoding (captured from the sandbox, scrubbed)

    @Test func readAfterWriteFixtureDecodesRealSandboxTraffic() throws {
        // Real sandbox capture: paseo.json existed at capture time (then deleted).
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<ReadProjectConfigRequest.Response>.self,
            from: Fixture.data("project_config_read_after_write_response", in: "project-config")).payload
        #expect(response.ok)
        let config = try #require(response.config)
        let setup = ProjectConfigEditor.lifecycleCommands(config["worktree"]?["setup"])
        #expect(setup == ["echo fixture-setup-ran"])
        let revision = try #require(response.revision)
        #expect(revision.mtimeMs == 1_700_000_000_000)
        #expect(revision.size == 273)
        #expect(response.hasUncommittedWorktreeSetupChanges == true)
    }

    @Test func readMissingConfigFixtureDecodesRealSandboxTraffic() throws {
        // Real sandbox capture: no paseo.json at that path.
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<ReadProjectConfigRequest.Response>.self,
            from: Fixture.data("project_config_read_response", in: "project-config")).payload
        #expect(response.ok)
        #expect(response.config == nil)
        #expect(response.revision == nil)
        #expect(response.hasUncommittedWorktreeSetupChanges == false)
    }

    @Test func writeResponseFixtureDecodesRealSandboxTraffic() throws {
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<WriteProjectConfigRequest.Response>.self,
            from: Fixture.data("project_config_write_response", in: "project-config")).payload
        #expect(response.ok)
        #expect(response.revision != nil)
        #expect(response.config?["scripts"]?["fixture-script"]?["command"]?.stringValue == "echo fixture-script-ran")
        #expect(response.error == nil)
    }

    @Test func iconGetFixtureDecodesRealSandboxTraffic() throws {
        // Real sandbox capture: the sandbox project has no custom icon (icon: null).
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<ProjectIconGetRequest.Response>.self,
            from: Fixture.data("project_icon_get_response", in: "project-config")).payload
        #expect(response.projectId == "prj_FIXTURE")
        #expect(response.icon == nil)
        #expect(response.error == nil)
    }

    // MARK: Store: load

    private func makeReadFixtureHandler(_ client: FakeDaemonClient) throws {
        let data = try Fixture.data(
            "project_config_read_after_write_response", in: "project-config")
        client.on(ReadProjectConfigRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<ReadProjectConfigRequest.Response>.self, from: data).payload
        }
    }

    @Test func loadPopulatesConfigAndRevision() async throws {
        let client = FakeDaemonClient()
        try makeReadFixtureHandler(client)
        let store = ProjectConfigStore(client: client)
        await store.load(repoRoot: "/fixture-sandbox")
        #expect(store.phase == .ready)
        #expect(store.revision != nil)
        let (setup, teardown) = ProjectConfigEditor.worktreeCommands(store.config)
        #expect(setup == ["echo fixture-setup-ran"])
        #expect(teardown == ["echo fixture-teardown-ran"])
        let scripts = ProjectConfigEditor.scripts(store.config)
        #expect(scripts.count == 1)
        #expect(scripts[0].name == "fixture-script")
        #expect(scripts[0].command == "echo fixture-script-ran")
        // raw preserved for round trip (type/port)
        if case .object(let raw) = scripts[0].raw {
            #expect(raw["type"] == .string("service"))
            if case .number(let port)? = raw["port"] { #expect(port == 4173) } else {
                Issue.record("expected port 4173 to round-trip")
            }
        } else {
            Issue.record("expected raw script entry to round-trip")
        }
        #expect(client.requests(ReadProjectConfigRequest.self).count == 1)
    }

    @Test func loadOnMissingConfigLeavesConfigNilButReady() async throws {
        let client = FakeDaemonClient()
        let data = try Fixture.data(
            "project_config_read_response", in: "project-config")
        client.on(ReadProjectConfigRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<ReadProjectConfigRequest.Response>.self, from: data).payload
        }
        let store = ProjectConfigStore(client: client)
        await store.load(repoRoot: "/fixture-sandbox")
        #expect(store.phase == .ready)
        #expect(store.config == nil)
        #expect(store.revision == nil)
    }

    @Test func loadErrorIsAnObservableFailure() async throws {
        let client = FakeDaemonClient()
        client.on(ReadProjectConfigRequest.self) { _ in
            let json = """
            {"type":"session","message":{"type":"read_project_config_response","payload":{
              "requestId":"r","repoRoot":"/fixture-sandbox","ok":false,
              "error":{"code":"project_not_found"}
            }}}
            """
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<ReadProjectConfigRequest.Response>.self,
                from: Data(json.utf8)).payload
        }
        let store = ProjectConfigStore(client: client)
        await store.load(repoRoot: "/fixture-sandbox")
        #expect(store.phase == .failed)
        #expect(store.error == .projectNotFound)
    }

    // MARK: Store: save

    @Test func saveSendsExpectedRevisionAndReArmsIt() async throws {
        let client = FakeDaemonClient()
        try makeReadFixtureHandler(client)
        let writeData = try Fixture.data(
            "project_config_write_response", in: "project-config")
        client.on(WriteProjectConfigRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<WriteProjectConfigRequest.Response>.self, from: writeData).payload
        }
        let store = ProjectConfigStore(client: client)
        await store.load(repoRoot: "/fixture-sandbox")
        let before = store.revision
        let ok = await store.save(
            repoRoot: "/fixture-sandbox",
            setup: ["echo fixture-setup-ran"],
            teardown: ["echo fixture-teardown-ran"],
            scripts: ProjectConfigEditor.scripts(store.config))
        #expect(ok == true)
        let sent = try #require(client.requests(WriteProjectConfigRequest.self).first)
        #expect(sent.expectedRevision == before)
        // revision re-armed from the write response
        #expect(store.revision == sent.expectedRevision)
        #expect(store.stale == false)
        #expect(store.error == nil)
    }

    @Test func staleWriteResponseSetsStaleAndKeepsLoadedConfig() async throws {
        let client = FakeDaemonClient()
        try makeReadFixtureHandler(client)
        client.on(WriteProjectConfigRequest.self) { _ in
            // Hand-written fixture shape (not captured): the daemon's stale conflict payload.
            let json = """
            {"type":"session","message":{"type":"write_project_config_response","payload":{
              "requestId":"r","repoRoot":"/fixture-sandbox","ok":false,
              "error":{"code":"stale_project_config",
                       "currentRevision":{"mtimeMs":1800000000000,"size":999}}
            }}}
            """
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<WriteProjectConfigRequest.Response>.self,
                from: Data(json.utf8)).payload
        }
        let store = ProjectConfigStore(client: client)
        await store.load(repoRoot: "/fixture-sandbox")
        let revisionBefore = store.revision
        let ok = await store.save(
            repoRoot: "/fixture-sandbox", setup: [], teardown: [], scripts: [])
        #expect(ok == false)
        #expect(store.stale == true)
        #expect(store.error == .staleProjectConfig(
            currentRevision: PaseoProjectConfigRevision(mtimeMs: 1_800_000_000_000, size: 999)))
        // The loaded config/revision are untouched; a reload is required to re-arm.
        #expect(store.revision == revisionBefore)
        #expect(store.config != nil)
    }

    @Test func writeFailedSurfacesObservableError() async throws {
        let client = FakeDaemonClient()
        try makeReadFixtureHandler(client)
        client.on(WriteProjectConfigRequest.self) { _ in
            let json = """
            {"type":"session","message":{"type":"write_project_config_response","payload":{
              "requestId":"r","repoRoot":"/fixture-sandbox","ok":false,
              "error":{"code":"write_failed"}
            }}}
            """
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<WriteProjectConfigRequest.Response>.self,
                from: Data(json.utf8)).payload
        }
        let store = ProjectConfigStore(client: client)
        await store.load(repoRoot: "/fixture-sandbox")
        let ok = await store.save(
            repoRoot: "/fixture-sandbox", setup: [], teardown: [], scripts: [])
        #expect(ok == false)
        #expect(store.error == .writeFailed)
        #expect(store.stale == false)
    }

    // MARK: Editor round-trip fidelity

    @Test func replacingPreservesUnknownKeysAndReplacesManagedKeys() throws {
        let base = JSONValue.object([
            "worktree": .object([
                "setup": .string("legacy single command"),
                "teardown": .array([.string("echo old-teardown")]),
                "servicePorts": .object(["range": .string("4000-4100")]),
                "terminals": .array([.object(["command": .string("vim")])]),
            ]),
            "scripts": .object([
                "keepme": .object([
                    "type": .string("service"), "command": .string("old-command"),
                    "port": .number(8080),
                ]),
                "dropme": .object(["type": .string("service"), "command": .string("bye")]),
            ]),
            "metadataGeneration": .object([
                "title": .object(["instructions": .string("write a title")]),
            ]),
            "futureDaemonKey": .object(["nested": .array([.number(1), .bool(true)])]),
        ])
        var scripts = ProjectConfigEditor.scripts(base)
        #expect(scripts.count == 2)
        scripts = scripts.map { script in
            guard script.name == "keepme" else { return script }
            var copy = script
            copy.command = "new-command"
            return copy
        }.filter { $0.name != "dropme" }
        let out = ProjectConfigEditor.replacing(
            config: base, setup: ["echo s1", "echo s2"], teardown: [], scripts: scripts)
        // worktree setup replaced, teardown dropped (empty), unknowns preserved
        let worktree = try #require(out["worktree"])
        #expect(ProjectConfigEditor.lifecycleCommands(worktree["setup"]) == ["echo s1", "echo s2"])
        #expect(worktree["teardown"] == nil)
        #expect(worktree["servicePorts"]?["range"]?.stringValue == "4000-4100")
        #expect(worktree["terminals"] != nil)
        // scripts: keepme rebuilt with new command + preserved type/port; dropme gone
        let keepme = try #require(out["scripts"]?["keepme"])
        #expect(keepme["command"]?.stringValue == "new-command")
        #expect(keepme["type"]?.stringValue == "service")
        if case .number(let port)? = keepme["port"] { #expect(port == 8080) } else {
            Issue.record("port must survive the round trip")
        }
        #expect(out["scripts"]?["dropme"] == nil)
        // untouched top-level keys
        #expect(out["metadataGeneration"] != nil)
        #expect(out["futureDaemonKey"] != nil)
    }

    @Test func replacingFromEmptyBaseBuildsMinimalConfig() throws {
        let out = ProjectConfigEditor.replacing(config: nil, setup: ["a"], teardown: [], scripts: [])
        #expect(ProjectConfigEditor.lifecycleCommands(out["worktree"]?["setup"]) == ["a"])
        #expect(out["scripts"] == nil)
        #expect(out["worktree"]?["setup"] != nil)
    }

    @Test func removingEverythingDropsTheEmptyObjects() throws {
        let base = JSONValue.object([
            "worktree": .object(["setup": .array([.string("x")])]),
            "scripts": .object(["s": .object(["command": .string("c")])]),
        ])
        let out = ProjectConfigEditor.replacing(config: base, setup: [], teardown: [], scripts: [])
        #expect(out["worktree"] == nil)
        #expect(out["scripts"] == nil)
    }

    @Test func worktreeCommandsToleratesSingleStringForm() throws {
        let (setup, teardown) = ProjectConfigEditor.worktreeCommands(
            .object(["worktree": .object(["setup": .string("npm ci"), "teardown": .string("docker compose down")])]))
        #expect(setup == ["npm ci"])
        #expect(teardown == ["docker compose down"])
    }

    // MARK: Wire encoding

    @Test func writeRequestEncodesExpectedRevisionAsExplicitNull() throws {
        let request = WriteProjectConfigRequest(repoRoot: "/fixture-sandbox", config: .object([:]), expectedRevision: nil)
        let data = try JSONEncoder().encode(SessionRequestEnvelope(request))
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let message = try #require(json["message"] as? [String: Any])
        #expect(json["type"] as? String == "session")
        #expect(message["type"] as? String == "write_project_config_request")
        #expect(message["repoRoot"] as? String == "/fixture-sandbox")
        #expect(message["expectedRevision"] is NSNull)
    }

    @Test func writeRequestEncodesRevisionObject() throws {
        let request = WriteProjectConfigRequest(
            repoRoot: "/fixture-sandbox", config: .object([:]),
            expectedRevision: PaseoProjectConfigRevision(mtimeMs: 1_700_000_000_000, size: 273))
        let data = try JSONEncoder().encode(SessionRequestEnvelope(request))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"mtimeMs\":1.7e+12") || text.contains("\"mtimeMs\":1700000000000"))
        #expect(text.contains("\"size\":273"))
    }

    // MARK: Icon store

    private func makeServerInfo(customIcon: Bool) throws -> ServerInfo {
        let json = """
        {"serverId":"srv_FIXTURE","version":"0.15.2","features":{"projectCustomIcon":\(customIcon)}}
        """
        return try JSONDecoder().decode(ServerInfo.self, from: Data(json.utf8))
    }

    private var onePixelPNG: Data {
        // 1x1 transparent PNG.
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
    }

    @Test func iconUploadSendsBase64AndReloads() async throws {
        let png = onePixelPNG
        let client = FakeDaemonClient()
        client.on(ProjectIconGetRequest.self) { _ in
            let payload: [String: Any] = [
                "requestId": "r", "projectId": "prj_FIXTURE",
                "icon": ["data": png.base64EncodedString(), "mimeType": "image/png"],
                "error": NSNull(),
            ]
            let json: [String: Any] = [
                "type": "session",
                "message": ["type": "project.icon.get.response", "payload": payload],
            ]
            let data = try JSONSerialization.data(withJSONObject: json)
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<ProjectIconGetRequest.Response>.self, from: data).payload
        }
        client.on(ProjectIconSetRequest.self) { _ in
            let json = """
            {"type":"session","message":{"type":"project.icon.set.response","payload":{
              "requestId":"r","projectId":"prj_FIXTURE","accepted":true,"error":null
            }}}
            """
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<ProjectIconSetRequest.Response>.self,
                from: Data(json.utf8)).payload
        }
        let store = ProjectIconStore(client: client)
        store.update(serverInfo: try makeServerInfo(customIcon: true))
        let ok = await store.setUpload(projectId: "prj_FIXTURE", data: png)
        #expect(ok == true)
        let sent = try #require(client.requests(ProjectIconSetRequest.self).first)
        #expect(sent.source == .upload(data: png.base64EncodedString()))
        // set reloads the icon afterwards
        #expect(client.requests(ProjectIconGetRequest.self).count == 1)
        #expect(store.iconData == png)
        #expect(store.error == nil)
    }

    @Test func iconSetWithoutTheGateIsAnObservableError() async throws {
        let client = FakeDaemonClient()
        let store = ProjectIconStore(client: client)
        // gate not opened (no server_info seen)
        let ok = await store.setUpload(projectId: "prj_FIXTURE", data: onePixelPNG)
        #expect(ok == false)
        #expect(store.error == "This host cannot set project icons.")
        #expect(client.requests(ProjectIconSetRequest.self).isEmpty)
    }

    @Test func iconResetSendsAutomaticSource() async throws {
        let client = FakeDaemonClient()
        client.on(ProjectIconSetRequest.self) { _ in
            let json = """
            {"type":"session","message":{"type":"project.icon.set.response","payload":{
              "requestId":"r","projectId":"prj_FIXTURE","accepted":true,"error":null
            }}}
            """
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<ProjectIconSetRequest.Response>.self,
                from: Data(json.utf8)).payload
        }
        let data = try Fixture.data("project_icon_get_response", in: "project-config")
        client.on(ProjectIconGetRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<ProjectIconGetRequest.Response>.self, from: data).payload
        }
        let store = ProjectIconStore(client: client)
        store.update(serverInfo: try makeServerInfo(customIcon: true))
        let ok = await store.reset(projectId: "prj_FIXTURE")
        #expect(ok == true)
        let sent = try #require(client.requests(ProjectIconSetRequest.self).first)
        #expect(sent.source == .automatic)
    }
}
