import AppIntents
import CoreSpotlight
import SwiftUI
import WidgetKit

// MARK: - Controls (Phase E G15, plan §3.3)

// Two Control Center / Lock Screen / Action button controls, via `ControlWidget`.
// They open the app through minimal `OpenURLIntent` wrappers over the existing
// `paseo://` routes. The full G16 intents live in the app target and can't be
// shared without dragging PaseoUI into the extension — these wrappers are the
// deliberate duplicate ("share ... only where it compiles cleanly").

/// Opens the new-agent draft through the existing route. The draft focuses its
/// composer and never sends.
struct WidgetNewAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "New agent"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "paseo://new-agent") else {
            throw URLError(.badURL)
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

/// Opens the conversation that most needs the reader: the top attention agent,
/// else the app's host root (which redirects to the last workspace).
/// Note: no voice-mode route exists in M20 yet, so this lands on the
/// conversation — one tap from the in-app voice entry — and adopts a voice route
/// if one is ever added.
struct WidgetVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Open conversation"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        if let top = GlanceMirror.load()?.agents.first(where: { $0.requiresAttention })
            ?? GlanceMirror.load()?.agents.first,
            let url = GlanceMirror.deepLink(for: top)
        {
            return .result(opensIntent: OpenURLIntent(url))
        }
        throw URLError(.fileDoesNotExist)
    }
}

struct NewAgentControl: ControlWidget {
    static let kind = "com.wiselfx.paseoclient.new-agent"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind,
            title: "New agent",
            image: Image(systemName: "plus.message")
        ) {
            ControlWidgetButton(action: WidgetNewAgentIntent()) {
                Label("New agent", systemImage: "plus.message")
            }
        }
    }
}

struct VoiceControl: ControlWidget {
    static let kind = "com.wiselfx.paseoclient.open-conversation"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind,
            title: "Open conversation",
            image: Image(systemName: "message")
        ) {
            ControlWidgetButton(action: WidgetVoiceIntent()) {
                Label("Open conversation", systemImage: "message")
            }
        }
    }
}
