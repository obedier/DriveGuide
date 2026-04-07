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
            // Map background — dark style
            Map(position: $cameraPosition) {
                if let loc = tourVM.verifiedLocation {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.brandGold)
                    }
                }
                if let tour = tourVM.currentTour {
                    ForEach(tour.stops) { stop in
                        Annotation(stop.name, coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)) {
                            StopMarker(order: stop.sequenceOrder + 1, category: stop.category)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
            .ignoresSafeArea()
            // Dark overlay for brand feel
            Color.brandDarkNavy.opacity(0.3).ignoresSafeArea()

            VStack(spacing: 0) {
                SearchCard()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .disabled(tourVM.isGenerating)
                    .opacity(tourVM.isGenerating ? 0.4 : 1)

                Spacer()

                if let preview = tourVM.currentPreview, !tourVM.isGenerating {
                    PreviewCard(preview: preview) { tourVM.showTourDetail = true }
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .bottom))
                } else if let tour = tourVM.currentTour {
                    TourReadyCard(tour: tour) { tourVM.showTourDetail = true }
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .bottom))
                }

                if let error = tourVM.error {
                    ErrorBanner(message: error) { tourVM.error = nil }
                        .padding(.horizontal, 16)
                }

                // Brand watermark
                if !tourVM.isGenerating && tourVM.currentPreview == nil && tourVM.currentTour == nil {
                    Text("wAIpoint")
                        .font(.caption)
                        .foregroundStyle(.brandGold.opacity(0.5))
                        .padding(.bottom, 8)
                }
            }
        }
        // Full-screen generation overlay
        .overlay {
            if tourVM.isGenerating {
                GenerationView(progress: tourVM.generationProgress)
                    .transition(.opacity)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $tourVM.showTourDetail) {
            if let tour = tourVM.currentTour {
                TourDetailView(tour: tour).environmentObject(tourVM)
            } else if let preview = tourVM.currentPreview {
                PreviewDetailView(preview: preview).environmentObject(tourVM)
            }
        }
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
        .onChange(of: tourVM.currentTour?.id) { _, _ in
            if let tour = tourVM.currentTour, !tour.stops.isEmpty {
                let lats = tour.stops.map(\.latitude)
                let lngs = tour.stops.map(\.longitude)
                withAnimation(.easeInOut(duration: 0.8)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2),
                        span: MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.4, 0.02), longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.4, 0.02))
                    ))
                }
            }
        }
        .animation(.spring(response: 0.4), value: tourVM.isGenerating)
        .animation(.spring(response: 0.4), value: tourVM.currentPreview != nil)
        .animation(.spring(response: 0.4), value: tourVM.currentTour != nil)
    }
}

// MARK: - Compass Generation View (from Stitch design 1)

struct GenerationView: View {
    let progress: String
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Compass rose
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.brandGreen.opacity(0.3), .clear], center: .center, startRadius: 40, endRadius: 100))
                    .frame(width: 200, height: 200)

                Circle()
                    .stroke(.brandGold.opacity(0.4), lineWidth: 2)
                    .frame(width: 160, height: 160)

                Image(systemName: "safari.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(.brandGold)
                    .rotationEffect(.degrees(rotation))

                Text("W")
                    .font(.title2.bold())
                    .foregroundStyle(.brandGold)
            }

            // Loading spinner
            ProgressView()
                .tint(.brandGold)
                .scaleEffect(1.2)

            // Progress messages
            Text(progress)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandDarkNavy.opacity(0.85))
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Search Card (from Stitch design 4)

