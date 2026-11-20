#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// A calm MapKit snapshot (no live map in the transcript) that opens Apple Maps on tap.
struct RichMapCard: View {
    let reference: MapReference

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot: UIImage?

    private var targetURL: URL? {
        if let lat = reference.latitude, let lng = reference.longitude {
            return URL(string: "https://maps.apple.com/?ll=\(lat),\(lng)")
        }
        return URL(string: reference.url)
    }

    /// The 150 pt snapshot slot, edge to edge in the media card; the container clips it.
    private var snapshotBox: some View {
        ZStack {
            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Palette.codeSurface)
                    .overlay {
                        Image(systemName: "map")
                            .font(.glyph(.xlarge, weight: .light))
                            .foregroundStyle(Palette.secondaryInk)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .contentShape(.rect)
    }

    var body: some View {
        Button {
            if let targetURL { openURL(targetURL) }
        } label: {
            PaseoMediaCard(
                media: snapshotBox,
                header: PaseoCardHeader(glyph: "mappin", title: caption))
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .paseoCardMenu(
            openTitle: "Open in Maps",
            onOpen: { if let targetURL { openURL(targetURL) } },
            copyTitle: "Copy location",
            copyText: caption)
        .paseoCardAccessibility(kind: "Map", title: caption, isButton: true)
        .accessibilityHint("Opens Apple Maps")
        .task(id: "\(reference.latitude ?? 0),\(reference.longitude ?? 0)") {
            guard snapshot == nil, let lat = reference.latitude, let lng = reference.longitude else { return }
            if let cached = RichMapSnapshotCache.image(for: reference) {
                snapshot = cached
                return
            }
            snapshot = await Self.snapshot(lat: lat, lng: lng)
            if let snapshot {
                RichMapSnapshotCache.store(snapshot, for: reference)
            }
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
