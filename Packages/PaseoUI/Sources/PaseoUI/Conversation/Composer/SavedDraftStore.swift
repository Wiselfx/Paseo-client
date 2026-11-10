#if canImport(UIKit)
import Foundation

/// M8b: the unsent draft per agent, persisted in UserDefaults under `paseo.draft.<agentId>`.
/// Writes are debounced by the caller (~500 ms); cleared on send; restored when a conversation
/// opens and the store's draft is empty.
enum SavedDraftStore {
    private static let prefix = "paseo.draft."

    static func load(_ agentId: String) -> String {
        UserDefaults.standard.string(forKey: prefix + agentId) ?? ""
    }

    static func save(_ agentId: String, _ text: String) {
        if text.isEmpty {
            UserDefaults.standard.removeObject(forKey: prefix + agentId)
        } else {
            UserDefaults.standard.set(text, forKey: prefix + agentId)
        }
    }

    static func clear(_ agentId: String) {
        UserDefaults.standard.removeObject(forKey: prefix + agentId)
    }
}
#endif
