#if canImport(UIKit)
import SwiftUI

/// A validation message under a Connect form row.
struct ConnectErrorCaption: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.paseo(.caption))
            .foregroundStyle(Palette.failureInk)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
    }
}
#endif
