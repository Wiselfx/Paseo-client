#if canImport(UIKit)
import CryptoKit
import Foundation
import ImageIO
import Synchronization
import UIKit

// MARK: - Sources

/// A daemon file, by location. `workspaceID` is agent-scoped and daemon-generated, so it
/// scopes the cache to one workspace on one host the way the ticket's `host+cwd+path`
/// identity does; `revision`, when the daemon sent it, versions the disk entry so an edited
/// file refreshes instead of serving the old bytes.
struct DaemonFileRef: Hashable, Sendable {
    var workspaceID: String
    var path: String
    var revision: String?
}
#endif
