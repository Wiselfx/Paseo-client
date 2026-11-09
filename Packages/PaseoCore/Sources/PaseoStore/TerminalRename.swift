import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Rename for terminals, added in M3g. The daemon sets the terminal's title; clients show it
/// in the tab strip. Lives in its own file so `TerminalsStore.swift` stays untouched apart from
/// two access wideners.
///
/// IMPLEMENTATION TICKET: docs/tickets/M3g-terminal-extras.md

public extension TerminalsStore {
    /// Renames a terminal. Returns true on success; failures land in `error` and return false.
    /// Refreshes the workspace's terminal list so the new title is visible immediately.
    @discardableResult
    func renameTerminal(_ terminalId: String, to title: String, in workspaceId: String? = nil) async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "A title is required."
            return false
        }
        do {
            let response = try await client.send(
                RenameTerminalRequest(terminalId: terminalId, title: trimmed))
            guard response.success else {
                error = response.error ?? "The daemon could not rename the terminal."
                return false
            }
            error = nil
            if let workspaceId {
                await refreshTerminals(in: workspaceId)
            } else {
                // Unknown workspace: refresh every watched one.
                for workspaceId in terminalsByWorkspace.keys {
                    await refreshTerminals(in: workspaceId)
                }
            }
            return true
        } catch {
            self.error = terminalRenameErrorText(error)
            return false
        }
    }
}

private func terminalRenameErrorText(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}
