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

    /// A standing message that stays until its owner clears it (the connection state). It
    /// shares the toast's place and look, and sits above a transient toast when both show.
    struct Status: Equatable {
        let message: String
        let systemImage: String?
        let showsProgress: Bool
    }

    private(set) var current: Item?
    private(set) var status: Status?
    private var clearTask: Task<Void, Never>?

    init() {}

    func setStatus(_ status: Status?) {
        guard self.status != status else { return }
        self.status = status
        if let status { AccessibilityNotification.Announcement(status.message).post() }
    }

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
extension EnvironmentValues {
    /// The shell's toast center; nil outside the shell (previews, isolated views).
    @Entry var toast: ToastCenter?
}
extension View {
    /// Put once at the shell root: toasts render in an overlay window, so they also show above
    /// an open sheet.
    func toastHost(_ center: ToastCenter) -> some View {
        modifier(ToastHostModifier(center: center))
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
#endif
