#if canImport(UIKit)
import Foundation

/// What tapping a script's service URL does. Upstream `ServiceUrlBehavior`
/// (`hooks/use-settings/storage.ts:40`: `"ask" | "in-app" | "external"`, default
/// `"ask"` at storage.ts:146), persisted as `paseo.serviceUrlBehavior`.
/// Set in Settings → Terminal, followed by `WorkspaceTerminalsView`.
enum ServiceUrlBehavior: String, CaseIterable {
    case ask
    case inApp = "in-app"
    case external

    static let storageKey = "paseo.serviceUrlBehavior"

    /// Upstream labels (`settings.general.serviceUrls.options`, en.ts:2594-2596).
    var label: String {
        switch self {
        case .ask: "Ask"
        case .inApp: "In Paseo"
        case .external: "External browser"
        }
    }
}
#endif
