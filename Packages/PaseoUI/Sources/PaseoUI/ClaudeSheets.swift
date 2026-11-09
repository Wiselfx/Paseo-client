#if canImport(UIKit)
    import SwiftUI

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
    struct SheetRow: View {
        let title: String
        var symbol: String?
        var detail: String?
        var value: String?
        var checked = false
        var chevron = false
        var badge: String?
        var action: () -> Void
        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 20, weight: .light)).frame(width: 23)
                            .foregroundStyle(Color(white: 0.72))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(title).font(.system(size: 17))
                            if let badge {
                                Text(badge).font(.system(size: 11, weight: .semibold)).foregroundStyle(
                                    badge.contains("usage") ? Color.orange : ClaudePalette.ink
                                ).padding(.horizontal, 8).padding(.vertical, 5).background(
                                    badge.contains("usage") ? Color.orange.opacity(0.20) : .primary.opacity(0.05),
                                    in: .capsule)
                            }
                        }
                        if let detail {
                            Text(detail).font(.system(size: 13)).foregroundStyle(ClaudePalette.secondary).fixedSize(
                                horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let value {
                        Text(value).font(.system(size: 16)).foregroundStyle(ClaudePalette.secondary).lineLimit(1)
                    }
                    if checked {
                        Image(systemName: "checkmark").font(.system(size: 19, weight: .semibold)).foregroundStyle(.blue)
                    }
                    if chevron {
                        Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(
                            ClaudePalette.secondary)
                    }
                }.padding(.horizontal, 16).padding(.vertical, detail == nil ? 14 : 14).contentShape(.rect)
            }.buttonStyle(.plain)
        }
    }
    struct RowGroup<Content: View>: View {
        @ViewBuilder var content: () -> Content
        var body: some View {
            VStack(spacing: 0, content: content).background(ClaudePalette.panel, in: .rect(cornerRadius: 28))
        }
    }
    struct RowDivider: View { var body: some View { Divider().padding(.horizontal, 16) } }
#endif
