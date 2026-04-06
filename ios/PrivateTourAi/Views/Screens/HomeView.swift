import SwiftUI
import MapKit

struct HomeView: View {
    @EnvironmentObject var tourVM: TourViewModel
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918),
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
    )

    var body: some View {
        ZStack {
            // Map background
            Map(position: $cameraPosition) {
                // Show verified location pin
                if let loc = tourVM.verifiedLocation {
                    Annotation("", coordinate: CLLocationCoordinate2D(
                        latitude: loc.latitude, longitude: loc.longitude
                    )) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(Color("AccentCoral"))
                    }
                }
                // Show tour stops
                if let tour = tourVM.currentTour {
                    ForEach(tour.stops) { stop in
                        Annotation(stop.name, coordinate: CLLocationCoordinate2D(
                            latitude: stop.latitude, longitude: stop.longitude
                        )) {
                            StopMarker(order: stop.sequenceOrder + 1, category: stop.category)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()

            // Overlay
            VStack {
                SearchCard()
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer()

                // Bottom cards
                if tourVM.isGenerating {
                    GeneratingCard(progress: tourVM.generationProgress)
                        .padding()
                        .transition(.move(edge: .bottom))
                } else if let preview = tourVM.currentPreview {
                    PreviewCard(preview: preview) {
                        tourVM.showTourDetail = true
                    }
                    .padding()
                    .transition(.move(edge: .bottom))
                } else if tourVM.currentTour != nil {
                    TourReadyCard(tour: tourVM.currentTour!) {
                        tourVM.showTourDetail = true
                    }
                    .padding()
                    .transition(.move(edge: .bottom))
                }

                if let error = tourVM.error {
                    ErrorBanner(message: error) { tourVM.error = nil }
                        .padding(.horizontal)
                }
            }
        }
        .sheet(isPresented: $tourVM.showTourDetail) {
            if let tour = tourVM.currentTour {
                TourDetailView(tour: tour)
                    .environmentObject(tourVM)
            } else if let preview = tourVM.currentPreview {
                PreviewDetailView(preview: preview)
                    .environmentObject(tourVM)
            }
        }
        // Zoom to verified location
        .onChange(of: tourVM.verifiedLocation?.latitude) { _, newLat in
            if let lat = newLat, let lng = tourVM.verifiedLocation?.longitude {
                withAnimation(.easeInOut(duration: 0.8)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                        span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
                    ))
                }
            }
        }
        // Zoom to tour stops
        .onChange(of: tourVM.currentTour?.id) { _, _ in
            if let tour = tourVM.currentTour, !tour.stops.isEmpty {
                let lats = tour.stops.map(\.latitude)
                let lngs = tour.stops.map(\.longitude)
                let center = CLLocationCoordinate2D(
                    latitude: (lats.min()! + lats.max()!) / 2,
                    longitude: (lngs.min()! + lngs.max()!) / 2
                )
                let span = MKCoordinateSpan(
                    latitudeDelta: max((lats.max()! - lats.min()!) * 1.4, 0.02),
                    longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.4, 0.02)
                )
                withAnimation(.easeInOut(duration: 0.8)) {
                    cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
                }
            }
        }
        .animation(.spring(response: 0.4), value: tourVM.isVerifying)
        .animation(.spring(response: 0.4), value: tourVM.isGenerating)
        .animation(.spring(response: 0.4), value: tourVM.currentPreview != nil)
        .animation(.spring(response: 0.4), value: tourVM.currentTour != nil)
    }
}

// MARK: - Search Card (autocomplete + inline verify)

