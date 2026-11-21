#if canImport(UIKit)
import SwiftUI

/// The trailing "Load more" row of the History list; it shows progress while a page loads.
struct HistoryLoadMoreRow: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                if isLoading {
                    InlineProgress()
                } else {
                    Text("Load more")
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                }
                Spacer()
            }
            .frame(minHeight: 44)
        }
        .panelRow(Palette.background)
        .accessibilityLabel("Load more")
    }
}
#endif
