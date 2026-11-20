#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

/// The composer placement: the machine's animation, with the poke override and the hit area.
/// Feet on the given rect's top edge, right edge flush with its trailing edge.
struct ComposerCrab: View {
    let state: MascotState

    @State private var poke: CrabAnimation?
    @State private var pokeLeftNext = false

    var body: some View {
        let effective = effectiveAnimation
        let tap: (() -> Void)? = effective.isResting ? { pokeNow() } : nil
        ClaudeCrabView(animation: effective, onBodyTap: tap)
            .onChange(of: poke) { _, newValue in
                // A poke plays once (`frames × 80 ms`), then hands the stage back.
                guard let newValue else { return }
                Task {
                    try? await Task.sleep(for: .seconds(newValue.pokeDuration))
                    if poke == newValue { poke = nil }
                }
            }
    }

    private var effectiveAnimation: CrabAnimation {
        if let poke { return poke }
        return state.crabAnimation
    }

    private func pokeNow() {
        Haptics.light()
        let next: CrabAnimation = pokeLeftNext ? .pokeLeft : .pokeRight
        pokeLeftNext.toggle()
        poke = next
    }
}
#endif
