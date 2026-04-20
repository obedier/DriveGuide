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
    @StateObject private var downloader = TourDownloader()
    @State private var isOfflineAvailable = false
    @AppStorage("voiceEngine") private var voiceEngine: String = "google"
    @AppStorage("voiceQuality") private var voiceQuality: String = "premium"
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
                        if tour.isFeatured {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles").font(.caption2)
                                Text("wAIpoint Featured").font(.caption2.bold()).tracking(0.6)
                            }
                            .foregroundStyle(.brandNavy)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(
                                LinearGradient(colors: [.brandGold, Color(red: 0.96, green: 0.85, blue: 0.55)],
                                               startPoint: .leading, endPoint: .trailing),
                                in: Capsule()
                            )
                        }

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

                            // Offline download — keeps tours playable with no network
                            OfflineDownloadRow(
                                tour: tour,
                                downloader: downloader,
                                isAvailable: $isOfflineAvailable,
                                voiceEngine: voiceEngine,
                                voicePreference: voiceQuality
                            )

                            // "Make it your own" — only for tours the user doesn't own
                            // (e.g., featured public tours opened from Community).
                            // Clones the tour into their library for editing.
                            if !tourVM.isOwnedByCurrentUser(tour) {
                                Button {
                                    tourVM.cloneTourForEditing(tour)
                                } label: {
                                    HStack {
                                        Image(systemName: "square.and.pencil")
                                        Text("Make it your own")
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.brandGold.opacity(0.85))
                                .accessibilityIdentifier("makeItYourOwnButton")
                                .accessibilityHint("Create an editable copy of this tour in your library")
                            } else {
                                // Community visibility — opt-in. Manual moderation for v1.
                                PublicVisibilityToggle(tour: tour)
                            }

                            // Passenger Mode + Share — share opens the system sheet with
                            // a /tour/<shareId> link, Passenger opens the simplified UI.
                            HStack(spacing: 10) {
                                Button {
                                    tourVM.pendingPassengerTour = tour
                                } label: {
                                    HStack {
                                        Image(systemName: "person.2.fill")
                                        Text("Passenger Mode")
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                }
                                .buttonStyle(.bordered)
                                .tint(.brandGold)

                                if let url = tourVM.shareTourById(tour) {
                                    ShareLink(item: url, subject: Text(tour.title)) {
                                        HStack {
                                            Image(systemName: "square.and.arrow.up")
                                            Text("Share")
                                        }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.brandGold)
                                }
                            }
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

                    // Stops list header (Edit/Add are in toolbar for easier hit target)
                    HStack(spacing: 8) {
                        Text("YOUR STOPS")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        if isEditing {
                            Text("· EDITING")
                                .font(.caption.bold())
                                .foregroundStyle(.brandGold)
                        }
                        Spacer()
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
                    ShareLink(
                        item: shareText(),
                        preview: SharePreview(tour.title, image: Image(systemName: "map.fill"))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.brandGold)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        // Add stop — in toolbar so it's always easy to hit
                        Button { showAddStopSheet = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.brandGold)
                        }
                        // Edit stops
                        Button { withAnimation { isEditing.toggle() } } label: {
                            Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.brandGold)
                        }
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .onAppear {
            // Always use the freshest tour stops from VM (in case it was updated elsewhere)
            let latest = tourVM.savedTours.first(where: { $0.id == tour.id })
                ?? tourVM.archivedTours.first(where: { $0.id == tour.id })
                ?? tour
            editableStops = latest.stops
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

    // MARK: - Share

    /// Builds a shareable text string. If a shareId exists, includes a public link.
    /// Works with Messages, Mail, Twitter, any app accepting text.
    private func shareText() -> String {
        var lines = [
            "🗺️ \(tour.title)",
            "",
            tour.description,
            "",
            "\(displayStops.count) stops · \(formatDuration(tour.durationMinutes))"
        ]
        if let shareId = tour.shareId {
            lines.append("")
            lines.append("Open in wAIpoint: https://waipoint.o11r.com/tour/\(shareId)")
        } else {
            lines.append("")
            lines.append("Created with wAIpoint — your AI-powered driving guide")
        }
        return lines.joined(separator: "\n")
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
        VStack(spacing: 8) {
            ForEach(Array(displayStops.enumerated()), id: \.element.id) { idx, stop in
                HStack(spacing: 10) {
                    // Persistent red minus button to delete
                    Button {
                        removeStop(at: idx)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)

                    CompactStopRow(stop: stop)
                        .frame(maxWidth: .infinity)

                    // Move up / down buttons (reliable on iPhone)
                    VStack(spacing: 2) {
                        Button {
                            moveStop(from: idx, to: idx - 1)
                        } label: {
                            Image(systemName: "chevron.up.circle.fill")
                                .font(.title3)
                                .foregroundStyle(idx > 0 ? .brandGold : Color.gray.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                        .disabled(idx == 0)

                        Button {
                            moveStop(from: idx, to: idx + 1)
                        } label: {
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.title3)
                                .foregroundStyle(idx < displayStops.count - 1 ? .brandGold : Color.gray.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                        .disabled(idx == displayStops.count - 1)
                    }
                }
                .padding(.horizontal, 16)
            }

            // Helpful hint
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").font(.caption2)
                Text("Tap ○− to remove · Tap ▲ / ▼ to reorder")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Stop Editing

    /// Ensure `editableStops` is populated before any mutation.
    private func ensureStopsLoaded() {
        if editableStops.isEmpty && !tour.stops.isEmpty {
            editableStops = tour.stops
        }
    }

    private func moveStop(from: Int, to: Int) {
        ensureStopsLoaded()
        guard from >= 0 && from < editableStops.count,
              to >= 0 && to < editableStops.count else { return }
        let stop = editableStops.remove(at: from)
        editableStops.insert(stop, at: to)
        resequenceStops()
        saveChanges()
    }

    private func removeStop(at idx: Int) {
        ensureStopsLoaded()
        guard idx >= 0 && idx < editableStops.count else { return }
        editableStops.remove(at: idx)
        resequenceStops()
        saveChanges()
    }

    private func insertStop(_ stop: TourStop, at idx: Int) {
        ensureStopsLoaded()
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
        tourVM.archivedTours = TourStorage.shared.loadArchived()
        // Keep current tour reference fresh so reopen shows updated data
        if tourVM.currentTour?.id == tour.id {
            tourVM.currentTour = updated
        }
        // Push to cloud so other devices see the change
        Task { try? await APIClient.shared.syncTourToCloud(updated) }
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

/// Opt-in public-visibility toggle. When the user flips it on, the tour joins
/// the community library (manual moderation per v1). Can be flipped off any
/// time; the server deletes the public listing but keeps the personal copy.
///
/// Binding pattern: the toggle is bound directly to `$isPublic` (optimistic
/// update) and `.onChange` fires the API call. On failure we revert `isPublic`
/// and surface an inline error. Previously the toggle used a computed Binding
/// whose setter only kicked off a Task — SwiftUI re-read `get` before the
/// Task updated state, snapping the switch back off.
struct PublicVisibilityToggle: View {
    let tour: Tour
    @EnvironmentObject var tourVM: TourViewModel
    @State private var isPublic: Bool
    @State private var isSyncing = false
    @State private var inlineError: String?
    /// Guards the `.onChange` handler so programmatic reverts don't re-fire
    /// the API call and loop.
    @State private var suppressOnChange = false

    init(tour: Tour) {
        self.tour = tour
        self._isPublic = State(initialValue: tour.isPublic)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: isPublic ? "globe" : "lock.fill")
                    .foregroundStyle(isPublic ? .brandGold : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isPublic ? "Visible in Community" : "Private to you")
                        .font(.subheadline).fontWeight(.semibold)
                    Text(isPublic
                         ? "Other travelers can browse and play this tour."
                         : "Flip on to share with the wAIpoint community.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isSyncing {
                    ProgressView().tint(.brandGold)
                }
                Toggle("", isOn: $isPublic)
                    .toggleStyle(.switch).tint(.brandGold).labelsHidden()
                    .disabled(isSyncing)
                    .accessibilityIdentifier("publicVisibilityToggle")
            }
            if let err = inlineError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(err).font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: isPublic) { oldValue, newValue in
            guard !suppressOnChange, oldValue != newValue else { return }
            Task { await sync(newValue: newValue, previousValue: oldValue) }
        }
    }

    /// Apply visibility change against the backend. Falls back to the
    /// already-deployed publish/unpublish endpoints if the newer /visibility
    /// endpoint isn't live yet. Reverts the UI on failure.
    @MainActor
    private func sync(newValue: Bool, previousValue: Bool) async {
        isSyncing = true
        inlineError = nil
        defer { isSyncing = false }

        do {
            try await applyVisibility(isPublic: newValue)
        } catch {
            // Revert the toggle without re-triggering .onChange.
            suppressOnChange = true
            isPublic = previousValue
            suppressOnChange = false
            inlineError = friendlyError(error)
            print("[VisibilityToggle] sync failed: \(error)")
        }
    }

    private func applyVisibility(isPublic: Bool) async throws {
        do {
            try await APIClient.shared.setTourVisibility(tourId: tour.id, isPublic: isPublic)
            return
        } catch {
            // Newer endpoint may not be deployed yet — fall through to the
            // older publishTour / unpublishTour endpoints which are live.
            print("[VisibilityToggle] /visibility unavailable, falling back: \(error)")
        }
        if isPublic {
            try await APIClient.shared.publishTour(tour: tour)
        } else {
            try await APIClient.shared.unpublishTour(tourId: tour.id)
        }
    }

    private func friendlyError(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized: return "Sign in to change visibility."
            case .networkError: return "No network — try again."
            default: return "Could not update visibility. Try again."
            }
        }
        return "Could not update visibility. Try again."
    }
}

/// Unified download / downloading / downloaded row shown on TourDetailView.
/// Three states: idle (show Download button), downloading (progress + cancel),
/// downloaded (check mark + size + remove option).
struct OfflineDownloadRow: View {
    let tour: Tour
    @ObservedObject var downloader: TourDownloader
    @Binding var isAvailable: Bool
    let voiceEngine: String
    let voicePreference: String

    @State private var totalSizeBytes: Int64 = 0

    var body: some View {
        Group {
            if downloader.isDownloading {
                downloadingState
            } else if isAvailable {
                downloadedState
            } else {
                idleState
            }
        }
        .task { await refreshState() }
    }

    private var idleState: some View {
        Button {
            downloader.download(
                tour: tour,
                voiceEngine: voiceEngine,
                voicePreference: voicePreference,
                onComplete: {
                    Task { await refreshState() }
                }
            )
        } label: {
            HStack {
                Image(systemName: "arrow.down.circle")
                Text("Download for offline")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(.brandGold)
        .accessibilityIdentifier("downloadForOfflineButton")
    }

    private var downloadingState: some View {
        VStack(spacing: 8) {
            ProgressView(value: downloader.progress)
                .tint(.brandGold)
            HStack {
                Text("Downloading \(Int(downloader.progress * 100))%")
                    .font(.caption)
                Spacer()
                Button("Cancel") { downloader.cancel() }
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 8)
    }

    private var downloadedState: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Available offline").font(.subheadline).fontWeight(.semibold)
                if totalSizeBytes > 0 {
                    Text(formatBytes(totalSizeBytes))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button(role: .destructive) {
                    Task { await removeOffline() }
                } label: {
                    Label("Remove download", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func refreshState() async {
        let downloaded = await OfflineTourStore.shared.isDownloaded(tourId: tour.id)
        isAvailable = downloaded
        if downloaded, let manifest = try? await OfflineTourStore.shared.manifest(for: tour.id) {
            totalSizeBytes = manifest.totalBytes
        } else {
            totalSizeBytes = 0
        }
    }

    private func removeOffline() async {
        try? await OfflineTourStore.shared.delete(tourId: tour.id)
        await refreshState()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useKB]
        return formatter.string(fromByteCount: bytes)
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
