#if canImport(UIKit)
import SwiftUI

/// 6 pt dot: breathing while running, yellow for input, blue for unread, hollow for idle.
struct PaseoStatusDot: View {
    enum Kind: Equatable { case running, needsInput, failed, done, unread, idle }

    let kind: Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Group {
            switch kind {
            case .running:
                Circle().fill(Palette.secondaryInk).frame(width: 6, height: 6)
                    .opacity(breathing ? 1 : 0.3)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: breathing)
                    .onAppear { breathing = true }
            case .needsInput: Circle().fill(Palette.warning).frame(width: 6, height: 6)
            case .failed: Circle().fill(Palette.failureInk).frame(width: 6, height: 6)
            case .done: Circle().fill(Palette.successInk).frame(width: 6, height: 6)
            case .unread: Circle().fill(Palette.unread).frame(width: 6, height: 6)
            case .idle: Circle().strokeBorder(Palette.captionInk, lineWidth: 1).frame(width: 6, height: 6)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }
}
#endif
