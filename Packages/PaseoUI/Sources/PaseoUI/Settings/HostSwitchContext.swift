#if canImport(UIKit)
import Foundation
import Observation
import SwiftUI

/// The saved daemons and what to do with them, injected by the app so the sidebar footer and
/// Settings → Hosts can switch without the shell knowing how hosts get switched. Nil in this
/// environment means those surfaces quietly render nothing extra.
@MainActor @Observable
public final class HostSwitchContext {
    public private(set) var hosts: [HostSwitchEntry] = []
    public var switchTo: (UUID) -> Void = { _ in }
    public var addHost: () -> Void = {}
    public var forgetHost: (UUID) -> Void = { _ in }
    public var renameHost: (UUID, String) -> Void = { _, _ in }

    public init() {}

    /// Replaces the list; publishes only on real change.
    public func update(hosts: [HostSwitchEntry]) {
        guard hosts != self.hosts else { return }
        self.hosts = hosts
    }

    public var currentEntry: HostSwitchEntry? {
        hosts.first(where: \.isCurrent)
    }
}
extension EnvironmentValues {
    @Entry public var hostSwitch: HostSwitchContext?
}
#endif
