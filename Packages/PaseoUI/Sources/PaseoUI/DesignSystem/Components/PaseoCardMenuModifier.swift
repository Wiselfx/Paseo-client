#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import UIKit

struct PaseoCardMenuModifier: ViewModifier {
    let openTitle: String?
    let onOpen: (() -> Void)?
    let onShare: (() -> Void)?
    let copyTitle: String?
    let copyText: String?
    let saveImage: UIImage?
    let externalTitle: String?
    let externalURL: URL?
    let viewSourceTitle: String?
    let onViewSource: (() -> Void)?
    let filePath: String?

    @Environment(\.richActions) private var richActions
    @Environment(\.openURL) private var openURL
    @Environment(\.toast) private var toast

    func body(content: Content) -> some View {
        content.contextMenu {
            VStack {
                if let openTitle, let onOpen {
                    Button(openTitle, systemImage: "arrow.up.forward.app") { onOpen() }
                }
                if let onShare {
                    Button("Share", systemImage: "square.and.arrow.up") { onShare() }
                }
                if let copyTitle, let copyText {
                    Button(copyTitle, systemImage: "doc.on.doc") { copy(copyText) }
                }
                if let saveImage {
                    Button("Save to Photos", systemImage: "photo") { save(saveImage) }
                }
                if let externalTitle, let externalURL {
                    Button(externalTitle, systemImage: "safari") { openExternally(externalURL) }
                }
                if let viewSourceTitle, let onViewSource {
                    Button(viewSourceTitle, systemImage: "chevron.left.forwardslash.chevron.right") {
                        onViewSource()
                    }
                }
                if let filePath {
                    Button("Show in Files", systemImage: "folder") {
                        richActions?.openFile(filePath)
                    }
                }
            }
        }
    }

    @MainActor private func copy(_ text: String) {
        if let richActions {
            richActions.copyText(text)
        } else {
            Clipboard.copy(text)
            Haptics.light()
        }
        toast?.show("Copied", systemImage: "checkmark")
    }

    @MainActor private func save(_ image: UIImage) {
        if let richActions {
            richActions.saveImage(image)
        } else {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
    }

    @MainActor private func openExternally(_ url: URL) {
        if let richActions {
            richActions.openURL(url)
        } else {
            openURL(url)
        }
    }
}
#endif