struct SearchCard: View {
    @EnvironmentObject var tourVM: TourViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var showOptions = false
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("City, neighborhood, or address...", text: $tourVM.searchText)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        isSearchFocused = false
                        Task { await tourVM.confirmAndGenerate() }
                    }
                    .onChange(of: tourVM.searchText) { _, newValue in
                        // Debounced autocomplete: verify location after typing stops
                        debounceTask?.cancel()
                        if newValue.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 {
                            debounceTask = Task {
                                try? await Task.sleep(for: .seconds(1.0))
                                if !Task.isCancelled {
                                    await tourVM.verifyLocation()
                                }
                            }
                        }
                    }

                if tourVM.isVerifying {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                // Current location button
                Button { tourVM.useCurrentLocation() } label: {
                    Image(systemName: "location.fill")
                        .foregroundStyle(Color("AccentCoral"))
                }

                if !tourVM.searchText.isEmpty {
                    Button { tourVM.searchText = ""; tourVM.clearTour() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            // Verified address confirmation (inline, subtle)
            if let loc = tourVM.verifiedLocation, !tourVM.isLocationConfirmed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(loc.formattedAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .transition(.opacity)
            }

            // Duration + themes + create button (always visible when search has content)
            if showOptions || tourVM.verifiedLocation != nil {
                VStack(spacing: 10) {
                    // Duration picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tourVM.durations, id: \.self) { duration in
                                DurationChip(
                                    duration: duration,
                                    isSelected: tourVM.selectedDuration == duration
                                ) {
                                    tourVM.selectedDuration = duration
                                }
                            }
                        }
                    }

                    // Theme pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tourVM.availableThemes, id: \.self) { theme in
                                ThemeChip(
                                    theme: theme,
                                    isSelected: tourVM.selectedThemes.contains(theme)
                                ) {
                                    if tourVM.selectedThemes.contains(theme) {
                                        tourVM.selectedThemes.remove(theme)
                                    } else {
                                        tourVM.selectedThemes.insert(theme)
                                    }
                                }
                            }
                        }
                    }

                    // Create Tour button
                    if tourVM.verifiedLocation != nil {
                        Button {
                            isSearchFocused = false
                            Task { await tourVM.confirmAndGenerate() }
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Create Tour")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("AccentCoral"))
                        .disabled(tourVM.isGenerating)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        .onChange(of: isSearchFocused) { _, focused in
            withAnimation(.spring(response: 0.3)) { showOptions = focused }
        }
        .animation(.spring(response: 0.3), value: tourVM.verifiedLocation != nil)
    }
}

// MARK: - Chips

struct DurationChip: View {
    let duration: Int
    let isSelected: Bool
    let action: () -> Void

    var label: String {
        if duration < 60 { return "\(duration)m" }
        let h = duration / 60
        let m = duration % 60
        return m > 0 ? "\(h)h\(m)m" : "\(h)h"
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color("AccentCoral") : Color(.systemGray5), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}

struct ThemeChip: View {
    let theme: String
    let isSelected: Bool
    let action: () -> Void

    var icon: String {
        switch theme {
        case "history": return "clock.fill"
        case "food": return "fork.knife"
        case "scenic": return "eye.fill"
        case "hidden-gems": return "diamond.fill"
        case "architecture": return "building.2.fill"
        case "culture": return "theatermasks.fill"
        case "nature": return "leaf.fill"
        case "nightlife": return "moon.stars.fill"
        default: return "star.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(theme.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color("AccentCoral").opacity(0.15) : Color(.systemGray6), in: Capsule())
            .foregroundStyle(isSelected ? Color("AccentCoral") : .secondary)
            .overlay(Capsule().stroke(isSelected ? Color("AccentCoral") : .clear, lineWidth: 1))
        }
    }
}

// MARK: - Cards

struct GeneratingCard: View {
    let progress: String

    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(Color("AccentCoral"))
            Text(progress)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct PreviewCard: View {
    let preview: TourPreview
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(preview.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Text(preview.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack {
                    Label("\(preview.stopCount) stops", systemImage: "mappin.and.ellipse")
                    Spacer()
                    Label(formatDuration(preview.durationMinutes), systemImage: "clock")
                    if let km = preview.totalDistanceKm {
                        Spacer()
                        Label(String(format: "%.1f km", km), systemImage: "car")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct TourReadyCard: View {
    let tour: Tour
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tour.title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Text("\(tour.stops.count) stops \u{2022} \(formatDuration(tour.durationMinutes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct StopMarker: View {
    let order: Int
    let category: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color("AccentCoral"))
                .frame(width: 32, height: 32)
            Text("\(order)")
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Helpers

func formatDuration(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) min" }
    let h = minutes / 60
    let m = minutes % 60
    return m > 0 ? "\(h)h \(m)m" : "\(h) hr"
}
