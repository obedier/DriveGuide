import SwiftUI
import MapKit

struct GuidedTourView: View {
    let tour: Tour
    @StateObject private var playback = TourPlaybackService()
    @StateObject private var nav = NavigationService()
    @StateObject private var ferrostarNav = FerrostarNavigationService()
    @StateObject private var routeAware: RouteAwarePlaybackCoordinator
    @AppStorage("navigationEngine") private var navigationEngine = "apple"
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isPreparing = true
    @State private var audioOnly = false
    @State private var use3DMap = false
    @State private var followUser = false
    @State private var mapReady = false
    @State private var showTurnByTurn = false
    @State private var hasPrepared = false

    init(tour: Tour) {
        self.tour = tour
        // Coordinator needs the tour at construction — the playback service is
        // shared so route-aware narration can drive it. The @StateObject holds
        // the coordinator for the lifetime of this view.
        let playback = TourPlaybackService()
        self._playback = StateObject(wrappedValue: playback)
        self._routeAware = StateObject(wrappedValue: RouteAwarePlaybackCoordinator(playback: playback, tour: tour))
    }

    private var isBoatTour: Bool { tour.transportMode == "boat" }
    private var useFerrostar: Bool { navigationEngine == "ferrostar" && !isBoatTour }

    // Unified accessors for whichever navigation engine is active
    private var activeIsNavigating: Bool { useFerrostar ? ferrostarNav.isNavigating : nav.isNavigating }
    private var activeStepInstruction: String { useFerrostar ? ferrostarNav.currentStepInstruction : nav.currentStepInstruction }
    private var activeDistanceToNextStop: CLLocationDistance { useFerrostar ? ferrostarNav.distanceToNextStop : nav.distanceToNextStop }
    private var activeUserLocation: CLLocationCoordinate2D? { useFerrostar ? ferrostarNav.userLocation : nav.userLocation }
    private var activeHeading: CLLocationDirection { useFerrostar ? ferrostarNav.heading : nav.heading }
    private var activeArrivedAtStop: Bool { useFerrostar ? ferrostarNav.arrivedAtStop : nav.arrivedAtStop }

