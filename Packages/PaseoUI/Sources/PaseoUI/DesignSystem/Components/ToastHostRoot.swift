#if canImport(UIKit)
import SwiftUI
import UIKit

/// The window's content: the standing status and the current toast, pinned to the top.
struct ToastHostRoot: View {
    let center: ToastCenter
    let onInteractiveRect: (CGRect) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.sm) {
            if let status = center.status {
                ToastStatusBanner(status: status)
                    .transition(.offset(y: -6).combined(with: .opacity))
            }
            if let item = center.current {
                ToastBanner(item: item, onUndo: { center.performUndo(item) })
                    .transition(.offset(y: -6).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 56)
        .padding(.horizontal, Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: center.current?.id)
        .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: center.status)
        .onPreferenceChange(ToastRectKey.self) { onInteractiveRect($0) }
    }
}
#endif
