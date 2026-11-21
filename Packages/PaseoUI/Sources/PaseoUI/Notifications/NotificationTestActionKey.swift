#if canImport(UIKit)
import SwiftUI

/// Lets Settings post the upstream test notification without importing
/// UserNotifications here. The app installs the real action at the composition root;
/// previews and tests fall back to a no-op that reports failure.
extension EnvironmentValues {
    @Entry public var notificationTestAction: @Sendable () async -> Bool = { false }
}
#endif
