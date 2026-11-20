#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

/// The quiet line for a permission answer. Shared with the notification fallback
/// path, so taps and notification actions read identically.
public enum ResolutionLine {
    public static func text(for response: AgentPermissionResponse, request: AgentPermissionRequest) -> String {
        if request.kind == .plan {
            if case .allow = response { return "Approved plan" }
            return "Rejected plan"
        }
        switch response {
        case .allow: return "Allowed: \(request.name)"
        case .deny(_, _, let interrupt): return interrupt == true ? "Canceled" : "Denied"
        case .unknown(let behavior, _): return behavior == "dismiss" ? "Canceled" : "Denied"
        }
    }
}
#endif
