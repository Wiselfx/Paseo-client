#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The composer's context-window control: the ring with its number, sitting left of the mic.
///
/// It is **the only view that reads `ConversationStore.contextUsage`** (H3 §1, R-1). `ComposerView`
/// used to read it in its own body: the ring's whole conditional, and its 70 % threshold, lived
/// there, so a usage event re-decided the card's layout. Now the reading, the ring and the
/// threshold are one control wide, and the card's body never mentions the usage at all.
///
/// In a conversation the control always occupies its slot. The number inside it changes; the row
/// never reflows, because nothing in it appears or disappears at a threshold any more. While the
/// provider has not reported a window the ring is an empty track with no number — still the same
/// size, still tappable — so the first usage the daemon sends is a change *inside* the ring.
///
/// The drawing half (`ComposerContextMeterFace`) compares on `ComposerContextReading` alone, so a
/// usage event that does not change the integer percent redraws nothing.
///
/// **Reads:** `store.contextUsage`.
struct ComposerContextMeter: View {
    let store: ConversationStore
    /// Opens the context sheet. Outside the face's `==`: one composer, one stable action.
    let onTap: () -> Void

    var body: some View {
        // The one read of the live usage, and O(1): the agent snapshot's last usage figures.
        ComposerContextMeterFace(
            reading: ComposerContextReading(store.contextUsage), onTap: onTap
        )
        .equatable()
    }
}
#endif
