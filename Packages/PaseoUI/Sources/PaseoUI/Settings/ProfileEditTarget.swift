#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Which edit sheet to present and with what.
struct ProfileEditTarget: Identifiable {
    enum Mode: Equatable { case create, edit }

    let mode: Mode
    let profile: AgentProfile?

    init(mode: Mode, profile: AgentProfile?) {
        self.mode = mode
        self.profile = profile
    }

    var id: String {
        switch mode {
        case .create: "create"
        case .edit: "edit.\(profile?.id ?? "unknown")"
        }
    }
}
#endif
