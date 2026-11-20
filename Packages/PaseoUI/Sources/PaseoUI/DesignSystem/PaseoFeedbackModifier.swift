#if canImport(UIKit)
import SwiftUI

/// Plays a `PaseoFeedback` when `trigger` changes (and `condition` agrees), unless the user
/// turned Haptics off in Settings → General.
struct PaseoFeedbackModifier<Trigger: Equatable>: ViewModifier {
    let feedback: PaseoFeedback
    let trigger: Trigger
    let condition: (Trigger, Trigger) -> Bool

    @AppStorage(PaseoSettingsKeys.haptics) private var enabled = true

    func body(content: Content) -> some View {
        content.sensoryFeedback(feedback.sensory, trigger: trigger) { old, new in
            enabled && condition(old, new)
        }
    }
}

extension View {
    /// Touch feedback when `trigger` changes. Attach it to the view whose state the action
    /// changes, in place of a `Haptics` call inside the action.
    func paseoFeedback<Trigger: Equatable>(
        _ feedback: PaseoFeedback, trigger: Trigger
    ) -> some View {
        modifier(PaseoFeedbackModifier(feedback: feedback, trigger: trigger) { _, _ in true })
    }

    /// Touch feedback only for the changes `condition` accepts, e.g. `{ _, new in new != nil }`
    /// for "an item was picked" but not "it was cleared".
    func paseoFeedback<Trigger: Equatable>(
        _ feedback: PaseoFeedback, trigger: Trigger,
        condition: @escaping (_ old: Trigger, _ new: Trigger) -> Bool
    ) -> some View {
        modifier(PaseoFeedbackModifier(feedback: feedback, trigger: trigger, condition: condition))
    }
}
#endif
