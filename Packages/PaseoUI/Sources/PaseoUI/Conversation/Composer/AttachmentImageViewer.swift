#if canImport(UIKit)
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PaseoStore

/// Minimal full-screen image viewer for attachment pills: dark canvas, tap to dismiss.
struct AttachmentImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        }
        .onTapGesture { dismiss() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Image viewer, tap to dismiss")
        .accessibilityAddTraits(.isButton)
    }
}
#endif
