import AppIntents
import Foundation

/// Opens the conversation that most needs the reader: the top attention agent,
/// else the app's host root (which redirects to the last workspace).
/// Note: no voice-mode route exists in M20 yet, so this lands on the
/// conversation — one tap from the in-app voice entry — and adopts a voice route
/// if one is ever added.
struct WidgetVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Open conversation"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        let agents = GlanceMirror.load()?.agents ?? []
        if let top = agents.first(where: { $0.requiresAttention }) ?? agents.first,
            let url = GlanceMirror.deepLink(for: top)
        {
            return .result(opensIntent: OpenURLIntent(url))
        }
        throw URLError(.fileDoesNotExist)
    }
}
