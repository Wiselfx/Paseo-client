#if canImport(UIKit)
    import SwiftUI

    /// The old sheet header, kept for sheets that have not moved to `SheetScaffold` yet.
    struct SheetHeader: View {
        let title: String
        var back = false
        var trailing: String?
        var controlDiameter: CGFloat = Metrics.hitSize
        var titleMaxWidth: CGFloat = 200
        let close: () -> Void
        var trailingAction: (() -> Void)?
        var body: some View {
            ZStack {
                Text(title).font(.paseo(.headline, weight: .semibold)).lineLimit(1).frame(maxWidth: titleMaxWidth)
                HStack {
                    Button(action: close) {
                        Image(systemName: back ? "chevron.left" : "xmark").font(.glyph(.large, weight: .light))
                            .frame(width: controlDiameter, height: controlDiameter)
                            .contentShape(.circle)
                    }.glassEffect(in: .circle).accessibilityLabel(back ? "Back" : "Close").accessibilityIdentifier(
                        "sheet.close.\(title)")
                    Spacer()
                    if let trailing {
                        Button {
                            trailingAction?()
                        } label: {
                            Text(trailing).frame(minHeight: Metrics.hitSize).contentShape(.rect)
                        }.font(.paseo(.callout))
                    }
                }
            }.frame(height: 58).padding(.horizontal, 16).padding(.top, 7)
        }
    }
#endif
