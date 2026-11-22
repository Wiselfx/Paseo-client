#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The PR pane's checks: one row per check and the rollup line under them.
struct PRChecksBlock: View {
    let status: CheckoutPrStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Checks")
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
                .padding(.horizontal, Space.lg)
                .padding(.bottom, 6)
            ForEach(Array(status.checks.enumerated()), id: \.offset) { _, check in
                PRCheckRow(check: check, prNumber: status.number ?? 0)
            }
            if let rollup = PRCheckStatus.rollup(status.checks) {
                Text(rollup)
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, Space.lg)
                    .padding(.top, Space.sm)
            }
        }
        .padding(.bottom, 10)
    }
}
#endif