struct SearchCard: View {
    @EnvironmentObject var tourVM: TourViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var showOptions = false
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 10) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.brandGold)
                TextField("City, neighborhood, or a...", text: $tourVM.searchText)
                    .focused($isSearchFocused)
                    .foregroundStyle(.white)
                    .submitLabel(.search)
                    .onSubmit {
                        isSearchFocused = false
                        Task { await tourVM.confirmAndGenerate() }
                    }
                    .onChange(of: tourVM.searchText) { _, newValue in
                        debounceTask?.cancel()
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Need at least 5 chars to avoid partial geocoding ("New to" instead of "New York")
                        if trimmed.count >= 5 {
                            debounceTask = Task {
                                // Wait 2 seconds after last keystroke to ensure user finished typing
                                try? await Task.sleep(for: .seconds(2.0))
                                if !Task.isCancelled { await tourVM.verifyLocation() }
                            }
                        }
                    }

                if tourVM.isVerifying {
                    ProgressView().scaleEffect(0.8).tint(.brandGold)
                }

                Button { tourVM.useCurrentLocation() } label: {
                    Image(systemName: "location.fill").foregroundStyle(.brandGold)
                }

                if !tourVM.searchText.isEmpty {
                    Button { tourVM.searchText = ""; tourVM.clearTour() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(12)
            .background(Color.brandDarkNavy.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))

            // Verified address
            if let loc = tourVM.verifiedLocation, !tourVM.isLocationConfirmed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    Text(loc.formattedAddress).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                .padding(.horizontal, 12)
            }

            // Options (always show when location is verified or search focused)
            if showOptions || tourVM.verifiedLocation != nil {
                VStack(spacing: 8) {
                    // Duration chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tourVM.durations, id: \.self) { dur in
                                DurationChip(duration: dur, isSelected: tourVM.selectedDuration == dur) {
                                    tourVM.selectedDuration = dur
                                }
                            }
                        }
                    }

                    // Transport modes (from Stitch design)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tourVM.transportModes, id: \.self) { mode in
                                TransportChip(mode: mode, isSelected: tourVM.transportMode == mode) {
                                    tourVM.transportMode = mode
                                }
                            }
                        }
                    }

                    // Theme pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tourVM.availableThemes, id: \.self) { theme in
                                ThemeChip(theme: theme, isSelected: tourVM.selectedThemes.contains(theme)) {
                                    if tourVM.selectedThemes.contains(theme) { tourVM.selectedThemes.remove(theme) }
                                    else { tourVM.selectedThemes.insert(theme) }
                                }
                            }
                        }
                    }

                    // Advanced toggle
                    Button {
                        withAnimation { tourVM.showAdvancedSettings.toggle() }
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                            Text("Advanced")
                            Spacer()
                            Image(systemName: tourVM.showAdvancedSettings ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                    }

                    if tourVM.showAdvancedSettings {
                        VStack(spacing: 6) {
                            HStack {
                                Toggle(isOn: $tourVM.useAsStartLocation) {
                                    Label("Start here", systemImage: "flag.fill").font(.caption)
                                }
                                .toggleStyle(.switch).tint(.brandGold)
                                Toggle(isOn: $tourVM.useAsEndLocation) {
                                    Label("End here", systemImage: "flag.checkered").font(.caption)
                                }
                                .toggleStyle(.switch).tint(.brandGold)
                            }
                            HStack {
                                Text("Speed").font(.caption).foregroundStyle(.white.opacity(0.5))
                                Spacer()
                                TextField("Auto", value: $tourVM.speedMph, format: .number)
                                    .textFieldStyle(.roundedBorder).frame(width: 70).font(.caption)
                            }
                            TextField("Special focus: \"homes of movie stars\"...", text: $tourVM.customPrompt, axis: .vertical)
                                .font(.caption).lineLimit(2...3).textFieldStyle(.roundedBorder)
                        }
                    }

                    // Create Tour button (gold, from Stitch)
                    if tourVM.verifiedLocation != nil {
                        if tourVM.currentPreview != nil || tourVM.currentTour != nil {
                            HStack(spacing: 8) {
                                Button { tourVM.showTourDetail = true } label: {
                                    HStack { Image(systemName: "eye"); Text("View") }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                }
                                .buttonStyle(.borderedProminent).tint(.brandGold)
                                Button {
                                    isSearchFocused = false
                                    withAnimation { showOptions = false }
                                    tourVM.clearTour()
                                    Task { await tourVM.confirmAndGenerate() }
                                } label: {
                                    HStack { Image(systemName: "arrow.triangle.2.circlepath"); Text("New") }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                }
                                .buttonStyle(.bordered).tint(.brandGold)
                            }
                        } else {
                            Button {
                                isSearchFocused = false
                                withAnimation(.spring(response: 0.3)) { showOptions = false }
                                Task { await tourVM.confirmAndGenerate() }
                            } label: {
                                HStack {
                                    Text("Create Tour").fontWeight(.semibold)
                                    Image(systemName: "compass.drawing")
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                            }
                            .buttonStyle(.borderedProminent).tint(.brandGold)
                            .disabled(tourVM.isGenerating)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(Color.brandNavy.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
        .onChange(of: isSearchFocused) { _, focused in
            withAnimation(.spring(response: 0.3)) { showOptions = focused }
        }
        .animation(.spring(response: 0.3), value: tourVM.verifiedLocation != nil)
    }
}

// MARK: - Chips (gold-themed)

struct DurationChip: View {
    let duration: Int; let isSelected: Bool; let action: () -> Void
    var label: String {
        if duration < 60 { return "\(duration)m" }
        let h = duration / 60; let m = duration % 60
        return m > 0 ? "\(h)h\(m)m" : "\(h)h"
    }
    var body: some View {
        Button(action: action) {
            Text(label).font(.caption.bold())
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(isSelected ? Color.brandGold : Color.white.opacity(0.1), in: Capsule())
                .foregroundStyle(isSelected ? .brandNavy : .white)
        }
    }
}

struct TransportChip: View {
    let mode: String; let isSelected: Bool; let action: () -> Void
    var icon: String {
        switch mode {
        case "car": return "car.fill"; case "walk": return "figure.walk"
        case "bike": return "bicycle"; case "boat": return "ferry.fill"
        case "plane": return "airplane"; default: return "car.fill"
        }
    }
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.body)
                Text(mode.capitalized).font(.caption2)
            }
            .frame(width: 50, height: 44)
            .background(isSelected ? Color.brandGold : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(isSelected ? .brandNavy : .white)
        }
    }
}

