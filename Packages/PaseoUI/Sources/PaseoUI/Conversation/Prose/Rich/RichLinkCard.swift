#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

struct RichLinkCard: View {
    let url: String

    @State private var metadata: LPLinkMetadata?
    @State private var hero: UIImage?
    @State private var icon: UIImage?
    @State private var showSafari = false
    @State private var showShare = false
    @State private var width: CGFloat = 0
    @Environment(\.richActions) private var richActions
    @Environment(\.richProseWidth) private var proseWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    /// The hero's width: the prose column when published, else this card's own measurement.
    private var slotWidth: CGFloat { proseWidth > 1 ? proseWidth : width }

    /// The OG image slot: 1.91:1 reserved from the first layout, so the card never
    /// changes height when the pixels land (C6). Tiles crop; the viewer never does.
    private var heroAspect: CGFloat { Metrics.ogHeroAspect }

    private var policy: MediaFetchPolicy {
        mediaFetchPolicy(
            kind: .linkPreview, knownBytes: nil,
            condition: richActions?.linkCondition ?? .assumed)
    }

    /// The metadata reads the cache on the first pass: remounts show the title
    /// immediately, and `.task` only fetches what is missing.
    private var resolvedMetadata: LPLinkMetadata? {
        if let metadata { return metadata }
        guard let parsed = URL(string: url) else { return nil }
        return RichLinkMetadataCache.metadata(for: parsed)
    }

    private var heroCacheKey: String { "hero:\(url)" }
    private var iconCacheKey: String { "icon:\(url)" }

    /// The hero reads the decoded cache on the first pass: a revisit lays the hero
    /// box out on frame one instead of flashing the text row.
    private var resolvedHero: UIImage? {
        hero ?? RichLinkHeroCache.image(for: heroCacheKey)
    }

    private var resolvedIcon: UIImage? {
        icon ?? RichLinkHeroCache.image(for: iconCacheKey)
    }

    private var linkTitle: String {
        if let title = resolvedMetadata?.title, !title.isEmpty { return title }
        return RichContentDetector.domain(for: url)
    }

    private var linkMeta: String {
        RichContentDetector.displayURL(url)
    }

    var body: some View {
        Button {
            showSafari = true
        } label: {
            if let hero = resolvedHero {
                PaseoMediaCard(
                    media: heroSlot(hero),
                    header: PaseoCardHeader(title: linkTitle, meta: linkMeta))
            } else {
                PaseoCard(content: LinkRowContent(
                    icon: resolvedIcon, title: linkTitle, meta: linkMeta))
            }
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        // The first-ever hero grows the card once, animated; revisits lay the
        // cached hero out on frame one and never animate.
        .animation(
            Motion.disclosure.resolved(reduceMotion: reduceMotion),
            value: resolvedHero != nil)
        .paseoCardMenu(
            openTitle: "Open",
            onOpen: { showSafari = true },
            onShare: { showShare = true },
            copyTitle: "Copy link",
            copyText: url,
            externalTitle: "Open in Safari",
            externalURL: URL(string: url))
        .paseoCardAccessibility(
            kind: "Link", title: linkTitle, meta: linkMeta, isButton: true)
        .background { widthReader }
        .task(id: url) { await loadMetadata() }
        .task(id: heroKey) { await loadHero() }
        .fullScreenCover(isPresented: $showSafari) {
            if let target = URL(string: url) {
                SafariView(url: target).ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showShare) {
            if let target = URL(string: url) {
                ActivityView(items: [target])
            }
        }
    }

    @ViewBuilder private func heroSlot(_ hero: UIImage) -> some View {
        Image(uiImage: hero)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .aspectRatio(heroAspect, contentMode: .fit)
            .clipped()
            .contentShape(.rect)
            .mediaSlot(width: slotWidth, heightCap: .infinity)
    }

    /// The card's inner width, for decoding the hero at the size it is drawn at.
    private var widthReader: some View {
        // `onGeometryChange` on the clear background instead of a `GeometryReader` per card (W1): same
        // size, delivered at once and on change, written only when it differs.
        Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                if width != newWidth { width = newWidth }
            }
    }

    /// Metadata fetches on cheap links only: Low Data Mode gets the text-only row
    /// (§12), offline keeps the domain row.
    private var heroKey: String? {
        guard policy == .automatic, width > 1 else { return nil }
        return "\(url)|\(MediaSizing.pixelWidth(points: width, scale: displayScale))"
    }

    @MainActor
    private func loadMetadata() async {
        guard policy == .automatic else { return }
        guard let parsed = URL(string: url) else { return }
        if let cached = RichLinkMetadataCache.metadata(for: parsed) {
            metadata = cached
        } else if let fetched = try? await Self.fetchMetadata(for: parsed) {
            RichLinkMetadataCache.store(fetched, for: parsed)
            metadata = fetched
        }
        await loadIcon()
    }

    @MainActor
    private func loadHero() async {
        guard heroKey != nil, resolvedHero == nil,
            !RichLinkHeroCache.missed(heroCacheKey)
        else { return }
        guard let provider = resolvedMetadata?.imageProvider else { return }
        guard let loaded: UIImage = try? await Self.loadImage(from: provider) else {
            RichLinkHeroCache.noteMiss(for: heroCacheKey)
            return
        }
        guard !Task.isCancelled else { return }
        // The provider hands over a full `UIImage` that decodes lazily on main at
        // first draw; thumbnail it off main at the card's pixel width first.
        let pixels = MediaSizing.pixelWidth(points: max(width, 1), scale: displayScale)
        guard
            let prepared = await loaded.byPreparingThumbnail(ofSize: CGSize(
                width: pixels, height: pixels))
        else {
            RichLinkHeroCache.noteMiss(for: heroCacheKey)
            return
        }
        RichLinkHeroCache.store(prepared, for: heroCacheKey)
        guard !Task.isCancelled else { return }
        hero = prepared
    }

    @MainActor
    private func loadIcon() async {
        guard resolvedIcon == nil, !RichLinkHeroCache.missed(iconCacheKey),
            let provider = resolvedMetadata?.iconProvider
        else { return }
        guard let loaded = try? await Self.loadImage(from: provider) else {
            RichLinkHeroCache.noteMiss(for: iconCacheKey)
            return
        }
        guard !Task.isCancelled else { return }
        guard
            let prepared = await loaded.byPreparingThumbnail(ofSize: CGSize(
                width: 96, height: 96))
        else {
            RichLinkHeroCache.noteMiss(for: iconCacheKey)
            return
        }
        RichLinkHeroCache.store(prepared, for: iconCacheKey)
        guard !Task.isCancelled else { return }
        icon = prepared
    }

    /// `NSItemProvider.loadObject(ofClass:)` is the async bridge for metadata images.
    /// Runs wherever the provider calls back; pixels hand off below.
    private static func loadImage(from provider: NSItemProvider) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image = object as? UIImage else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    /// LPMetadataProvider only documents the completion-handler API; bridging keeps the
    /// async call site without relying on an undocumented async variant.
    private static func fetchMetadata(for url: URL) async throws -> LPLinkMetadata {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MetadataBox, Error>) in
            LPMetadataProvider().startFetchingMetadata(for: url) { metadata, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let metadata else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                continuation.resume(returning: MetadataBox(value: metadata))
            }
        }.value
    }

    /// `LPLinkMetadata` isn't `Sendable`; the provider hands over a finished object that
    /// nothing mutates afterwards, so it is safe to carry across the completion hop.
    private struct MetadataBox: @unchecked Sendable {
        let value: LPLinkMetadata
    }
}
#endif
