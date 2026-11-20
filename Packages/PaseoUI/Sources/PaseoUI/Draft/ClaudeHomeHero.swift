#if canImport(UIKit)
import Foundation
import SwiftUI

/// The home state: the mark above a serif greeting, both rising in on the DSH tokens.
struct ClaudeHomeHero: View {
    var hint: String?

    /// The greeting is drawn once per launch, so the launch skeleton and the draft that follows
    /// it show the same sentence (E2b §1).
    private static let launchDraw = Double.random(in: 0..<1)

    @AppStorage(PaseoSettingsKeys.yourName) private var name = ""
    @State private var markIn: Bool
    @State private var greetingIn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(hint: String? = nil) {
        self.hint = hint
        // Every hero after the first of this launch starts settled: no second rise on the
        // skeleton → draft hand-off (E2b §1).
        let settled = HomeHeroLaunchState.shared.hasRisen
        _markIn = State(initialValue: settled)
        _greetingIn = State(initialValue: settled)
    }

    private var greeting: String { ClaudeGreeting.pick(username: name, draw: Self.launchDraw) }

    var body: some View {
        VStack(spacing: 20) {
            // Paseo's butterfly at the splash's 96 pt, shimmering while the hero idles
            // (Upstream: packages/app/src/screens/startup-splash-screen.tsx:44-46,155-186);
            // this hero is what `LaunchSkeleton` shows, so the splash and the draft draw one mark.
            PaseoLogoShimmer()
                .modifier(ClaudeHeroRise(visible: markIn, reduceMotion: reduceMotion))

            VStack(spacing: 8) {
                Text(greeting)
                    .font(.paseo(.largeTitle))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("home.greeting")
                if let hint {
                    Text(hint)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                        .multilineTextAlignment(.center)
                }
            }
            .modifier(ClaudeHeroRise(visible: greetingIn, reduceMotion: reduceMotion))
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard HomeHeroLaunchState.shared.claimRise() else {
                // A later hero of the same launch (usually the draft after the skeleton): it was
                // built settled, and never plays the entrance again (E2b §1).
                if !markIn { markIn = true }
                if !greetingIn { greetingIn = true }
                return
            }
            let settle = Motion.settle.resolved(reduceMotion: reduceMotion)
            if reduceMotion {
                withAnimation(settle) {
                    markIn = true
                    greetingIn = true
                }
            } else {
                withAnimation(settle) { markIn = true }
                withAnimation(settle?.delay(ClaudeMotion.stagger)) { greetingIn = true }
            }
        }
    }
}
#endif