struct ThemeChip: View {
    let theme: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(theme.replacingOccurrences(of: "-", with: " ").capitalized)
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(isSelected ? Color.brandGold.opacity(0.2) : Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(isSelected ? .brandGold : .white.opacity(0.7))
                .overlay(Capsule().stroke(isSelected ? Color.brandGold : .clear, lineWidth: 1))
        }
    }
}

// MARK: - Bottom Cards

struct PreviewCard: View {
    let preview: TourPreview; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(preview.title).font(.headline).foregroundStyle(.brandGold)
                Text(preview.description).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                HStack {
                    Label("\(preview.stopCount) stops", systemImage: "mappin.and.ellipse")
                    Spacer()
                    Label(formatDuration(preview.durationMinutes), systemImage: "clock")
                    if let km = preview.totalDistanceKm {
                        Spacer()
                        Label(String(format: "%.1f mi", km * 0.621371), systemImage: "car")
                    }
                }
                .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            .padding(16)
            .background(Color.brandNavy.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct TourReadyCard: View {
    let tour: Tour; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(tour.title).font(.headline).foregroundStyle(.brandGold)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Text("\(tour.stops.count) stops \u{2022} \(formatDuration(tour.durationMinutes))")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            .padding(16)
            .background(Color.brandNavy.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct ErrorBanner: View {
    let message: String; let onDismiss: () -> Void
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).foregroundStyle(.white)
            Spacer()
            Button(action: onDismiss) { Image(systemName: "xmark").font(.caption).foregroundStyle(.white.opacity(0.5)) }
        }
        .padding(12)
        .background(Color.brandNavy.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct StopMarker: View {
    let order: Int; let category: String
    var body: some View {
        ZStack {
            Circle().fill(Color.brandGold).frame(width: 32, height: 32)
            Text("\(order)").font(.caption.bold()).foregroundStyle(.brandNavy)
        }
    }
}

func formatDuration(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) min" }
    let h = minutes / 60; let m = minutes % 60
    return m > 0 ? "\(h)h \(m)m" : "\(h) hr"
}
