import UIKit

/// One answer's background-task identifier, carried into the expiry handler. Each
/// answer owns its own box: the identifier is written once after `beginBackgroundTask`
/// returns and read on the main actor, so a shared slot is never needed.
final class BackgroundTaskBox: @unchecked Sendable {
    var id = UIBackgroundTaskIdentifier.invalid
}
