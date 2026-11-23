#if canImport(UIKit)
import SwiftUI

/// The file card's failure row: the download failed, or the file is over the download cap.
/// The same presentation as the image cards (`MediaFailureContent`); only a failure that
/// trying again can fix offers the button.
struct RichFileFailureRow: View {
    let fileName: String
    /// The file is larger than the 64 MB cap: retrying would give the same answer.
    let overLimit: Bool
    let onRetry: () -> Void

    var body: some View {
        MediaFailureContent(
            detail: overLimit ? "\(fileName) · Over the 64 MB limit" : fileName,
            onRetry: overLimit ? nil : onRetry,
            title: overLimit ? "File too large to download" : "Couldn't download file",
            symbol: "doc",
            retryHint: "Tries downloading the file again")
        .frame(minHeight: Metrics.rowCardMinHeight - Space.md * 2)
    }
}
#endif
