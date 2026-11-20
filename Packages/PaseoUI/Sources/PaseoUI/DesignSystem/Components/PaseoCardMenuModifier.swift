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
                    Button(copyTitle, systemImage: "doc.on.doc") {
                        if let richActions {
                            richActions.copyText(copyText)
                        } else {
                            UIPasteboard.general.string = copyText
                            Haptics.light()
                        }
                    }
                }
                if let saveImage {
                    Button("Save to Photos", systemImage: "photo") {
                        if let richActions {
                            richActions.saveImage(saveImage)
                        } else {
                            UIImageWriteToSavedPhotosAlbum(saveImage, nil, nil, nil)
                        }
                    }
                }
                if let externalTitle, let externalURL {
                    Button(externalTitle, systemImage: "safari") {
                        if let richActions {
                            richActions.openURL(externalURL)
                        } else {
                            UIApplication.shared.open(externalURL)
                        }
                    }
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
}
#endif
