import SwiftUI
import MapKit

struct TourDetailView: View {
    let tour: Tour
    @EnvironmentObject var tourVM: TourViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStop: TourStop?
    @State private var showGuidedTour = false
    @State private var showRegenerate = false
    @State private var regeneratePrompt = ""
    @State private var isRegenerating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Map header
                    Map {
                        ForEach(tour.stops) { stop in
                            Annotation(stop.name, coordinate: CLLocationCoordinate2D(
                                latitude: stop.latitude, longitude: stop.longitude
                            )) {
                                StopMarker(order: stop.sequenceOrder + 1, category: stop.category)
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding()

                    // Tour info
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tour.title)
                            .font(.title2.bold())

                        Text(tour.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 20) {
                            InfoBadge(icon: "mappin.and.ellipse", value: "\(tour.stops.count) stops")
                            InfoBadge(icon: "clock", value: formatDuration(tour.durationMinutes))
                            if let km = tour.totalDistanceKm {
                                InfoBadge(icon: "car", value: String(format: "%.1f km", km))
                            }
                        }
                        .padding(.vertical, 8)

                        if let summary = tour.storyArcSummary {
                            Text(summary)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(12)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        }

                        // Action buttons
                        VStack(spacing: 10) {
                            Button {
                                showGuidedTour = true
                            } label: {
                                HStack {
                                    Image(systemName: "headphones")
                                    Text("Start Guided Tour")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color("AccentCoral"))

                            Button {
                                if let urlStr = tour.mapsDirectionsUrl,
                                   let url = URL(string: urlStr) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                    Text("Open Route in Maps")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }
                    }
                    .padding(.horizontal)

                    // Regenerate section
                    VStack(spacing: 10) {
                        Button {
                            withAnimation { showRegenerate.toggle() }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Regenerate Tour")
                                Spacer()
                                Image(systemName: showRegenerate ? "chevron.up" : "chevron.down")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }

                        if showRegenerate {
                            VStack(spacing: 10) {
                                TextField("What should change? e.g. \"more food stops\", \"skip museums\"", text: $regeneratePrompt, axis: .vertical)
                                    .font(.callout)
                                    .lineLimit(2...4)
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    Task { await regenerateTour() }
                                } label: {
                                    HStack {
                                        if isRegenerating {
                                            ProgressView().scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "sparkles")
                                        }
                                        Text(isRegenerating ? "Regenerating..." : "Regenerate")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .disabled(isRegenerating)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Stops list
                    VStack(alignment: .leading, spacing: 0) {
                        Text("YOUR STOPS")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 16)
                            .padding(.bottom, 12)

                        ForEach(tour.stops) { stop in
                            StopRow(stop: stop, isLast: stop.id == tour.stops.last?.id)
                                .onTapGesture { selectedStop = stop }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let shareUrl = tourVM.shareTour() {
                        ShareLink(item: shareUrl, subject: Text(tour.title), message: Text("Check out this tour I made with Private TourAi!")) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $selectedStop) { stop in
            StopDetailSheet(stop: stop, allStops: tour.stops)
        }
        .fullScreenCover(isPresented: $showGuidedTour) {
            GuidedTourView(tour: tour)
        }
    }

    private func regenerateTour() async {
        isRegenerating = true
        let originalPrompt = tour.customPrompt ?? ""
        let combinedPrompt = [originalPrompt, regeneratePrompt]
            .filter { !$0.isEmpty }
            .joined(separator: ". Also: ")

        do {
            let newTour = try await APIClient.shared.generateFullTour(
                location: tour.locationQuery,
                durationMinutes: tour.durationMinutes,
                themes: tour.themes,
                transportMode: tour.transportMode ?? "car",
                customPrompt: combinedPrompt.isEmpty ? nil : combinedPrompt
            )
            TourStorage.shared.save(newTour)
            tourVM.savedTours = TourStorage.shared.loadAll()
            tourVM.currentTour = newTour
            regeneratePrompt = ""
            showRegenerate = false
        } catch {
            tourVM.error = error.localizedDescription
        }
        isRegenerating = false
    }
}

struct InfoBadge: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color("AccentCoral"))
            Text(value)
                .font(.caption)
        }
    }
}

struct StopRow: View {
    let stop: TourStop
    let isLast: Bool

    var categoryIcon: String {
        switch stop.category {
        case "landmark": return "building.columns.fill"
        case "restaurant": return "fork.knife"
        case "viewpoint": return "eye.fill"
        case "hidden-gem": return "diamond.fill"
        case "photo-op": return "camera.fill"
        case "park": return "leaf.fill"
        case "museum": return "building.2.fill"
        case "neighborhood": return "house.fill"
        default: return "mappin.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color("AccentCoral"))
                        .frame(width: 28, height: 28)
                    Text("\(stop.sequenceOrder + 1)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color("AccentCoral").opacity(0.3))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                // Photo
                if let photoUrl = stop.photoUrl, let url = URL(string: photoUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(.systemGray5)
                    }
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack {
                    Text(stop.name)
                        .font(.subheadline.bold())
                    Spacer()
                    Image(systemName: categoryIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(stop.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    if stop.recommendedStayMinutes > 0 {
                        Label("\(stop.recommendedStayMinutes) min", systemImage: "clock")
                    }
                    if stop.isOptional {
                        Label("Optional", systemImage: "arrow.uturn.right")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal)
    }
}

struct StopDetailSheet: View {
    let stops: [TourStop]
    @State var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(stop: TourStop, allStops: [TourStop]) {
        self.stops = allStops
        self._currentIndex = State(initialValue: allStops.firstIndex(where: { $0.id == stop.id }) ?? 0)
    }

    // Legacy init for compatibility
    init(stop: TourStop) {
        self.stops = [stop]
        self._currentIndex = State(initialValue: 0)
    }

    var stop: TourStop { stops[currentIndex] }
    var hasPrevious: Bool { currentIndex > 0 }
    var hasNext: Bool { currentIndex < stops.count - 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Photo
                    if let photoUrl = stop.photoUrl, let url = URL(string: photoUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color(.systemGray5)
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        // Mini map
                        Map {
                            Annotation(stop.name, coordinate: CLLocationCoordinate2D(
                                latitude: stop.latitude, longitude: stop.longitude
                            )) {
                                StopMarker(order: stop.sequenceOrder + 1, category: stop.category)
                            }
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    HStack {
                        Text(stop.name)
                            .font(.title2.bold())
                        Spacer()
                        Text("\(currentIndex + 1) of \(stops.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(stop.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()

                    NarrationSection(title: "As You Approach", text: stop.approachNarration)
                    NarrationSection(title: "At This Stop", text: stop.atStopNarration)
                    NarrationSection(title: "As You Leave", text: stop.departureNarration)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        Button {
                            withAnimation { currentIndex -= 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!hasPrevious)

                        Button {
                            withAnimation { currentIndex += 1 }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!hasNext)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct NarrationSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(Color("AccentCoral"))
            Text(text)
                .font(.callout)
                .lineSpacing(4)
        }
    }
}

struct PreviewDetailView: View {
    let preview: TourPreview
    @EnvironmentObject var tourVM: TourViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isUnlocking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(preview.title)
                        .font(.title2.bold())
                    Text(preview.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 20) {
                        InfoBadge(icon: "mappin.and.ellipse", value: "\(preview.stopCount) stops")
                        InfoBadge(icon: "clock", value: formatDuration(preview.durationMinutes))
                        if let km = preview.totalDistanceKm {
                            InfoBadge(icon: "car", value: String(format: "%.1f km", km))
                        }
                    }
                    .padding(.vertical, 4)

                    ForEach(preview.previewStops) { stop in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(stop.name)
                                    .font(.headline)
                                Spacer()
                                Text(stop.category.replacingOccurrences(of: "-", with: " ").capitalized)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color("AccentCoral").opacity(0.1), in: Capsule())
                                    .foregroundStyle(Color("AccentCoral"))
                            }
                            Text(stop.teaser)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Remaining stops teaser
                    if preview.stopCount > preview.previewStops.count {
                        HStack {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.secondary)
                            Text("+ \(preview.stopCount - preview.previewStops.count) more stops with full narration")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Unlock / Continue button
                    if isUnlocking || tourVM.isGenerating {
                        HStack(spacing: 14) {
                            ProgressView()
                                .tint(Color("AccentCoral"))
                            Text(tourVM.generationProgress.isEmpty ? "Unlocking your tour..." : tourVM.generationProgress)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        Button {
                            unlockFullTour()
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Get Full Guided Tour")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("AccentCoral"))
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: tourVM.currentTour != nil) { _, hasTour in
                if hasTour {
                    dismiss()
                }
            }
        }
    }

    private func unlockFullTour() {
        isUnlocking = true
        Task {
            await tourVM.unlockFullTour()
            isUnlocking = false
        }
    }
}
