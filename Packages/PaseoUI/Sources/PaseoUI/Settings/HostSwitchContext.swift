#if canImport(UIKit)
import Foundation
import Observation
import SwiftUI

/// One saved daemon in the host picker / hosts list. The app builds these from its store.
public struct HostSwitchEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let label: String
    /// Full `ws(s)://host:port/ws` URL — never contains credentials. For relay hosts this
    /// is the relay endpoint (`host:port`), not a WebSocket URL.
    public let urlLine: String
    public let lastConnectedAt: Date?
    /// The host this session is talking to.
    public let isCurrent: Bool
    /// True when this saved host pairs through the E2EE relay (R18).
    public let isRelay: Bool

    public init(
        id: UUID, label: String, urlLine: String, lastConnectedAt: Date?, isCurrent: Bool,
        isRelay: Bool = false
    ) {
        self.id = id
        self.label = label
        self.urlLine = urlLine
        self.lastConnectedAt = lastConnectedAt
        self.isCurrent = isCurrent
        self.isRelay = isRelay
    }
}

/// The saved daemons and what to do with them, injected by the app so the sidebar footer and
/// Settings → Hosts can switch without the shell knowing how hosts get switched. Nil in this
/// environment means those surfaces quietly render nothing extra.
@Observable
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

public struct HostSwitchEnvironmentKey: EnvironmentKey {
    public static var defaultValue: HostSwitchContext? { nil }
}

extension EnvironmentValues {
    public var hostSwitch: HostSwitchContext? {
        get { self[HostSwitchEnvironmentKey.self] }
        set { self[HostSwitchEnvironmentKey.self] = newValue }
    }
}
#endif
