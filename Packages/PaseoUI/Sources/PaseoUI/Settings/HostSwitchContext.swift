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

    // MARK: Appearance (per saved host)

    /// Per-host presentation, upstream `hosts/appearance.ts`: a color from the identity
    /// palette plus how the sidebar badge renders. Keyed by saved-host id (UUID), never by
    /// URL, so a future relay identity change stays compatible.
    public private(set) var appearances: [UUID: HostAppearance] = [:]

    public func appearance(for id: UUID) -> HostAppearance {
        appearances[id] ?? HostAppearance()
    }

    public func setAppearance(_ value: HostAppearance, for id: UUID) {
        appearances[id] = value
        persistAppearances()
    }

    public func removeAppearance(for id: UUID) {
        appearances[id] = nil
        persistAppearances()
    }

    private static let appearanceKey = "hostSwitch.appearances"

    private func persistAppearances() {
        guard let data = try? JSONEncoder().encode(appearances) else { return }
        UserDefaults.standard.set(data, forKey: Self.appearanceKey)
    }

    public func loadAppearances() {
        guard let data = UserDefaults.standard.data(forKey: Self.appearanceKey),
            let decoded = try? JSONDecoder().decode([UUID: HostAppearance].self, from: data)
        else { return }
        appearances = decoded
    }
}

/// Per-host identity color, upstream `hosts/appearance.ts` IDENTITY_COLOR_NAMES (same order,
/// same fills — the order is load-bearing upstream, kept here too).
public enum HostColor: String, Sendable, CaseIterable, Codable {
    case none
    case violet
    case sky
    case emerald
    case orange
    case pink
    case indigo
    case teal
    case red
    case amber
    case blue

    public var title: String {
        switch self {
        case .none: "Default"
        case .violet: "Violet"
        case .sky: "Sky"
        case .emerald: "Emerald"
        case .orange: "Orange"
        case .pink: "Pink"
        case .indigo: "Indigo"
        case .teal: "Teal"
        case .red: "Red"
        case .amber: "Amber"
        case .blue: "Blue"
        }
    }

    /// The upstream fill table (identity-colors.ts IDENTITY_COLORS).
    public var swiftUIColor: Color {
        switch self {
        case .none: .clear
        case .violet: Color(red: 0x7a / 255, green: 0x6a / 255, blue: 0xa8 / 255)
        case .sky: Color(red: 0x3d / 255, green: 0x7e / 255, blue: 0xa6 / 255)
        case .emerald: Color(red: 0x38 / 255, green: 0x80 / 255, blue: 0x68 / 255)
        case .orange: Color(red: 0xa4 / 255, green: 0x67 / 255, blue: 0x3a / 255)
        case .pink: Color(red: 0xb0 / 255, green: 0x5c / 255, blue: 0x80 / 255)
        case .indigo: Color(red: 0x6a / 255, green: 0x70 / 255, blue: 0xb8 / 255)
        case .teal: Color(red: 0x36 / 255, green: 0x80 / 255, blue: 0x80 / 255)
        case .red: Color(red: 0xb0 / 255, green: 0x62 / 255, blue: 0x60 / 255)
        case .amber: Color(red: 0x8f / 255, green: 0x78 / 255, blue: 0x38 / 255)
        case .blue: Color(red: 0x51 / 255, green: 0x79 / 255, blue: 0xb0 / 255)
        }
    }
}

/// How the sidebar badge renders. Upstream defaults local hosts to hidden and remote hosts
/// to name; this client only ever connects remotely (LAN/Tailscale), so the default is name.
public enum HostBadgeDisplay: String, Sendable, CaseIterable, Codable {
    case name
    case icon
    case hidden

    public var title: String {
        switch self {
        case .name: "Name"
        case .icon: "Icon only"
        case .hidden: "Hidden"
        }
    }
}

/// One host's presentation choices. `badgeDisplay` default follows upstream's remote default.
public struct HostAppearance: Sendable, Equatable, Codable {
    public var color: HostColor = .none
    public var badgeDisplay: HostBadgeDisplay = .name

    public init(color: HostColor = .none, badgeDisplay: HostBadgeDisplay = .name) {
        self.color = color
        self.badgeDisplay = badgeDisplay
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
