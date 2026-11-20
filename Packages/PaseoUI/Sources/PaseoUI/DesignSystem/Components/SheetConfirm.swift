#if canImport(UIKit)
import SwiftUI

/// A sheet's confirming toolbar action: `(title or nil, isEnabled, isWorking, action)`.
struct SheetConfirm {
    var title: String?
    var isEnabled: Bool
    var isWorking: Bool
    var identifier: String?
    var action: () -> Void

    init(
        _ title: String? = nil, isEnabled: Bool = true, isWorking: Bool = false,
        identifier: String? = nil, action: @escaping () -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.isWorking = isWorking
        self.identifier = identifier
        self.action = action
    }
}
#endif
