#if canImport(UIKit)
import PDFKit
import UIKit

/// Renders a PDF's first page as a thumbnail. `@concurrent`, so the parse runs off the main actor
/// as a structured child of the card's task: a card that scrolls away before the work starts
/// skips it, instead of a detached task that outlives its requester.
enum RichPDFThumbnail {
    /// The first page at `width` pixels across, or nil for data PDFKit cannot read.
    @concurrent
    static func render(data: Data, width: CGFloat) async -> UIImage? {
        guard !Task.isCancelled,
            let document = PDFDocument(data: data), let page = document.page(at: 0)
        else { return nil }
        let box = page.bounds(for: .mediaBox)
        let ratio = box.width / max(box.height, 1)
        return page.thumbnail(
            of: CGSize(width: width, height: max(width / max(ratio, 0.01), 1)), for: .mediaBox)
    }
}
#endif
