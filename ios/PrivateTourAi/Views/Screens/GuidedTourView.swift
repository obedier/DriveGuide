import SwiftUI
import MapKit

struct GuidedTourView: View {
    let tour: Tour
    @StateObject private var playback = TourPlaybackService()
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isPreparing = true
    @State private var audioOnly = false
    @State private var use3DMap = false

    private var isBoatTour: Bool { tour.transportMode == "boat" }

    var body: some View {
        ZStack {
            // Map — nautical chart for boat tours, Apple Maps for everything else
            if isBoatTour {
                NauticalChartView(stops: tour.stops, currentStopIndex: playback.currentStopIndex)
                    .ignoresSafeArea()
            } else {
                Map(position: $cameraPosition) {
                    ForEach(tour.stops) { stop in
                        let idx = tour.stops.firstIndex(where: { $0.id == stop.id }) ?? 0
                        let isCurrent = idx == playback.currentStopIndex
                        let isVisited = idx < playback.currentStopIndex

                        Annotation(stop.name, coordinate: CLLocationCoordinate2D(
                            latitude: stop.latitude, longitude: stop.longitude
                        )) {
                            ZStack {
                                Circle()
                                    .fill(isCurrent ? Color("AccentCoral") : isVisited ? .green : Color(.systemGray4))
                                    .frame(width: 36, height: 36)
                                if isCurrent {
                                    Circle()
                                        .stroke(Color("AccentCoral"), lineWidth: 3)
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
                .ignoresSafeArea()
            }

            VStack {
                // Top bar
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
                    }

                    Spacer()

                    HStack(spacing: 12) {
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

                Spacer()

                // Bottom card
                if isPreparing {
                    PreparingAudioCard(progress: playback.audioProgress)
                } else if audioOnly && playback.isActive {
                    AudioOnlyCard(playback: playback) { stopAndDismiss() }
                } else {
                    TourControlCard(playback: playback, tour: tour) { stopAndDismiss() }
                }
            }
        }
        .task {
            await playback.prepareTour(tour)
            isPreparing = false
        }
        .onChange(of: playback.currentStopIndex) { _, newIdx in
            guard !isBoatTour, newIdx >= 0, newIdx < tour.stops.count else { return }
            let stop = tour.stops[newIdx]
            withAnimation(.easeInOut(duration: 1.0)) {
                if use3DMap {
                    cameraPosition = .camera(MapCamera(
                        centerCoordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude),
                        distance: 800, heading: 0, pitch: 60
                    ))
                } else {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude),
                        span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                    ))
                }
            }
        }
        .statusBarHidden()
    }

    private func stopAndDismiss() {
        playback.stopTour()
        dismiss()
    }
}

// MARK: - Preparing Card

struct PreparingAudioCard: View {
    let progress: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color("AccentCoral"))
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
                .foregroundStyle(Color("AccentCoral"))

            HStack(spacing: 20) {
                Button { playback.previousSegment() } label: {
                    Image(systemName: "backward.fill").font(.title3)
                }
                .disabled(playback.audioPlayer.currentSegmentIndex == 0)

                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color("AccentCoral"))
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
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Segment label
            Text(playback.isActive ? playback.segmentLabel.uppercased() : "READY TO START")
                .font(.caption.bold())
                .foregroundStyle(Color("AccentCoral"))
                .padding(.top, 16)
                .padding(.bottom, 4)

            if playback.isActive {
                // Active tour: show photo, narration, controls

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

                // Progress bar
                if playback.audioPlayer.hasAudio {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color(.systemGray5))
                            Rectangle().fill(Color("AccentCoral"))
                                .frame(width: geo.size.width * playback.audioPlayer.playbackProgress)
                        }
                    }
                    .frame(height: 3)
                    .clipShape(Capsule())
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
                            .foregroundStyle(Color("AccentCoral"))
                    }

                    Button { playback.nextSegment() } label: {
                        Image(systemName: "forward.fill").font(.title3)
                    }
                    .disabled(playback.audioPlayer.currentSegmentIndex >= playback.audioPlayer.totalSegments - 1)
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 10)

                // End Tour button
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
                // Not started: show tour summary and start buttons

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
                            Text("Simulate Tour")
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button {
                        playback.startTour()
                    } label: {
                        HStack {
                            Image(systemName: "location.fill")
                            Text("Start Live")
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("AccentCoral"))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
}
