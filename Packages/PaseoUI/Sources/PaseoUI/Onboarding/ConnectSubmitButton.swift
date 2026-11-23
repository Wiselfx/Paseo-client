#if canImport(UIKit)
import SwiftUI

/// The one primary action: `PrimaryButtonStyle` keeps its width and shows the spinner while
/// connecting (PLAN §RH, async actions).
struct ConnectSubmitButton: View {
    let status: ConnectView.Status
    let canConnect: Bool
    let action: () -> Void

    private var connecting: Bool { status == .connecting }

    var body: some View {
        Button(action: action) {
            Text(
                connecting
                    ? "Connecting…" : (status.isFailed ? "Try again" : "Connect"))
        }
        .buttonStyle(.paseoPrimary(isWorking: connecting))
        .disabled(!canConnect)
        .padding(.horizontal, Space.lg)
        .accessibilityIdentifier("connect.submit")
    }
}
#endif
