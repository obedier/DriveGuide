import SwiftUI

/// Horizontal row of iconic cards showing the 3 nearest major metro areas to the user.
/// Tapping a card fills the search text box with the metro's display name.
struct NearbyMetrosRow: View {
    @StateObject private var service = MetroAreaService()
    @EnvironmentObject var tourVM: TourViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

                HStack(spacing: 10) {
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
            ZStack(alignment: .bottomLeading) {
                // Image
                AsyncImage(url: item.metro.imageURL) { phase in
                    switch phase {
                    case .empty:
                        LinearGradient(
                            colors: [.brandNavy, .brandGreen.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        LinearGradient(
                            colors: [.brandNavy, .brandGold.opacity(0.3)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        Image(systemName: "building.2")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.4))
                    @unknown default:
                        Color.brandNavy
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 96)
                .clipped()

                // Gradient overlay for text readability
                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .center, endPoint: .bottom
                )
                .frame(height: 96)

                // Text
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.metro.name)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(String(format: "%.0f mi", item.distanceMiles))
                        .font(.caption2)
                        .foregroundStyle(.brandGold)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brandGold.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }
}
