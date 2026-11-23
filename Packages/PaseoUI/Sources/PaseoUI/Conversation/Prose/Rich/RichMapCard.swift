#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// A calm MapKit snapshot (no live map in the transcript) that opens Apple Maps on tap.
/// While the snapshot loads the slot shows a spinner; offline or after a failed render it
/// says so, with a Try again control beside the card (the card itself stays tappable).
struct RichMapCard: View {
    let reference: MapReference

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.richActions) private var richActions
    @State private var snapshot: UIImage?
    /// The render ended without an image.
    @State private var failed = false
    /// Bumped by Try again: reruns the load task.
    @State private var retryToken = 0

    /// The snapshot is a network fetch (Apple's tiles): it follows the same etiquette as the
    /// link card, so offline and Low Data Mode never start one.
    private var policy: MediaFetchPolicy {
        mediaFetchPolicy(
            kind: .linkPreview, knownBytes: nil,
            condition: richActions?.linkCondition ?? .assumed)
    }

    private var hasCoordinates: Bool {
        reference.latitude != nil && reference.longitude != nil
    }

    /// The decoded image from this card or an earlier visit, on the first pass.
    private var resolvedSnapshot: UIImage? {
        snapshot ?? RichMapSnapshotCache.image(for: reference)
    }

    private var loadKey: String {
        "\(reference.latitude ?? 0),\(reference.longitude ?? 0)|\(policy == .automatic)|\(retryToken)"
    }

    private var targetURL: URL? {
        if let lat = reference.latitude, let lng = reference.longitude {
            return URL(string: "https://maps.apple.com/?ll=\(lat),\(lng)")
        }
        return URL(string: reference.url)
    }

    /// The 150 pt snapshot slot, edge to edge in the media card; the container clips it.
    private var snapshotBox: some View {
        ZStack {
            if let resolvedSnapshot {
                Image(uiImage: resolvedSnapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Palette.codeSurface)
                    .overlay {
                        RichMapPlaceholder(
                            showsProgress: hasCoordinates && !failed && policy == .automatic,
                            message: placeholderMessage)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .contentShape(.rect)
    }

    /// What the empty slot says: nothing while loading or for a query-only link.
    private var placeholderMessage: String? {
        guard hasCoordinates, resolvedSnapshot == nil else { return nil }
        if failed { return "Couldn't load map preview" }
        if policy == .cacheOnly { return "No connection" }
        return nil
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: openInMaps) {
                PaseoMediaCard(
                    media: snapshotBox,
                    header: PaseoCardHeader(glyph: "mappin", title: caption))
            }
            .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
            .paseoCardMenu(
                openTitle: "Open in Maps",
                onOpen: openInMaps,
                copyTitle: "Copy location",
                copyText: caption)
            .paseoCardAccessibility(kind: "Map", title: caption, isButton: true)
            .accessibilityHint("Opens Apple Maps")
            if failed, resolvedSnapshot == nil {
                Button("Try again", systemImage: "arrow.clockwise", action: retry)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                    .contentShape(.rect)
                    .accessibilityHint("Tries loading the map preview again")
            }
        }
        .task(id: loadKey) { await loadSnapshot() }
    }

    private func retry() {
        failed = false
        retryToken += 1
    }

    private func openInMaps() {
        if let targetURL { openURL(targetURL) }
    }

    /// The cached render when there is one, else one fetch, stored for the next visit.
    @MainActor
    private func loadSnapshot() async {
        guard snapshot == nil, let lat = reference.latitude, let lng = reference.longitude else {
            return
        }
        if let cached = RichMapSnapshotCache.image(for: reference) {
            snapshot = cached
            return
        }
        // Offline and Low Data Mode keep the placeholder instead of fetching tiles.
        guard policy == .automatic else { return }
        failed = false
        let rendered = await Self.snapshot(lat: lat, lng: lng)
        guard !Task.isCancelled else { return }
        if let rendered {
            RichMapSnapshotCache.store(rendered, for: reference)
            snapshot = rendered
        } else {
            failed = true
        }
    }

    private var caption: String {
        if let lat = reference.latitude, let lng = reference.longitude {
            return "\(lat), \(lng)"
        }
        return RichContentDetector.displayURL(reference.url)
    }

    /// One static render of a 300×180 region around the point. Calm, and cached.
    private static func snapshot(lat: Double, lng: Double) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04))
        options.size = CGSize(width: 600, height: 360)
        options.showsBuildings = false
        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            return snapshot.image
        } catch {
            return nil
        }
    }
}
#endif
