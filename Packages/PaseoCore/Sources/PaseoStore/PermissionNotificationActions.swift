import Foundation
import PaseoProtocol

// MARK: - Permission notification actions (Phase D G19)

// NOTE: Notification Allow/Deny buttons appear only on simple permission requests:
// one tool call, no free-text input, no question options. Anything richer (plans,
// questions, modes, free-text answers) stays in the transcript card, where the
// full context and the text field live.

/// The two notification actions for a simple request, with the daemon answers they send.
public struct PermissionNotificationActions: Sendable, Equatable {
    /// The daemon action id for the allow button (for `selectedActionId`).
    public var allowActionId: String
    /// The daemon action id for the deny button.
    public var denyActionId: String

    public init(allowActionId: String, denyActionId: String) {
        self.allowActionId = allowActionId
        self.denyActionId = denyActionId
    }

    public var allowResponse: AgentPermissionResponse {
        .allowing(selectedActionId: allowActionId)
    }

    public var denyResponse: AgentPermissionResponse {
        .denying(selectedActionId: denyActionId)
    }
}

public enum PermissionNotificationMapping {
    /// The notification actions for `request`, or nil when it is not simple:
    /// - the kind must be `.tool` (one tool call — plans, questions and modes
    ///   need the transcript card);
    /// - the daemon must offer an allow and a deny button (unknown behaviors
    ///   cannot map to the two fixed buttons);
    /// - the input must carry no question options (`questions`, answered in a form)
    ///   and no free-text field (answered by typing).
    ///
    /// Free-text detection is a conservative key heuristic: a non-empty string under
    /// `text`, `prompt`, `message`, `answer`, `input` or `value` means the approval
    /// flow expects typed input. Tool arguments (`command`, `path`, `pattern`, …)
    /// are what is being approved, not typed input, and pass through.
    public static func actions(for request: AgentPermissionRequest) -> PermissionNotificationActions? {
        guard request.kind == .tool,
            let actions = request.actions, !actions.isEmpty,
            let allow = actions.first(where: { $0.behavior == .allow }),
            let deny = actions.first(where: { $0.behavior == .deny }),
            !hasQuestionOptions(request.input),
            !hasFreeTextInput(request.input)
        else { return nil }
        return PermissionNotificationActions(allowActionId: allow.id, denyActionId: deny.id)
    }

    private static func hasQuestionOptions(_ input: JSONValue?) -> Bool {
        guard case .object(let object) = input,
            case .array(let items)? = object["questions"]
        else { return false }
        return !items.isEmpty
    }

    private static func hasFreeTextInput(_ input: JSONValue?) -> Bool {
        guard case .object(let object) = input else { return false }
        let keys = ["text", "prompt", "message", "answer", "input", "value"]
        for key in keys {
            if case .string(let value)? = object[key],
                !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return true
            }
        }
        return false
    }
}
