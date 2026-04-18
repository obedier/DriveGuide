import SwiftUI
import UIKit

/// Compact metro-area picker. Presented as a bottom sheet on iPhone and a popover on iPad
/// via `NearbyMetrosPresentation`. Text-only rows, brand-aligned, no network fetches.
struct NearbyMetrosSheet: View {
    @StateObject private var service = MetroAreaService()
    @EnvironmentObject var tourVM: TourViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.brandNavy.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                content
            }
        }
        .task { await service.resolve(count: 10) }
    }

    private var header: some View {
        HStack {
            Image(systemName: "location.north.fill")
                .foregroundStyle(.brandGold)
            Text("Nearby Cities")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Button("Close") { dismiss() }
                .font(.subheadline)
                .foregroundStyle(.brandGold)
                .accessibilityLabel("Close nearby cities")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch service.state {
        case .idle, .loading:
            loadingView
        case .permissionDenied:
            permissionDeniedView
        case .locationUnavailable:
            locationUnavailableView
        case .empty:
            emptyView
        case .loaded(let metros, let fallback):
            loadedView(metros: metros, fallback: fallback)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.brandGold)
            Text("Finding nearby cities…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    private var permissionDeniedView: some View {
        recoveryView(
            icon: "location.slash.fill",
            title: "Enable location to see nearby cities",
            subtitle: "We only use your location to suggest cities nearby.",
            primaryLabel: "Open Settings",
            primaryAction: openSettings,
            secondaryLabel: nil,
            secondaryAction: nil
        )
    }

    private var locationUnavailableView: some View {
        VStack(spacing: 14) {
            recoveryView(
                icon: "mappin.slash",
                title: "Can't find your location right now",
                subtitle: "Pick from top US cities below, or retry.",
                primaryLabel: "Retry",
                primaryAction: { Task { await service.resolve(count: 10) } },
                secondaryLabel: nil,
                secondaryAction: nil
            )
            Divider().overlay(.brandGold.opacity(0.3)).padding(.horizontal, 20)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(topUSFallback) { item in
                        MetroRow(item: item, distanceLabel: nil) { pick(item) }
                    }
                }
            }
        }
    }

    private var emptyView: some View {
        recoveryView(
            icon: "building.2",
            title: "No major cities nearby",
            subtitle: "Try searching by name instead.",
            primaryLabel: "Retry",
            primaryAction: { Task { await service.resolve(count: 10) } },
            secondaryLabel: nil,
            secondaryAction: nil
        )
    }

    private func loadedView(metros: [MetroAreaService.MetroWithDistance], fallback: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if fallback {
                    Text("Currently US cities only")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
                }
                ForEach(metros) { item in
                    MetroRow(
                        item: item,
                        distanceLabel: String(format: "%.0f mi", item.distanceMiles)
                    ) { pick(item) }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func recoveryView(
        icon: String,
        title: String,
        subtitle: String,
        primaryLabel: String,
        primaryAction: @escaping () -> Void,
        secondaryLabel: String?,
        secondaryAction: (() -> Void)?
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.brandGold.opacity(0.8))
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button(primaryLabel, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .tint(.brandGold)
                .foregroundStyle(.brandNavy)
                .padding(.top, 4)
            if let secondaryLabel, let secondaryAction {
                Button(secondaryLabel, action: secondaryAction)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func pick(_ item: MetroAreaService.MetroWithDistance) {
        tourVM.searchText = item.metro.displayName
        dismiss()
        Task { await tourVM.verifyLocation() }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Fallback list (top US metros by population — shown when location is unavailable)

    private var topUSFallback: [MetroAreaService.MetroWithDistance] {
        let names = ["New York", "Los Angeles", "Chicago", "Houston", "Washington", "Miami"]
        return service.nearestMetros(to: .init(latitude: 39.5, longitude: -98.35), inCountry: "US", count: 60)
            .filter { names.contains($0.metro.name) }
    }
}

// MARK: - Row

private struct MetroRow: View {
    let item: MetroAreaService.MetroWithDistance
    let distanceLabel: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle")
                    .font(.title3)
                    .foregroundStyle(.brandGold)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.metro.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(item.metro.state)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                if let distanceLabel {
                    Text(distanceLabel)
                        .font(.caption.bold())
                        .foregroundStyle(.brandGold)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        if let distanceLabel {
            return "\(item.metro.name), \(item.metro.state), \(distanceLabel) away"
        }
        return "\(item.metro.name), \(item.metro.state)"
    }
}

// MARK: - Size-class aware presentation modifier

/// Presents `NearbyMetrosSheet` as a bottom sheet on iPhone and as a popover on iPad.
struct NearbyMetrosPresentation: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content
                .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds)) {
                    NearbyMetrosSheet()
                        .frame(idealWidth: 360, idealHeight: 520)
                        .presentationCompactAdaptation(.popover)
                }
        } else {
            content
                .sheet(isPresented: $isPresented) {
                    NearbyMetrosSheet()
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
        }
    }
}

extension View {
    func nearbyMetrosPresentation(isPresented: Binding<Bool>) -> some View {
        modifier(NearbyMetrosPresentation(isPresented: isPresented))
    }
}
