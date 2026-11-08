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
    private static let notification = UINotificationFeedbackGenerator()

    /// Ticks, toggles, disclosures.
    public static func selection() { selectionGenerator.selectionChanged() }
    /// Sending a message.
    public static func send() { rigidImpact.impactOccurred(intensity: 0.7) }
    /// Something arrived or settled: a turn finished, a tool completed.
    public static func settle() { softImpact.impactOccurred(intensity: 0.6) }
    public static func success() { notification.notificationOccurred(.success) }
    public static func failure() { notification.notificationOccurred(.error) }

    /// Call before a gesture that will likely produce feedback, to cut latency.
    public static func prepare() {
        selectionGenerator.prepare()
        rigidImpact.prepare()
    }
}
