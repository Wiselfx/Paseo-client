import SwiftUI
import UIKit

/// One place for touch feedback, so the app feels consistent and it can be tuned centrally.
///
/// The "crunch" of the iOS wheel picker is the selection generator: use `.selection` for anything
/// that ticks through values or toggles open and closed.
@MainActor
public enum Haptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let notification = UINotificationFeedbackGenerator()

    /// The user's Haptics switch in Settings → General. Read per event so toggling takes effect
    /// immediately; absence of the key means on.
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: PaseoSettingsKeys.haptics) as? Bool ?? true
    }

    /// Ticks, toggles, disclosures.
    public static func selection() { guard isEnabled else { return }; selectionGenerator.selectionChanged() }
    /// Sending a message.
    public static func send() { guard isEnabled else { return }; rigidImpact.impactOccurred(intensity: 0.7) }
    /// Releasing a scrubber onto its target: one light tap (the prompt rail's jump).
    public static func light() { guard isEnabled else { return }; lightImpact.impactOccurred() }
    /// Something arrived or settled: a turn finished, a tool completed.
    public static func settle() { guard isEnabled else { return }; softImpact.impactOccurred(intensity: 0.6) }
    public static func success() { guard isEnabled else { return }; notification.notificationOccurred(.success) }
    public static func failure() { guard isEnabled else { return }; notification.notificationOccurred(.error) }

    /// Call before a gesture that will likely produce feedback, to cut latency.
    public static func prepare() {
        guard isEnabled else { return }
        selectionGenerator.prepare()
        rigidImpact.prepare()
        lightImpact.prepare()
    }
}
