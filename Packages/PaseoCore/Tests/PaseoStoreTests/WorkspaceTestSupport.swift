import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

@testable import PaseoStore

/// Typed access to the T7 capture in `Fixtures/workspaces/`.
extension Load {
    static func workspaceServerInfo() throws -> ServerInfo {
        try decoder.decode(
            SessionPayloadEnvelope<ServerInfo>.self, from: Fixture.data("server_info", in: "workspaces")
        ).payload
    }

    static func workspaceDirectory() throws -> FetchWorkspacesRequest.Response {
        try decoder.decode(
            SessionPayloadEnvelope<FetchWorkspacesRequest.Response>.self,
            from: Fixture.data("fetch_workspaces_response", in: "workspaces")
        ).payload
    }

    static func projectList() throws -> ProjectListRequest.Response {
        try decoder.decode(
            SessionPayloadEnvelope<ProjectListRequest.Response>.self,
            from: Fixture.data("project_list_response", in: "workspaces")
        ).payload
    }

    static func sandboxWorkspace() throws -> WorkspaceDescriptor {
        let workspace = try #require(try workspaceDirectory().entries.first)
        return workspace
    }

    static func checkoutStatus() throws -> CheckoutStatus {
        try decoder.decode(
            SessionPayloadEnvelope<CheckoutStatus>.self,
            from: Fixture.data("checkout_status_response", in: "workspaces")
        ).payload
    }

    static func scratchCheckoutStatus() throws -> CheckoutStatus {
        try decoder.decode(
            SessionPayloadEnvelope<CheckoutStatus>.self,
            from: Fixture.data("scratch_checkout_status_response", in: "workspaces")
        ).payload
    }

    static func checkoutDiff() throws -> CheckoutDiff {
        try decoder.decode(
            SessionPayloadEnvelope<CheckoutDiff>.self,
            from: Fixture.data("subscribe_checkout_diff_response", in: "workspaces")
        ).payload
    }

    static func fileListing() throws -> FileExplorerRequest.Response {
        try decoder.decode(
            SessionPayloadEnvelope<FileExplorerRequest.Response>.self,
            from: Fixture.data("file_explorer_list_response", in: "workspaces")
        ).payload
    }

    static func fileRead() throws -> FileExplorerRequest.Response {
        try decoder.decode(
            SessionPayloadEnvelope<FileExplorerRequest.Response>.self,
            from: Fixture.data("file_explorer_file_response", in: "workspaces")
        ).payload
    }

    static func workspaceUpdate() throws -> WorkspaceUpdate {
        try decoder.decode(
            SessionPayloadEnvelope<WorkspaceUpdate>.self,
            from: Fixture.data("workspace_update_02", in: "workspaces")
        ).payload
    }

    static func githubSearch() throws -> GithubRepositorySearchRequest.Response {
        try decoder.decode(
            SessionPayloadEnvelope<GithubRepositorySearchRequest.Response>.self,
            from: Fixture.data("github_search_repositories_response", in: "workspaces")
        ).payload
    }

    static func projectAdd() throws -> ProjectAddRequest.Response {
        try decoder.decode(
            SessionPayloadEnvelope<ProjectAddRequest.Response>.self,
            from: Fixture.data("project_add_response", in: "workspaces")
        ).payload
    }

    static func workspaceCreate() throws -> WorkspaceCreateRequest.Response {
        try decoder.decode(
            SessionPayloadEnvelope<WorkspaceCreateRequest.Response>.self,
            from: Fixture.data("workspace_create_response", in: "workspaces")
        ).payload
    }
}
