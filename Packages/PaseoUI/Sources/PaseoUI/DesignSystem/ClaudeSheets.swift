#if canImport(UIKit)
    import SwiftUI

    /// The old sheet header, kept for sheets that have not moved to `SheetScaffold` yet.
    struct SheetHeader: View {
        let title: String
        var back = false
        var trailing: String?
        var controlDiameter: CGFloat = 42
        var titleMaxWidth: CGFloat = 200
        let close: () -> Void
        var trailingAction: (() -> Void)?
        var body: some View {
            ZStack {
                Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1).frame(maxWidth: titleMaxWidth)
                HStack {
                    Button(action: close) {
                        Image(systemName: back ? "chevron.left" : "xmark").font(.system(size: 21, weight: .light))
                            .frame(width: controlDiameter, height: controlDiameter)
                    }.glassEffect(in: .circle).accessibilityLabel(back ? "Back" : "Close").accessibilityIdentifier(
                        "sheet.close.\(title)")
                    Spacer()
                    if let trailing { Button(trailing) { trailingAction?() }.font(.system(size: 16)) }
                }
            }.frame(height: 58).padding(.horizontal, 16).padding(.top, 7)
        }
    }
#endif
