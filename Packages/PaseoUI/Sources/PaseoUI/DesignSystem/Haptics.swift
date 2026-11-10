import SwiftUI
import UIKit

/// One place for touch feedback, so the app feels consistent and it can be tuned centrally.
///
/// The bar is Apple's own apps: feedback is rare, soft and meaningful. One call per intent, none
/// on navigation, none on a thing merely appearing.
@MainActor
public enum Haptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()

    /// The user's Haptics switch in Settings → General, read once and refreshed by
    /// `setEnabled(_:)` when the switch moves; absence of the key means on.
    private static var isEnabled = readEnabled()

    private static func readEnabled() -> Bool {
        UserDefaults.standard.object(forKey: PaseoSettingsKeys.haptics) as? Bool ?? true
    }

    /// Called by Settings when the Haptics switch changes, so the cache is always current.
    public static func setEnabled(_ enabled: Bool) { isEnabled = enabled }

    /// A value ticks: toggles, segmented and picker changes, a disclosure opening or closing,
    /// a drag crossing a threshold, a long-press menu appearing.
    public static func selection() { guard isEnabled else { return }; selectionGenerator.selectionChanged() }
    /// A small confirmation: copy to clipboard, a row action committed, an attachment added.
    public static func light() { guard isEnabled else { return }; lightImpact.impactOccurred(intensity: 0.6) }
    /// Sending a message: a soft, full thump, not a rigid click.
    public static func send() { guard isEnabled else { return }; softImpact.impactOccurred(intensity: 0.9) }
    /// Queueing a message (the long press firing).
    public static func medium() { guard isEnabled else { return }; mediumImpact.impactOccurred() }
    /// A turn finished in the conversation on screen, app active.
    public static func settle() { guard isEnabled else { return }; softImpact.impactOccurred(intensity: 0.45) }
    /// An action you waited on completed: commit, push, PR created, branch switched, pairing done,
    /// project added.
    public static func success() { guard isEnabled else { return }; softImpact.impactOccurred(intensity: 0.7) }
    /// A user-initiated action failed. Never on a background or automatic failure.
    public static func failure() { guard isEnabled else { return }; notification.notificationOccurred(.error) }

    /// Call before a gesture that will likely produce feedback, to cut latency.
    public static func prepare() {
        guard isEnabled else { return }
        selectionGenerator.prepare()
        softImpact.prepare()
        lightImpact.prepare()
        mediumImpact.prepare()
    }
}
