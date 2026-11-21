#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

/// A path or URL shown as the preview of a permission request that has no richer rendering.
struct PermissionPathRow: View {
    let path: String

    var body: some View {
        Text(path)
            .font(.paseo(.codeSmall))
            .foregroundStyle(Palette.ink)
            .lineLimit(2)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
