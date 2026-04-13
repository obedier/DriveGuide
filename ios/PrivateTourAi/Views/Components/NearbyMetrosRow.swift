import SwiftUI
import UIKit

/// Vertical stack of iconic cards showing the 3 nearest major metro areas to the user.
/// Tapping a card fills the search text box with the metro's display name.
struct NearbyMetrosRow: View {
    @StateObject private var service = MetroAreaService()
    @EnvironmentObject var tourVM: TourViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !service.nearestMetros.isEmpty {
                HStack {
                    Image(systemName: "location.north.fill")
                        .font(.caption2)
                        .foregroundStyle(.brandGold)
                    Text("Nearby Metros")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.leading, 4)

                VStack(spacing: 10) {
                    ForEach(service.nearestMetros) { item in
                        MetroCard(item: item) {
                            tourVM.searchText = item.metro.displayName
                            Task { await tourVM.verifyLocation() }
                        }
                    }
                }
            }
        }
        .task {
            await service.refreshNearest(count: 3)
        }
    }
}

private struct MetroCard: View {
    let item: MetroAreaService.MetroWithDistance
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: item.metro.imageURL)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    LinearGradient(
                        colors: [.black.opacity(0), .black.opacity(0.75)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(width: geo.size.width, height: geo.size.height * 0.6)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.metro.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            Text(item.metro.state)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        Text(String(format: "%.0f mi", item.distanceMiles))
                            .font(.caption.bold())
                            .foregroundStyle(.brandGold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.5), in: Capsule())
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brandGold.opacity(0.25)))
            }
            .frame(height: 110)
        }
        .buttonStyle(.plain)
    }
}

/// Image loader that uses URLSession with a proper User-Agent header
/// so Wikipedia/Wikimedia CDN allows the request. Behaves like SwiftUI's Image.
private struct RemoteImage: View {
    let url: URL?
    @State private var uiImage: UIImage?
    @State private var failed = false

    var body: some View {
        if let img = uiImage {
            Image(uiImage: img)
                .resizable()
        } else if failed {
            ZStack {
                LinearGradient(
                    colors: [.brandNavy, .brandGold.opacity(0.3)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: "building.2.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .task(id: url) { await load() }
        } else {
            LinearGradient(
                colors: [.brandNavy, .brandGreen.opacity(0.6)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .task(id: url) { await load() }
        }
    }

    private func load() async {
        guard let url else { failed = true; return }
        if let cached = RemoteImageCache.shared.image(for: url) {
            uiImage = cached
            return
        }
        var req = URLRequest(url: url)
        req.setValue("wAIpoint/2.5 (iOS; contact: obedier@gmail.com)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("[RemoteImage] Non-200 from \(url): \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                failed = true
                return
            }
            if let img = UIImage(data: data) {
                RemoteImageCache.shared.set(img, for: url)
                uiImage = img
            } else {
                failed = true
            }
        } catch {
            print("[RemoteImage] Failed to load \(url): \(error.localizedDescription)")
            failed = true
        }
    }
}

/// Tiny in-memory cache so AsyncImage-like reuse doesn't re-download.
private final class RemoteImageCache {
    static let shared = RemoteImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}
