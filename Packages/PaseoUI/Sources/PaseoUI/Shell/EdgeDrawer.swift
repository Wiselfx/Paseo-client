#if canImport(UIKit)
import SwiftUI

/// Which edge a drawer slides from.
enum DrawerEdge {
    case leading
    case trailing
}

/// Shared physics for the two edge drawers: the left sidebar and the right workspace panel.
/// Finger-tracking drags, the one settle animation, the card material and the dim scrim live here
/// so both sides behave identically (UX-SPEC §1, §1.4).
enum EdgeDrawer {
    /// Touchable edge zone on each side.
    static let edgeZone: CGFloat = 24

    /// The display's corner radius, a constant: 55 on Face ID phones. Never interpolated with
    /// progress (§1.1) — a card that covers the screen has the screen's own shape.
    static let cornerRadius: CGFloat = 55

    /// The one settle animation: critically damped, no overshoot. Reduce Motion gets a flat
    /// ease-out instead (§0.4).
    static func settleAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.32)
    }

    /// The scrim over a covered surface: 0.25 in light, 0.55 in dark, scaled by progress (§1.1).
    static func scrimOpacity(_ progress: CGFloat, dark: Bool) -> Double {
        Double(min(max(progress, 0), 1)) * (dark ? 0.55 : 0.25)
    }
}

/// The drag gesture both drawers use. Attach with `.edgeDrawerDrag(...)`; the same math runs on
/// both edges. The finger tracks 1:1 with no animation while dragging and the surface settles by
/// projected position on release (§0.4).
struct EdgeDrawerDrag: ViewModifier {
    /// The edge the finger must start on; nil arms anywhere (an already-open surface only).
    /// A missing or blocked edge still consumes the gesture's direction decision.
    let edge: DrawerEdge?
    let screenWidth: CGFloat
    let drawerWidth: CGFloat
    /// Read when a gesture begins, not when the view is built, so the shell never has to
    /// re-evaluate (and rebuild the sidebar and the chat) just to hand a gesture a new Bool.
    let isOpen: () -> Bool
    /// The other drawer is open, so this one never arms.
    let blocked: () -> Bool
    /// Keep requiring the 24 pt edge zone even while open (the panel's leading-edge dismissal).
    let requiresEdgeZone: Bool
    /// For a drag on an open surface: never arm inside the leading 24 pt, which the panel's own
    /// edge dismissal owns. Exactly one gesture drives the progress at a time.
    let excludeLeadingEdge: Bool
    /// The finger direction that moves the drawer towards open.
    let openDirection: DrawerEdge
    @Binding var progress: CGFloat
    let onSettle: (Bool) -> Void

    @State private var dragOrigin: CGFloat?
    /// Decided once per gesture: a scroll that starts vertically never turns into a drawer drag.
    @State private var directionDecided = false

    func body(content: Content) -> some View {
        content.simultaneousGesture(gesture)
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if !directionDecided {
                    directionDecided = true
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                        return
                    }
                    guard !blocked() else { return }
                    if edge != nil {
                        guard isOpen() || isInEdgeZone(value.startLocation.x) else { return }
                        guard !requiresEdgeZone || isInEdgeZone(value.startLocation.x) else {
                            return
                        }
                    } else {
                        guard isOpen() else { return }
                        guard !excludeLeadingEdge || value.startLocation.x > EdgeDrawer.edgeZone
                        else { return }
                    }
                    dragOrigin = progress
                    Haptics.prepare()
                }
                guard let origin = dragOrigin else { return }
                let signed = signedTranslation(value.translation.width)
                progress = min(1, max(0, origin + signed / max(1, drawerWidth)))
            }
            .onEnded { value in
                directionDecided = false
                guard let origin = dragOrigin else { return }
                dragOrigin = nil
                let signed = signedTranslation(value.predictedEndTranslation.width)
                let projected = origin + signed / max(1, drawerWidth)
                onSettle(projected >= 0.5)
            }
    }

    private func isInEdgeZone(_ x: CGFloat) -> Bool {
        guard let edge else { return true }
        switch edge {
        case .leading: return x <= EdgeDrawer.edgeZone
        case .trailing: return x >= screenWidth - EdgeDrawer.edgeZone
        }
    }

    private func signedTranslation(_ translation: CGFloat) -> CGFloat {
        openDirection == .leading ? translation : -translation
    }
}

extension View {
    /// Drives an edge drawer with the shared finger-tracking gesture.
    ///
    /// - Parameters:
    ///   - edge: where the drag may start. Nil arms anywhere, for a gesture on an open surface.
    ///   - openDirection: the finger direction that opens the drawer; defaults to `edge`.
    ///   - requiresEdgeZone: keep the edge zone while open (a dismissal that must not fight a
    ///     vertically scrolling list in the middle of the screen).
    ///   - excludeLeadingEdge: leave the leading 24 pt to the panel's own edge dismissal.
    func edgeDrawerDrag(
        edge: DrawerEdge?, screenWidth: CGFloat, drawerWidth: CGFloat,
        isOpen: @escaping () -> Bool, blocked: @escaping () -> Bool, openDirection: DrawerEdge? = nil, requiresEdgeZone: Bool = false,
        excludeLeadingEdge: Bool = false,
        progress: Binding<CGFloat>, onSettle: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            EdgeDrawerDrag(
                edge: edge, screenWidth: screenWidth, drawerWidth: drawerWidth, isOpen: isOpen,
                blocked: blocked, requiresEdgeZone: requiresEdgeZone,
                excludeLeadingEdge: excludeLeadingEdge,
                openDirection: openDirection ?? edge ?? .leading,
                progress: progress, onSettle: onSettle))
    }
}

/// The canvas behind a surface's content: the display-radius shape, full bleed, so it covers the
/// status bar and the home indicator area. No drop shadow (§1.1).
struct EdgeDrawerCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: EdgeDrawer.cornerRadius, style: .continuous)
            .fill(ClaudePalette.background)
            .ignoresSafeArea()
    }
}

/// The 0.5 pt hairline along a displaced surface's rounded edge, faded in with progress. Drawn
/// above the content so the surface's own opaque background cannot hide it; never interactive.
struct EdgeDrawerHairline: View {
    let progress: CGFloat

    var body: some View {
        if progress > 0 {
            RoundedRectangle(cornerRadius: EdgeDrawer.cornerRadius, style: .continuous)
                .stroke(
                    ClaudePalette.ink.opacity(0.10 * Double(min(max(progress, 0), 1))),
                    lineWidth: 0.5)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The scrim over a covered surface; tap closes. It lives inside the surface's rounded shape, so
/// its corners match the card's, and it is full bleed like the card (§1.1).
struct EdgeDrawerDim: View {
    let progress: CGFloat
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if progress > 0 {
            let shape = RoundedRectangle(cornerRadius: EdgeDrawer.cornerRadius, style: .continuous)
            shape
                .fill(
                    Color.black.opacity(
                        EdgeDrawer.scrimOpacity(progress, dark: colorScheme == .dark)))
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture(perform: onTap)
                .accessibilityLabel("Close")
        }
    }
}

/// What the workspace panel needs to take part in the shared panel dismissal (§1.3): a drag that
/// tracks one to one and settles through the shell's single animation.
struct PanelDismissDrag {
    var progress: Binding<CGFloat>
    var width: CGFloat
    var onSettle: (Bool) -> Void
}
#endif
