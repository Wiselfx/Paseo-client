import Foundation

public enum ClaudeSettingsDestination: String, Equatable, Sendable, CaseIterable {
    case about = "About", usage = "Usage", notifications = "Notifications"
    case code = "Claude Code", connectors = "Connectors", voice = "Voice"
}
public enum ClaudeSettingsInfoLink: String, Equatable, Sendable, CaseIterable {
    case usagePolicy = "Usage Policy", consumerTerms = "Consumer Terms", privacyPolicy = "Privacy Policy", licenses =
        "Licenses", support = "Help & Support"
}
@nonexhaustive public enum ClaudeSettingsAction: Equatable, Sendable {
    case infoLink(ClaudeSettingsInfoLink)
    case open(ClaudeSettingsDestination), back, close
    case connector(ClaudeSettingsConnectorAction)
    case codePreference(ClaudeCodePreferenceAction)
    case usage(ClaudeUsageAction)
    case setNotification(ClaudeNotificationPreference, Bool)
    case setHaptics(Bool), setAppearance(ClaudeAppearance)
}
/// Reversible presentation state only. Saving settings requires explicit host acknowledgement.
public struct ClaudeSettingsState: Equatable, Sendable {
    public var connectors = ClaudeSettingsConnectorState()
    public var codePreferences = ClaudeCodePreferences()
    public var usage = ClaudeUsageState()
    public var notifications = ClaudeNotificationPreferences()
    public var hapticsEnabled = true
    public var versionLabel = ""
    public private(set) var destination: ClaudeSettingsDestination?
    public init() {}
    public mutating func reduce(_ action: ClaudeSettingsAction) {
        switch action {
        case .open(let destination):
            connectors.close()
            self.destination = destination
        case .back, .close:
            connectors.close()
            destination = nil
        case .connector(let action):
            guard destination == .connectors else { return }
            if case .back = action, connectors.connector == nil {
                destination = nil
                connectors.close()
            } else {
                connectors.reduce(action)
            }
        case .codePreference(let action): codePreferences.reduce(action)
        case .setNotification(let preference, let enabled): notifications[preference] = enabled
        case .setHaptics(let enabled): hapticsEnabled = enabled
        case .usage, .infoLink, .setAppearance:
            break
        }
    }
}
