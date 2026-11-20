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
#endif
