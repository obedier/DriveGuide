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
                                    playback.startTour()
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
            // Calculate routes and prepare audio in parallel
            if useFerrostar {
                async let routeCalc: () = ferrostarNav.calculateRoutes(for: tour.stops, transportMode: tour.transportMode ?? "car")
                async let audioPrepare: () = playback.prepareTour(tour)
                _ = await (routeCalc, audioPrepare)
            } else {
                async let routeCalc: () = nav.calculateRoutes(for: tour.stops, transportMode: tour.transportMode ?? "car")
                async let audioPrepare: () = playback.prepareTour(tour)
                _ = await (routeCalc, audioPrepare)
            }
            isPreparing = false
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

    var body: some View {
        VStack(spacing: 8) {
            Text(playback.segmentLabel)
                .font(.caption.bold())
                .foregroundStyle(.brandGold)

            HStack(spacing: 20) {
                Button { playback.previousSegment() } label: {
                    Image(systemName: "backward.fill").font(.title3)
                }
                .disabled(playback.audioPlayer.currentSegmentIndex == 0)

                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.brandGold)
                }

                Button { playback.nextSegment() } label: {
                    Image(systemName: "forward.fill").font(.title3)
                }
                .disabled(playback.audioPlayer.currentSegmentIndex >= playback.audioPlayer.totalSegments - 1)

                Spacer()

                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            }
            .foregroundStyle(.primary)
        }
        .padding(16)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
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
