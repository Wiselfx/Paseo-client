#if canImport(UIKit)
import SwiftUI

/// Which edge a drawer slides from.
enum DrawerEdge {
    case leading
    case trailing
}

/// Shared physics for the two edge drawers: the left sidebar and the right workspace panel.
/// Finger-tracking drags, spring settles, the dim scrim and the card corner radius live here so
/// both sides behave identically.
enum EdgeDrawer {
    /// Touchable edge zone on each side.
    static let edgeZone: CGFloat = 24

    /// The card corner radius for the covered surface: `min(55, max(44, width * 0.12))`.
    static func cornerRadius(forScreenWidth width: CGFloat) -> CGFloat {
        min(55, max(44, width * 0.12))
    }

    /// The settle spring; Reduce Motion gets a flat fade instead.
    static func settleAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.22) : .spring(response: 0.36, dampingFraction: 0.88)
    }
}

/// The drag gesture both drawers use. Attach with `.edgeDrawerDrag(...)`; the same math runs on
/// both edges, with the direction sign flipped for the trailing edge.
struct EdgeDrawerDrag: ViewModifier {
    let edge: DrawerEdge
    let screenWidth: CGFloat
    let drawerWidth: CGFloat
    let isOpen: Bool
    /// The other drawer is open, so this one never arms.
    let blocked: Bool
    @Binding var progress: CGFloat
    let onSettle: (Bool) -> Void

    @State private var dragOrigin: CGFloat?

    func body(content: Content) -> some View {
        content.simultaneousGesture(gesture)
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                if dragOrigin == nil {
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    guard !blocked else { return }
                    guard isOpen || isInEdgeZone(value.startLocation.x) else { return }
                    dragOrigin = progress
                    Haptics.prepare()
                }
                guard let origin = dragOrigin else { return }
                let signed = signedTranslation(value.translation.width)
                progress = min(1, max(0, origin + signed / max(1, drawerWidth)))
            }
            .onEnded { value in
                guard let origin = dragOrigin else { return }
                dragOrigin = nil
                let signed = signedTranslation(value.predictedEndTranslation.width)
                let projected = origin + signed / max(1, drawerWidth)
                onSettle(projected >= 0.5)
            }
    }

    private func isInEdgeZone(_ x: CGFloat) -> Bool {
        switch edge {
        case .leading: x <= EdgeDrawer.edgeZone
        case .trailing: x >= screenWidth - EdgeDrawer.edgeZone
        }
    }

    private func signedTranslation(_ translation: CGFloat) -> CGFloat {
        edge == .leading ? translation : -translation
    }
}

extension View {
    /// Drives an edge drawer with the shared finger-tracking gesture.
    func edgeDrawerDrag(
        edge: DrawerEdge, screenWidth: CGFloat, drawerWidth: CGFloat, isOpen: Bool, blocked: Bool,
        progress: Binding<CGFloat>, onSettle: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            EdgeDrawerDrag(
                edge: edge, screenWidth: screenWidth, drawerWidth: drawerWidth, isOpen: isOpen,
                blocked: blocked, progress: progress, onSettle: onSettle))
    }
}

/// The dim scrim drawn over the covered surface while a drawer is open; tap closes.
struct EdgeDrawerDim: View {
    let progress: CGFloat
    let onTap: () -> Void

    var body: some View {
        if progress > 0 {
            Color.black.opacity(0.45 * Double(progress))
                .contentShape(.rect)
                .onTapGesture(perform: onTap)
                .accessibilityLabel("Close")
        }
    }
}
#endif
