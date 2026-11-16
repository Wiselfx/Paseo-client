#if canImport(UIKit)
import SwiftUI
import UIKit

/// One toast at a time. A newer toast replaces the current one, and each toast's timer is tied to
/// its id, so a stale timer never clears a newer message.
@MainActor @Observable final class ToastCenter {
    struct Item: Identifiable {
        let id = UUID()
        let message: String
        let systemImage: String?
        let undo: (() -> Void)?
        let duration: Duration
    }

    private(set) var current: Item?
    private var clearTask: Task<Void, Never>?

    init() {}

    func show(
        _ message: String,
        systemImage: String? = nil,
        undo: (() -> Void)? = nil,
        duration: Duration = .seconds(2.5)
    ) {
        let item = Item(
            message: message,
            systemImage: systemImage,
            undo: undo,
            duration: undo == nil ? duration : .seconds(4)
        )
        current = item
        AccessibilityNotification.Announcement(message).post()
        let id = item.id
        let wait = item.duration
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.clear(id)
        }
    }

    func performUndo(_ item: Item) {
        item.undo?()
        clear(item.id)
    }

    func clear(_ id: UUID) {
        guard current?.id == id else { return }
        current = nil
        clearTask?.cancel()
        clearTask = nil
    }
}

private struct ToastCenterKey: EnvironmentKey {
    static let defaultValue: ToastCenter? = nil
}

extension EnvironmentValues {
    /// The shell's toast center; nil outside the shell (previews, isolated views).
    var toast: ToastCenter? {
        get { self[ToastCenterKey.self] }
        set { self[ToastCenterKey.self] = newValue }
    }
}

private struct ToastRectKey: PreferenceKey {
    static let defaultValue = CGRect.null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull { value = next }
    }
}

private struct ToastHostModifier: ViewModifier {
    let center: ToastCenter

    func body(content: Content) -> some View {
        content
            .environment(\.toast, center)
            .background {
                ToastWindowHost(center: center)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Put once at the shell root: toasts render in an overlay window, so they also show above
    /// an open sheet.
    func toastHost(_ center: ToastCenter) -> some View {
        modifier(ToastHostModifier(center: center))
    }
}

/// The toast itself: a glass capsule at the top, below the safe area and the 48 pt header.
private struct ToastBanner: View {
    let item: ToastCenter.Item
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage).font(.glyph(.small, weight: .medium))
            }
            Text(item.message)
                .font(.paseo(.footnote, weight: .medium))
                .lineLimit(2)
            if item.undo != nil {
                Button("Undo", action: onUndo)
                    .font(.paseo(.footnote, weight: .semibold))
                    .buttonStyle(.plain)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ToastRectKey.self, value: proxy.frame(in: .global))
                        }
                    }
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, 10)
        .glassEffect(in: .capsule)
        .accessibilityElement(children: .contain)
    }
}

/// The window's content: the current toast, pinned to the top.
private struct ToastHostRoot: View {
    let center: ToastCenter
    let onInteractiveRect: (CGRect) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let item = center.current {
                ToastBanner(item: item, onUndo: { center.performUndo(item) })
                    .padding(.top, 56)
                    .padding(.horizontal, Space.lg)
                    .transition(.offset(y: -6).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.fade.animation, value: center.current?.id)
        .onPreferenceChange(ToastRectKey.self) { onInteractiveRect($0) }
    }
}

/// A window that passes every touch through except the toast's Undo button.
private final class ToastWindow: UIWindow {
    var interactiveRect: CGRect = .null

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !interactiveRect.isNull, interactiveRect.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

private struct ToastWindowHost: UIViewRepresentable {
    let center: ToastCenter

    func makeCoordinator() -> Coordinator {
        Coordinator(center: center)
    }

    func makeUIView(context: Context) -> UIView {
        context.coordinator.attach()
        return UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.apply(
            colorScheme: context.environment.colorScheme,
            pureBlack: context.environment.pureBlack)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private let center: ToastCenter
        /// The app owns the window: losing it hides the toast for good.
        @MainActor private var window: ToastWindow?
        @MainActor private var colorScheme: ColorScheme?
        @MainActor private var pureBlack = false

        init(center: ToastCenter) {
            self.center = center
        }

        /// The window is separate from the app's, so it does not inherit the in-app appearance.
        @MainActor func apply(colorScheme: ColorScheme, pureBlack: Bool) {
            self.colorScheme = colorScheme
            self.pureBlack = pureBlack
            applyAppearance()
        }

        /// Never called from a place that has no window yet: `attach()` applies it once it has one.
        @MainActor private func applyAppearance() {
            guard let window, let colorScheme else { return }
            window.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
            window.traitOverrides[PureBlackTrait.self] = pureBlack
        }

        @MainActor func attach() {
            guard window == nil else { return }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                ?? scenes.first
            else { return }
            let window = ToastWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.backgroundColor = .clear
            let root = ToastHostRoot(center: center) { [weak window] rect in
                window?.interactiveRect = rect
            }
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear
            window.rootViewController = host
            self.window = window
            applyAppearance()
            window.isHidden = false
        }

        @MainActor func detach() {
            window?.isHidden = true
            window = nil
        }
    }
}

#Preview("Light") {
    ToastPreviewHost()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ToastPreviewHost()
        .preferredColorScheme(.dark)
}

private struct ToastPreviewHost: View {
    @State private var center = ToastCenter()

    var body: some View {
        VStack(spacing: Space.md) {
            Button("Plain toast") { center.show("Copied") }
                .buttonStyle(.paseoPrimary())
            Button("Undo toast") {
                center.show("Agent archived", undo: {})
            }
            .buttonStyle(.paseoSecondary)
            if let item = center.current {
                Text(item.message).font(.paseo(.footnote)).foregroundStyle(Palette.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}
#endif
