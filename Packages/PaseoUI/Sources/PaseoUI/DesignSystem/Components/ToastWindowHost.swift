#if canImport(UIKit)
import SwiftUI
import UIKit

struct ToastWindowHost: UIViewRepresentable {
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
#endif
