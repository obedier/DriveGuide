import SwiftUI
import MapKit

struct TourDetailView: View {
    let tour: Tour
    @EnvironmentObject var tourVM: TourViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStop: TourStop?
    @State private var showGuidedTour = false
    @State private var showPaywall = false
    @State private var showRegenerate = false
    @StateObject private var store = StoreKitService.shared
    @State private var regeneratePrompt = ""
    @State private var isRegenerating = false

    // Editable stops (local state so drag/remove/insert work without mutating immutable Tour)
    @State private var editableStops: [TourStop] = []
    @State private var isEditing = false
    @State private var showAddStopSheet = false
    @State private var insertAfterIndex: Int = 0

    // Use editable stops once loaded, otherwise fall back to tour.stops
    private var displayStops: [TourStop] {
        editableStops.isEmpty ? tour.stops : editableStops
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Map header
                    Map {
                        ForEach(displayStops) { stop in
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
                            InfoBadge(icon: "mappin.and.ellipse", value: "\(displayStops.count) stops")
                            InfoBadge(icon: "clock", value: formatDuration(tour.durationMinutes))
                            if let km = tour.totalDistanceKm {
                                let miles = km * 0.621371
                                let distIcon = transportIconFor(tour.transportMode)
                                let unit = (tour.transportMode == "boat") ? "nm" : "mi"
                                let dist = (tour.transportMode == "boat") ? km * 0.539957 : miles
                                InfoBadge(icon: distIcon, value: String(format: "%.1f %@", dist, unit))
                            }
                            if let mode = tour.transportMode, mode != "car" {
                                InfoBadge(icon: transportIconFor(mode), value: mode.capitalized)
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
                            // Start Guided Tour
                            Button {
                                if store.isPremium {
                                    showGuidedTour = true
                                } else {
                                    showPaywall = true
                                }
                            } label: {
                                HStack {
                                    Image(systemName: store.isPremium ? "location.fill" : "lock.fill")
                                    Text(store.isPremium ? "Start Guided Tour" : "Unlock Guided Tour")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.brandGold)

                            // Open in Google Maps app (falls back to Apple Maps / web)
                            Button { openInGoogleMaps() } label: {
                                HStack {
                                    Image(systemName: "map.fill")
                                    Text("Open in Google Maps")
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

                    // Stops list header with prominent Edit + Add buttons
                    HStack(spacing: 10) {
                        Text("YOUR STOPS")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        // Add button — uses smart insertion
                        Button {
                            showAddStopSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add")
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.brandGold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.brandGold.opacity(0.15), in: Capsule())
                        }

                        // Edit button
                        Button { withAnimation { isEditing.toggle() } } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle.fill")
                                Text(isEditing ? "Done" : "Edit")
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.brandGold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.brandGold.opacity(0.15), in: Capsule())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    // Stops list
                    if isEditing {
                        editableStopsList
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(displayStops) { stop in
                                StopRow(stop: stop, isLast: stop.id == displayStops.last?.id)
                                    .onTapGesture { selectedStop = stop }
                            }
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
        .onAppear {
            if editableStops.isEmpty { editableStops = tour.stops }
        }
        .sheet(item: $selectedStop) { stop in
            StopDetailSheet(stop: stop, allStops: displayStops)
        }
        .fullScreenCover(isPresented: $showGuidedTour) {
            GuidedTourView(tour: tourWithEditedStops())
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showAddStopSheet) {
            AddStopSearchSheet(
                nearLatitude: tourCentroid().latitude,
                nearLongitude: tourCentroid().longitude,
                onAdd: { newStop in
                    let bestIdx = bestInsertionIndex(for: newStop)
                    insertStop(newStop, at: bestIdx)
                    showAddStopSheet = false
                }
            )
        }
    }

    // MARK: - Smart Insertion

    private func tourCentroid() -> CLLocationCoordinate2D {
        guard !displayStops.isEmpty else {
            return CLLocationCoordinate2D(latitude: tour.stops.first?.latitude ?? 0, longitude: tour.stops.first?.longitude ?? 0)
        }
        let avgLat = displayStops.map { $0.latitude }.reduce(0, +) / Double(displayStops.count)
        let avgLng = displayStops.map { $0.longitude }.reduce(0, +) / Double(displayStops.count)
        return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLng)
    }

    /// Find the insertion index that minimizes total route distance.
    /// Tries inserting the new stop between each pair of consecutive existing stops,
    /// plus at the start/end, and picks the position with the lowest added distance.
    private func bestInsertionIndex(for newStop: TourStop) -> Int {
        let stops = displayStops
        guard stops.count >= 2 else { return stops.count } // append if 0 or 1 stops
        let newLoc = CLLocation(latitude: newStop.latitude, longitude: newStop.longitude)

        var bestIdx = stops.count
        var bestDelta = Double.infinity

        // Evaluate each insertion position (between stops)
        for i in 0...stops.count {
            let delta: Double
            if i == 0 {
                // Insert at start: newStop → stops[0]
                let next = CLLocation(latitude: stops[0].latitude, longitude: stops[0].longitude)
                delta = newLoc.distance(from: next)
            } else if i == stops.count {
                // Insert at end: stops[last] → newStop
                let prev = CLLocation(latitude: stops[i - 1].latitude, longitude: stops[i - 1].longitude)
                delta = prev.distance(from: newLoc)
            } else {
                // Insert between stops[i-1] and stops[i]:
                // delta = d(prev→new) + d(new→next) - d(prev→next)
                let prev = CLLocation(latitude: stops[i - 1].latitude, longitude: stops[i - 1].longitude)
                let next = CLLocation(latitude: stops[i].latitude, longitude: stops[i].longitude)
                delta = prev.distance(from: newLoc) + newLoc.distance(from: next) - prev.distance(from: next)
            }
            if delta < bestDelta {
                bestDelta = delta
                bestIdx = i
            }
        }
        return bestIdx
    }

    // MARK: - Editable Stops List (native iOS List with drag + swipe)

    private var editableStopsList: some View {
        VStack(spacing: 0) {
            // Native List with drag + swipe to delete
            List {
                ForEach(displayStops) { stop in
                    CompactStopRow(stop: stop)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                if let idx = displayStops.firstIndex(where: { $0.id == stop.id }) {
                                    removeStop(at: idx)
                                }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
                .onMove { source, destination in
                    editableStops.move(fromOffsets: source, toOffset: destination)
                    resequenceStops()
                    saveChanges()
                }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .frame(height: CGFloat(displayStops.count) * 72 + 20) // Fit all rows
            .environment(\.editMode, .constant(.active))

            // Helpful hint
            HStack(spacing: 6) {
                Image(systemName: "hand.draw.fill").font(.caption2)
                Text("Drag the handle to reorder · Swipe left to remove")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Stop Editing

    private func moveStop(from: Int, to: Int) {
        guard from >= 0 && from < editableStops.count,
              to >= 0 && to < editableStops.count else { return }
        let stop = editableStops.remove(at: from)
        editableStops.insert(stop, at: to)
        resequenceStops()
        saveChanges()
    }

    private func removeStop(at idx: Int) {
        guard idx >= 0 && idx < editableStops.count else { return }
        editableStops.remove(at: idx)
        resequenceStops()
        saveChanges()
    }

    private func insertStop(_ stop: TourStop, at idx: Int) {
        let safeIdx = min(max(idx, 0), editableStops.count)
        editableStops.insert(stop, at: safeIdx)
        resequenceStops()
        saveChanges()
    }

    private func resequenceStops() {
        editableStops = editableStops.enumerated().map { idx, stop in
            TourStop(
                id: stop.id, sequenceOrder: idx, name: stop.name,
                description: stop.description, category: stop.category,
                latitude: stop.latitude, longitude: stop.longitude,
                recommendedStayMinutes: stop.recommendedStayMinutes,
                isOptional: stop.isOptional,
                approachNarration: stop.approachNarration,
                atStopNarration: stop.atStopNarration,
                departureNarration: stop.departureNarration,
                googlePlaceId: stop.googlePlaceId, photoUrl: stop.photoUrl
            )
        }
    }

    private func saveChanges() {
        let updated = tourWithEditedStops()
        TourStorage.shared.save(updated)
        tourVM.savedTours = TourStorage.shared.loadAll()
    }

    private func tourWithEditedStops() -> Tour {
        let json = (try? JSONEncoder().encode(tour)) ?? Data()
        guard var obj = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return tour }
        // Encode the edited stops using the Tour's coding keys
        let stopsData = editableStops.map { stop -> [String: Any] in
            var d: [String: Any] = [
                "id": stop.id,
                "sequence_order": stop.sequenceOrder,
                "name": stop.name,
                "description": stop.description,
                "category": stop.category,
                "latitude": stop.latitude,
                "longitude": stop.longitude,
                "recommended_stay_minutes": stop.recommendedStayMinutes,
                "is_optional": stop.isOptional,
                "approach_narration": stop.approachNarration,
                "at_stop_narration": stop.atStopNarration,
                "departure_narration": stop.departureNarration
            ]
            if let pid = stop.googlePlaceId { d["google_place_id"] = pid }
            if let url = stop.photoUrl { d["photo_url"] = url }
            return d
        }
        obj["stops"] = stopsData
        guard let newData = try? JSONSerialization.data(withJSONObject: obj),
              let newTour = try? JSONDecoder().decode(Tour.self, from: newData) else { return tour }
        return newTour
    }

    // MARK: - Google Maps

    private func openInGoogleMaps() {
        let stops = displayStops
        guard let origin = stops.first, let dest = stops.last else { return }

        let travelMode: String = {
            switch tour.transportMode {
            case "walk": return "walking"
            case "bike": return "bicycling"
            default: return "driving"
            }
        }()

        let originStr = "\(origin.latitude),\(origin.longitude)"
        let destStr = "\(dest.latitude),\(dest.longitude)"
        let waypointsStr = stops.dropFirst().dropLast().map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|")

        // Try Google Maps app first
        var gmURL = "comgooglemaps://?saddr=\(originStr)&daddr=\(destStr)&directionsmode=\(travelMode)"
        if !waypointsStr.isEmpty {
            gmURL += "&waypoints=\(waypointsStr)"
        }
        if let url = URL(string: gmURL), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }

        // Fall back to web
        var webURL = "https://www.google.com/maps/dir/?api=1&origin=\(originStr)&destination=\(destStr)&travelmode=\(travelMode)"
        if !waypointsStr.isEmpty {
            webURL += "&waypoints=\(waypointsStr)"
        }
        if let url = URL(string: webURL) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Regenerate

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

func transportIconFor(_ mode: String?) -> String {
    switch mode {
    case "walk": return "figure.walk"
    case "bike": return "bicycle"
    case "boat": return "ferry.fill"
    case "plane": return "airplane"
    default: return "car.fill"
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

// MARK: - Compact Stop Row (edit mode)

struct CompactStopRow: View {
    let stop: TourStop

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.brandGold)
                    .frame(width: 32, height: 32)
                Text("\(stop.sequenceOrder + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.brandNavy)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name).font(.subheadline.bold()).lineLimit(1)
                if stop.recommendedStayMinutes > 0 {
                    Text("\(stop.recommendedStayMinutes) min stay").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Editable Stop Row (legacy, kept for reference)

struct EditableStopRow: View {
    let stop: TourStop
    let onRemove: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Numbered circle
            ZStack {
                Circle()
                    .fill(Color.brandGold)
                    .frame(width: 30, height: 30)
                Text("\(stop.sequenceOrder + 1)")
                    .font(.caption2.bold())
                    .foregroundStyle(.brandNavy)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name).font(.subheadline.bold()).lineLimit(1)
                Text(stop.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            // Reorder buttons
            VStack(spacing: 4) {
                Button { onMoveUp?() } label: {
                    Image(systemName: "chevron.up.circle.fill")
                        .foregroundStyle(onMoveUp == nil ? Color.gray.opacity(0.3) : .brandGold)
                }
                .disabled(onMoveUp == nil)
                Button { onMoveDown?() } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundStyle(onMoveDown == nil ? Color.gray.opacity(0.3) : .brandGold)
                }
                .disabled(onMoveDown == nil)
            }
            .font(.title3)

            // Remove button
            Button(role: .destructive) { onRemove() } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.3))
        .padding(.horizontal, 4)
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
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color.brandGold)
                        .frame(width: 30, height: 30)
                        .shadow(color: .brandGold.opacity(0.3), radius: 4)
                    Text("\(stop.sequenceOrder + 1)")
                        .font(.caption2.bold())
                        .foregroundStyle(.brandNavy)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.brandGold.opacity(0.3))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
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
                    Button {
                        let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(stop.latitude),\(stop.longitude)")!
                        UIApplication.shared.open(url)
                    } label: {
                        Image(systemName: "map.fill")
                            .font(.caption)
                            .foregroundStyle(.brandGold)
                            .padding(4)
                            .background(Color.brandGold.opacity(0.15), in: Circle())
                    }
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
                    if let photoUrl = stop.photoUrl, let url = URL(string: photoUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color(.systemGray5)
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
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

// MARK: - Add Stop Search Sheet

struct AddStopSearchSheet: View {
    let nearLatitude: Double
    let nearLongitude: Double
    let onAdd: (TourStop) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search for a place, business, or landmark", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit { performSearch() }
                    if !searchText.isEmpty {
                        Button { searchText = ""; searchResults = [] } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                .padding()

                if isSearching {
                    ProgressView().padding()
                }

                // Results
                List(searchResults, id: \.self) { item in
                    Button {
                        addMapItem(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name ?? "Unknown place")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            if let address = item.placemark.title {
                                Text(address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Add Stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Search") { performSearch() }
                        .disabled(searchText.isEmpty)
                }
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.count > 2 {
                    performSearch()
                }
            }
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: nearLatitude, longitude: nearLongitude),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            isSearching = false
            if let error {
                print("[AddStop] Search failed: \(error)")
                return
            }
            searchResults = response?.mapItems ?? []
        }
    }

    private func addMapItem(_ item: MKMapItem) {
        let coord = item.placemark.coordinate
        let name = item.name ?? "New Stop"
        let address = item.placemark.title ?? ""

        let newStop = TourStop(
            id: UUID().uuidString,
            sequenceOrder: 0, // Will be resequenced by caller
            name: name,
            description: address,
            category: categorize(item),
            latitude: coord.latitude,
            longitude: coord.longitude,
            recommendedStayMinutes: 10,
            isOptional: false,
            approachNarration: "Heading to \(name).",
            atStopNarration: "Welcome to \(name).",
            departureNarration: "Let's continue.",
            googlePlaceId: nil,
            photoUrl: nil
        )
        onAdd(newStop)
    }

    private func categorize(_ item: MKMapItem) -> String {
        guard let category = item.pointOfInterestCategory else { return "landmark" }
        switch category {
        case .restaurant, .cafe, .bakery, .brewery, .winery: return "restaurant"
        case .museum: return "museum"
        case .park, .nationalPark, .beach: return "park"
        case .hotel: return "hotel"
        default: return "landmark"
        }
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
