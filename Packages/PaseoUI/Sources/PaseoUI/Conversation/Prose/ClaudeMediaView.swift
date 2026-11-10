#if canImport(UIKit)
    import SwiftUI

    public enum ClaudeMediaPresentation { case thumbnail, message, viewer, videoViewer }
    /// Pixels are injected by the host. This presentation neither reads a photo library nor fetches URLs.
    public struct ClaudeMediaViewer: View {
        public var item: ClaudeMedia
        public var controlsVisible: Bool
        public var mediaContent: (ClaudeMedia, ClaudeMediaPresentation) -> AnyView
        public var onAction: (ClaudeMediaAction) -> Void
        public init(
            item: ClaudeMedia, controlsVisible: Bool,
            mediaContent: @escaping (ClaudeMedia, ClaudeMediaPresentation) -> AnyView,
            onAction: @escaping (ClaudeMediaAction) -> Void
        ) {
            self.item = item
            self.controlsVisible = controlsVisible
            self.mediaContent = mediaContent
            self.onAction = onAction
        }
        public var body: some View {
            VStack(spacing: 0) {
                Group {
                    if controlsVisible {
                        HStack {
                            Button {
                                onAction(.close)
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 18)).frame(width: 44, height: 44)
                            }.glassEffect(in: .circle).accessibilityLabel("Close image").accessibilityIdentifier(
                                "media.viewer.close")
                            Spacer(minLength: 8)
                            Text(item.fileName).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 8)
                            HStack(spacing: 0) {
                                Button {
                                    onAction(.edit(item))
                                } label: {
                                    Image(systemName: "pencil").frame(width: 48, height: 44)
                                }.accessibilityLabel("Edit image").accessibilityIdentifier("media.viewer.edit")
                                Button {
                                    onAction(.share(item))
                                } label: {
                                    Image(systemName: "square.and.arrow.up").frame(width: 48, height: 44)
                                }.accessibilityLabel("Share image").accessibilityIdentifier("media.viewer.share")
                            }.glassEffect(in: .capsule)
                        }
                    } else {
                        Color.clear.frame(height: 44).accessibilityHidden(true)
                    }
                }.padding(.horizontal, 16).padding(.top, 16)
                GeometryReader { geometry in
                    let width = min(geometry.size.width, geometry.size.height * item.displayAspectRatio)
                    let height = width / item.displayAspectRatio
                    mediaContent(item, .viewer).frame(width: width, height: height).clipped()
                        .contentShape(Rectangle()).onTapGesture { onAction(.toggleControls) }
                        .accessibilityLabel(item.accessibilityDescription).accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("media.viewer.image")
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }.padding(.bottom, 24)
            }.background(.black).foregroundStyle(.white).preferredColorScheme(.dark).statusBarHidden(false)
        }
    }
#endif
