#if canImport(UIKit)
    import SwiftUI

    public enum ClaudeMediaPresentation { case thumbnail, message, viewer, videoViewer }
    /// Pixels are injected by the host. This presentation neither reads a photo library nor fetches URLs.
    ///
    /// E3 §3.5: the canvas is black, the media fills the height it can, and an image pinches and
    /// pans (double-tap toggles 1×/2×) with its chrome still on tap. A video gets the host's
    /// `.videoViewer` content — its own native player — and reports appeared/disappeared so the
    /// host can pause it; there is no zoom on a player, and tap does not toggle chrome over the
    /// player's own controls.
    public struct ClaudeMediaViewer: View {
        public var item: ClaudeMedia
        public var controlsVisible: Bool
        public var mediaContent: (ClaudeMedia, ClaudeMediaPresentation) -> AnyView
        public var onAction: (ClaudeMediaAction) -> Void

        @State private var zoom: CGFloat = 1
        @State private var baseZoom: CGFloat = 1
        @State private var offset: CGSize = .zero
        @State private var baseOffset: CGSize = .zero
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

        private var isImage: Bool { item.kind == .image }

        public var body: some View {
            VStack(spacing: 0) {
                chrome
                GeometryReader { geometry in
                    let fitted = fittedSize(in: geometry.size)
                    ZStack {
                        if isImage {
                            mediaContent(item, .viewer)
                                .frame(width: fitted.width, height: fitted.height)
                                .scaleEffect(zoom)
                                .offset(offset)
                        } else {
                            mediaContent(item, .videoViewer)
                                .frame(width: fitted.width, height: fitted.height)
                                .onAppear { onAction(.videoViewerAppeared(item)) }
                                .onDisappear { onAction(.videoViewerDisappeared(item)) }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { toggleZoom() }
                    .onTapGesture { if isImage { onAction(.toggleControls) } }
                    .gesture(magnification)
                    .gesture(drag)
                    .animation(
                        Motion.disclosure.resolved(reduceMotion: reduceMotion), value: zoom)
                    .clipped()
                }
                .padding(.bottom, 24)
            }
            .background(.black)
            .foregroundStyle(.white)
            .preferredColorScheme(.dark)
            .statusBarHidden(false)
            .onChange(of: item.id) { _, _ in resetZoom() }
            .accessibilityIdentifier("media.viewer")
        }

        /// The top bar: close, the file name, and the image-only edit/share actions.
        private var chrome: some View {
            Group {
                if controlsVisible {
                    HStack {
                        Button {
                            onAction(.close)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.paseo(.body))
                                .frame(width: 44, height: 44)
                        }
                        .glassEffect(in: .circle)
                        .accessibilityLabel("Close image")
                        .accessibilityIdentifier("media.viewer.close")
                        Spacer(minLength: 8)
                        Text(item.fileName)
                            .font(.paseo(.headline))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if isImage {
                            HStack(spacing: 0) {
                                Button {
                                    onAction(.edit(item))
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.paseo(.body))
                                        .frame(width: 48, height: 44)
                                }
                                .accessibilityLabel("Edit image")
                                .accessibilityIdentifier("media.viewer.edit")
                                Button {
                                    onAction(.share(item))
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.paseo(.body))
                                        .frame(width: 48, height: 44)
                                }
                                .accessibilityLabel("Share image")
                                .accessibilityIdentifier("media.viewer.share")
                            }
                            .glassEffect(in: .capsule)
                        }
                    }
                } else {
                    Color.clear.frame(height: 44).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }

        private var magnification: some Gesture {
            MagnificationGesture()
                .onChanged { value in
                    guard isImage else { return }
                    zoom = min(5, max(1, baseZoom * value))
                }
                .onEnded { _ in
                    guard isImage else { return }
                    baseZoom = zoom
                    if zoom <= 1.05 { resetZoom() }
                }
        }

        private var drag: some Gesture {
            DragGesture()
                .onChanged { value in
                    guard isImage, zoom > 1 else { return }
                    offset = CGSize(
                        width: baseOffset.width + value.translation.width,
                        height: baseOffset.height + value.translation.height)
                }
                .onEnded { _ in
                    guard isImage else { return }
                    baseOffset = offset
                }
        }

        private func toggleZoom() {
            guard isImage else { return }
            if zoom > 1 {
                resetZoom()
            } else {
                zoom = 2
                baseZoom = 2
            }
        }

        private func resetZoom() {
            zoom = 1
            baseZoom = 1
            offset = .zero
            baseOffset = .zero
        }

        /// The media's frame: its aspect ratio fitted inside the canvas, never upscaled past it.
        private func fittedSize(in size: CGSize) -> CGSize {
            let aspect = item.displayAspectRatio
            var width = size.width
            var height = width / aspect
            if height > size.height {
                height = size.height
                width = height * aspect
            }
            return CGSize(width: max(width, 1), height: max(height, 1))
        }
    }
#endif