    var body: some View {
        ZStack {
            // Map — boat tours render immediately (WKWebView handles its own loading),
            // other maps delayed until fullScreenCover transition completes to avoid
            // Metal drawable zero-size issue on iPad (CAMetalLayer ignores invalid setDrawableSize)
            if isBoatTour {
                NauticalChartView(stops: tour.stops, currentStopIndex: playback.currentStopIndex)
                    .ignoresSafeArea()
            } else if !mapReady {
                Color.black.ignoresSafeArea()
                ProgressView()
                    .tint(.brandGold)
                    .scaleEffect(1.5)
            } else if useFerrostar && showTurnByTurn {
                // Ferrostar turn-by-turn as the map layer (controls overlay on top via the VStack below)
                FerrostarTurnByTurnView(
                    stops: tour.stops,
                    transportMode: tour.transportMode ?? "car",
                    onExit: {
                        showTurnByTurn = false
                    }
                )
                .ignoresSafeArea()
            } else if useFerrostar {
                MapLibreNavigationView(
                    routeCoordinates: ferrostarNav.routeCoordinates,
                    stops: tour.stops,
                    currentStopIndex: playback.currentStopIndex,
                    followUser: followUser,
                    heading: ferrostarNav.heading,
                    use3DMap: use3DMap,
                    isNavigating: ferrostarNav.isNavigating,
                    userLocation: ferrostarNav.userLocation
                )
                .ignoresSafeArea()
            } else {
                let _ = print("[GuidedTour] RENDERING Apple Maps")
                Map(position: $cameraPosition) {
                    // User location
                    UserAnnotation()

                    // Route polylines
                    ForEach(Array(nav.routePolylines.enumerated()), id: \.offset) { _, polyline in
                        MapPolyline(polyline)
                            .stroke(.brandGold, lineWidth: 5)
                    }

                    // Stop markers
                    ForEach(tour.stops) { stop in
                        let idx = tour.stops.firstIndex(where: { $0.id == stop.id }) ?? 0
                        let isCurrent = idx == playback.currentStopIndex
                        let isVisited = idx < playback.currentStopIndex

                        Annotation(stop.name, coordinate: CLLocationCoordinate2D(
                            latitude: stop.latitude, longitude: stop.longitude
                        )) {
                            ZStack {
                                Circle()
                                    .fill(isCurrent ? Color.brandGold : isVisited ? .green : Color.brandGold.opacity(0.7))
                                    .frame(width: 36, height: 36)
                                    .shadow(color: isCurrent ? .brandGold.opacity(0.5) : .clear, radius: 8)
                                if isCurrent {
                                    Circle()
                                        .stroke(Color.brandGold, lineWidth: 3)
                                        .frame(width: 44, height: 44)
                                }
                                Text("\(stop.sequenceOrder + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
                .mapStyle(use3DMap ? .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .including([.museum, .park, .restaurant, .hotel]), showsTraffic: false) : .standard(elevation: .realistic))
                .mapControls { MapUserLocationButton() }
                .ignoresSafeArea()
            }

            if showTurnByTurn {
                // Compact overlay for turn-by-turn mode — Ferrostar handles nav UI, we handle audio
                VStack {
                    // Exit button
                    HStack {
                        Button { stopAndDismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .padding(.leading)
                        .padding(.top, 8)
                        Spacer()
                    }

                    // 2.16: Bridge / drive-to banner.
                    if let bridge = playback.bridgeState {
                        BridgeStatusBanner(state: bridge)
                            .padding(.horizontal)
                            .padding(.top, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer()

                    // Audio player
                    if playback.isActive {
                        AudioOnlyCard(playback: playback) { stopAndDismiss() }
                    }
                }
            } else {
                VStack(spacing: 0) {
                    // Turn instruction banner
                    if activeIsNavigating && !activeStepInstruction.isEmpty && !isPreparing {
                        turnInstructionBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Top controls bar
                    topControlsBar

                    Spacer()

                    // Bottom card
                    if isPreparing {
                        PreparingAudioCard(progress: playback.audioProgress)
                    } else if audioOnly && playback.isActive {
                        AudioOnlyCard(playback: playback) { stopAndDismiss() }
                    } else {
                        TourControlCard(
                            playback: playback,
                            tour: tour,
                            onStartNavigation: {
                                if useFerrostar {
                                    ferrostarNav.startNavigation(targetStopIndex: 0)
                                    showTurnByTurn = true
                                    // 2.16: Use awareness variant so far-from-first-stop
                                    // tours get a dynamic "drive-to" intro instead of
                                    // immediately playing segment 0.
                                    playback.startTourWithAwareness(userLocation: activeUserLocation)
                                    // 2.11: Arrivals auto-trigger the matching narration segment.
                                    routeAware.attach(ferrostarNav)
                                } else {
                                    nav.startNavigation(targetStopIndex: 0)
                                    withAnimation { followUser = true; use3DMap = true }
                                }
                            },
                            onStop: { stopAndDismiss() }
                        )
                    }
                }
            }
        }
        .task {
            guard !hasPrepared else { return }
            hasPrepared = true
            // Audio first — for pre-generated tours this is near-instant because
            // every segment already has an audio_url from the server. The map
            // route can continue computing in the background without blocking
            // the "ready to start" UI.
            await playback.prepareTour(tour)
            isPreparing = false
            // Route calc continues in background so the map populates while
            // the user reads the ready-to-start card.
            Task {
                if useFerrostar {
                    await ferrostarNav.calculateRoutes(for: tour.stops, transportMode: tour.transportMode ?? "car")
                } else {
                    await nav.calculateRoutes(for: tour.stops, transportMode: tour.transportMode ?? "car")
                }
            }
        }
        // 2.16: Feed user location into the playback coordinator so the
        // bridge narration knows when to hand off to the pre-gen segment 0.
        .onChange(of: ferrostarNav.userLocation?.latitude) { _, _ in
            if let loc = ferrostarNav.userLocation { playback.observeLocation(loc) }
        }
        .onChange(of: nav.userLocation?.latitude) { _, _ in
            if let loc = nav.userLocation { playback.observeLocation(loc) }
        }
        .onChange(of: playback.currentStopIndex) { _, newIdx in
            guard !isBoatTour, newIdx >= 0, newIdx < tour.stops.count else { return }
            let stop = tour.stops[newIdx]

            if useFerrostar {
                // MapLibre/Ferrostar handles its own camera — no action needed
            } else if !followUser {
                withAnimation(.easeInOut(duration: 1.0)) {
                    if use3DMap {
                        cameraPosition = .camera(MapCamera(
                            centerCoordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude),
                            distance: 800, heading: activeHeading, pitch: 60
                        ))
                    } else {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude),
                            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                        ))
                    }
                }
            }
        }
        .onChange(of: activeUserLocation?.latitude) { _, _ in
            guard !useFerrostar else { return } // MapLibre handles camera following internally
            if followUser, let loc = activeUserLocation {
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .camera(MapCamera(
                        centerCoordinate: loc,
                        distance: 1000, heading: activeHeading, pitch: use3DMap ? 60 : 0
                    ))
                }
            }
        }
        .onChange(of: activeArrivedAtStop) { _, arrived in
            if arrived && playback.isActive {
                // Auto-advance narration when arriving at stop
                if useFerrostar {
                    ferrostarNav.advanceToNextStop()
                } else {
                    nav.advanceToNextStop()
                }
            }
        }
        .onAppear {
            guard !mapReady else { return } // Only run once
            print("[GuidedTour] onAppear — isBoatTour=\(isBoatTour), useFerrostar=\(useFerrostar), navigationEngine=\(navigationEngine)")
            print("[GuidedTour] stops=\(tour.stops.count), transportMode=\(tour.transportMode ?? "nil")")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                print("[GuidedTour] Setting mapReady=true")
                mapReady = true
            }
        }
        .onDisappear {
            ferrostarNav.stopNavigation()
            nav.stopNavigation()
            mapReady = false
        }
        .statusBarHidden()
    }

    // MARK: - Turn Instruction Banner

    private var turnInstructionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: turnIcon(for: activeStepInstruction))
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(activeStepInstruction)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if activeDistanceToNextStop > 0 {
                    let stopName = tour.stops[safe: activeIsNavigating ? playback.currentStopIndex + 1 : 0]?.name ?? "next stop"
                    Text("\(formatDistance(activeDistanceToNextStop)) to \(stopName)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.brandNavy.opacity(0.95))
        .padding(.top, 4)
    }

    // MARK: - Top Controls Bar

    private var topControlsBar: some View {
        HStack {
            Button { stopAndDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.4))
            }

            Spacer()

            if playback.isSimulating {
                Label("SIMULATION", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange, in: Capsule())
                    .foregroundStyle(.white)
            } else if activeIsNavigating {
                Label("NAVIGATING", systemImage: "location.fill")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green, in: Capsule())
                    .foregroundStyle(.white)
            }

            Spacer()

            HStack(spacing: 12) {
                // Follow user toggle
                if !isBoatTour {
                    Button { withAnimation { followUser.toggle() } } label: {
                        Image(systemName: followUser ? "location.fill" : "location")
                            .font(.caption)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay { if followUser { Circle().fill(Color.brandGold.opacity(0.3)) } }
                            .foregroundStyle(followUser ? .brandGold : .primary)
                    }
                }

                Button { withAnimation { audioOnly.toggle() } } label: {
                    Image(systemName: audioOnly ? "text.bubble" : "speaker.wave.2.fill")
                        .font(.caption)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }

                if !isBoatTour {
                    Button { withAnimation { use3DMap.toggle() } } label: {
                        Image(systemName: use3DMap ? "map" : "view.3d")
                            .font(.caption)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }

                if playback.isActive {
                    Text("\(playback.audioPlayer.currentSegmentIndex + 1)/\(max(playback.audioPlayer.totalSegments, 1))")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func stopAndDismiss() {
        playback.stopTour()
        if useFerrostar {
            ferrostarNav.stopNavigation()
        } else {
            nav.stopNavigation()
        }
        dismiss()
    }

    private func turnIcon(for instruction: String) -> String {
        let lower = instruction.lowercased()
        if lower.contains("left") { return "arrow.turn.up.left" }
        if lower.contains("right") { return "arrow.turn.up.right" }
        if lower.contains("u-turn") { return "arrow.uturn.left" }
        if lower.contains("merge") { return "arrow.merge" }
        if lower.contains("arriv") { return "mappin.circle.fill" }
        if lower.contains("straight") || lower.contains("continue") { return "arrow.up" }
        return "arrow.up"
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        let feet = meters * 3.281
        if feet < 500 { return "\(Int(feet)) ft" }
        let miles = meters / 1609.34
        return String(format: "%.1f mi", miles)
    }
}

// Safe subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preparing Card

struct PreparingAudioCard: View {
    let progress: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.brandGold)
            Text(progress.isEmpty ? "Preparing your guided tour..." : progress)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }
}

// MARK: - Audio Only (minimal)

struct AudioOnlyCard: View {
    @ObservedObject var playback: TourPlaybackService
    let onStop: () -> Void
    @State private var showSegmentList = false

    private var total: Int { playback.audioPlayer.totalSegments }
    private var current: Int { playback.audioPlayer.currentSegmentIndex }

    var body: some View {
        VStack(spacing: 10) {
            // Header row — segment title + counter + photo thumb
            HStack(spacing: 10) {
                if let stop = playback.currentStop, let photoUrl = stop.photoUrl, let url = URL(string: photoUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(.systemGray5)
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.segmentLabel)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(current + 1) of \(total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                // Expand into full segment list
                Button { showSegmentList = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.subheadline)
                        .foregroundStyle(.brandGold)
                        .frame(width: 36, height: 36)
                        .background(Color.brandGold.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Show all segments")
            }

            // Playback progress
            ProgressView(value: Double(current + 1), total: Double(max(total, 1)))
                .tint(.brandGold)

            // Transport controls
            HStack(spacing: 20) {
                Button { playback.previousSegment() } label: {
                    Image(systemName: "backward.fill").font(.title3)
                }
                .disabled(current == 0)

                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.brandGold)
                }

                Button { playback.nextSegment() } label: {
                    Image(systemName: "forward.fill").font(.title3)
                }
                .disabled(current >= total - 1)

                Spacer()

                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            }
            .foregroundStyle(.primary)
        }
        .padding(14)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
        .sheet(isPresented: $showSegmentList) {
            SegmentListSheet(playback: playback)
                .presentationDetents([.medium, .large])
        }
    }
}

/// Scrollable list of all segments with a tap-to-skip affordance. Surfaced
/// from the in-tour player's ⋯ button so the user can see where they are in
/// the arc and jump to a specific stop without scrubbing through audio.
struct SegmentListSheet: View {
    @ObservedObject var playback: TourPlaybackService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<playback.audioPlayer.totalSegments, id: \.self) { index in
                    let segment = playback.audioPlayer.segments.first(where: { $0.sequenceOrder == index })
                    let isCurrent = index == playback.audioPlayer.currentSegmentIndex
                    let isPast = index < playback.audioPlayer.currentSegmentIndex

                    Button {
                        playback.audioPlayer.playSegment(at: index)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(isCurrent ? Color.brandGold : isPast ? Color.green.opacity(0.5) : Color.brandGold.opacity(0.15))
                                    .frame(width: 28, height: 28)
                                if isPast {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                } else {
                                    Text("\(index + 1)")
                                        .font(.caption.bold())
                                        .foregroundStyle(isCurrent ? .brandNavy : .brandGold)
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(segmentLabel(for: index))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if let seg = segment {
                                    Text(seg.narrationText.prefix(80) + (seg.narrationText.count > 80 ? "…" : ""))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }

                            Spacer()

                            if isCurrent && playback.audioPlayer.isPlaying {
                                Image(systemName: "waveform")
                                    .foregroundStyle(.brandGold)
                                    .symbolEffect(.variableColor.iterative)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(isCurrent ? Color.brandGold.opacity(0.1) : Color.clear)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Tour Segments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func segmentLabel(for index: Int) -> String {
        guard let segment = playback.audioPlayer.segments.first(where: { $0.sequenceOrder == index }) else {
            return "Segment \(index + 1)"
        }
        switch segment.segmentType {
        case "intro": return "Welcome"
        case "outro": return "Tour Complete"
        case "between_stops": return "On the road"
        default:
            // at_stop / approach / departure — show the stop name
            if let stopId = segment.toStopId,
               let stop = playback.currentTour?.stops.first(where: { $0.id == stopId }) {
                let prefix: String = {
                    switch segment.segmentType {
                    case "approach": return "Approaching "
                    case "departure": return "Departing "
                    default: return ""
                    }
                }()
                return "\(prefix)\(stop.name)"
            }
            return segment.segmentType.capitalized
        }
    }
}

// MARK: - Main Tour Control Card

struct TourControlCard: View {
    @ObservedObject var playback: TourPlaybackService
    let tour: Tour
    let onStartNavigation: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Segment label with stop number
            HStack {
                if playback.isActive {
                    Text(playback.segmentLabel.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(.brandGold)
                    Spacer()
                    Text("\(playback.audioPlayer.currentSegmentIndex + 1) of \(playback.audioPlayer.totalSegments)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("READY TO START")
                        .font(.caption.bold())
                        .foregroundStyle(.brandGold)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            if playback.isActive {
                // Photo
                if let stop = playback.currentStop, let photoUrl = stop.photoUrl, let url = URL(string: photoUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(.systemGray5)
                    }
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }

                // Narration text
                ScrollView {
                    Text(playback.currentNarrationText)
                        .font(.callout)
                        .lineSpacing(5)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                }
                .frame(maxHeight: 140)

                // Scrubbing timeline
                if playback.audioPlayer.hasAudio {
                    Slider(
                        value: Binding(
                            get: { playback.audioPlayer.playbackProgress },
                            set: { playback.audioPlayer.seek(to: $0) }
                        ),
                        in: 0...1
                    )
                    .tint(.brandGold)
                    .padding(.horizontal, 20)
                }

                // Playback controls
                HStack(spacing: 24) {
                    Button { playback.previousSegment() } label: {
                        Image(systemName: "backward.fill").font(.title3)
                    }
                    .disabled(playback.audioPlayer.currentSegmentIndex == 0)

                    Button { playback.togglePlayPause() } label: {
                        Image(systemName: playback.audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.brandGold)
                    }

                    Button { playback.nextSegment() } label: {
                        Image(systemName: "forward.fill").font(.title3)
                    }
                    .disabled(playback.audioPlayer.currentSegmentIndex >= playback.audioPlayer.totalSegments - 1)
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 10)

                Button(action: onStop) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("End Tour")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            } else {
                // Not started
                Text(tour.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Text("\(tour.stops.count) stops \u{2022} \(formatDuration(tour.durationMinutes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                if !playback.audioReady && !playback.audioProgress.isEmpty {
                    Text(playback.audioProgress)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                }

                // Start buttons
                HStack(spacing: 12) {
                    Button {
                        playback.startSimulation()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Simulate")
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button {
                        onStartNavigation()
                        playback.startTour()
                    } label: {
                        HStack {
                            Image(systemName: "location.fill")
                            Text("Navigate")
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandGold)
                }
                .padding(.horizontal, 16)

                // Close — dismiss without starting. The top-left xmark icon
                // does the same thing but it's easy to miss on the busy map.
                Button(action: onStop) {
                    Text("Close").font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("closeTourReadyButton")

                // Voice picker
                Menu {
                    Button {
                        playback.switchVoice(engine: "google", quality: "premium")
                    } label: {
                        Label("Gary (Google Premium)", systemImage: playback.voiceEngine == "google" ? "checkmark" : "")
                    }
                    Button {
                        playback.switchVoice(engine: "kokoro", quality: "premium")
                    } label: {
                        Label("Kim (Kokoro)", systemImage: playback.voiceEngine == "kokoro" ? "checkmark" : "")
                    }
                } label: {
                    HStack {
                        Image(systemName: "person.wave.2")
                        Text("Guide: \(playback.voiceEngine == "kokoro" ? "Kim" : "Gary")")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.brandGold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.brandGold.opacity(0.1), in: Capsule())
                }
                .padding(.bottom, 14)
            }
        }
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
}

/// Banner shown during the "drive-to" phase — when the user started a tour
/// far from the first stop and the app is playing a dynamic bridge narration
/// to fill the travel time. Switches off the moment they're close enough for
/// segment 0 to take over.
struct BridgeStatusBanner: View {
    let state: TourPlaybackService.BridgeState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.isPlaying ? "waveform" : "car.fill")
                .foregroundStyle(.brandGold)
                .font(.title3)
                .symbolEffect(.variableColor.iterative, isActive: state.isPlaying)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.isPlaying ? "Warming up…" : "Heading to \(state.firstStopName)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(formatDistance(km: state.distanceKm)) · ~\(state.etaMinutes) min · tour begins when you arrive")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.brandGold.opacity(0.5), lineWidth: 1)
        )
    }

    private func formatDistance(km: Double) -> String {
        let miles = km * 0.621371
        if miles >= 1 {
            return String(format: "%.1f mi away", miles)
        } else {
            let feet = Int(miles * 5280)
            return "\(feet) ft away"
        }
    }
}
