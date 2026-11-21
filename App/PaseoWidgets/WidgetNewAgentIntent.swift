import AppIntents
import Foundation

// MARK: - Controls (Phase E G15, plan §3.3)

// Two Control Center / Lock Screen / Action button controls, via `ControlWidget`.
// They open the app through minimal `OpenURLIntent` wrappers over the existing
// `paseo://` routes. The full G16 intents live in the app target and can't be
// shared without dragging PaseoUI into the extension — these wrappers are the
// deliberate duplicate ("share ... only where it compiles cleanly").

/// Opens the new-agent draft through the existing route. The draft focuses its
/// composer and never sends.
struct WidgetNewAgentIntent: AppIntent {
    static let title: LocalizedStringResource = "New agent"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "paseo://new-agent") else {
            throw URLError(.badURL)
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}
