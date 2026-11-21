#if canImport(UIKit)
import SwiftUI

/// Lets Settings ask the app layer for OS notification permission without importing
/// UserNotifications here. The app installs the real action at the composition root; previews and
/// tests fall back to a no-op.
extension EnvironmentValues {
    @Entry public var notificationPermissionAction: @Sendable () -> Void = {}
}
#endif
