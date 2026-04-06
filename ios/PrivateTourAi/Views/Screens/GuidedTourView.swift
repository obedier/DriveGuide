import SwiftUI
import MapKit

struct GuidedTourView: View {
    let tour: Tour
    @StateObject private var playback = TourPlaybackService()
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isPreparing = true

    var body: some View {
        ZStack {
            // Map showing current position along route
            Map(position: $cameraPosition) {
                ForEach(tour.stops) { stop in
                    let isCurrent = tour.stops.firstIndex(where: { $0.id == stop.id }) == playback.currentStopIndex
                    let isVisited = (tour.stops.firstIndex(where: { $0.id == stop.id }) ?? 999) < playback.currentStopIndex

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
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()

            VStack {
                // Top bar
                HStack {
                    Button { stopAndDismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                    Spacer()
                    if playback.isSimulating {
                        Label("SIMULATION", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.orange, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    // Segment counter
                    Text("\(playback.audioPlayer.currentSegmentIndex + 1)/\(playback.audioPlayer.totalSegments)")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding()

                Spacer()

                // Narration card
                if isPreparing {
                    PreparingAudioCard(progress: playback.audioProgress)
                } else {
                    NarrationPlaybackCard(playback: playback)
                }
            }
        }
        .task {
            await playback.prepareTour(tour)
            isPreparing = false
        }
        .onChange(of: playback.currentStopIndex) { _, newIdx in
            if newIdx >= 0, newIdx < tour.stops.count {
                let stop = tour.stops[newIdx]
                withAnimation(.easeInOut(duration: 0.6)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude),
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }
        }
    }

    private func stopAndDismiss() {
        playback.stopTour()
        dismiss()
    }
}

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

struct NarrationPlaybackCard: View {
    @ObservedObject var playback: TourPlaybackService

    var body: some View {
        VStack(spacing: 0) {
            // Segment type label
            Text(playback.segmentLabel.uppercased())
                .font(.caption.bold())
                .foregroundStyle(Color("AccentCoral"))
                .padding(.top, 16)
                .padding(.bottom, 4)

            // Narration text (scrollable)
            ScrollView {
                Text(playback.currentNarrationText)
                    .font(.callout)
                    .lineSpacing(5)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .frame(maxHeight: 200)

            // Progress bar
            if playback.audioPlayer.hasAudio {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                        Rectangle()
                            .fill(Color("AccentCoral"))
                            .frame(width: geo.size.width * playback.audioPlayer.playbackProgress)
                    }
                }
                .frame(height: 3)
                .clipShape(Capsule())
                .padding(.horizontal, 20)
            }

            // Controls
            HStack(spacing: 30) {
                Button { playback.previousSegment() } label: {
                    Image(systemName: "backward.fill")
                        .font(.title3)
                }

                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(Color("AccentCoral"))
                }

                Button { playback.nextSegment() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 12)

            // Action buttons
            HStack(spacing: 16) {
                if !playback.isActive {
                    // Start buttons
                    Button {
                        playback.startSimulation()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Simulate Tour")
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button {
                        playback.startTour()
                    } label: {
                        HStack {
                            Image(systemName: "location.fill")
                            Text("Live GPS")
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("AccentCoral"))
                } else {
                    Button {
                        playback.stopTour()
                    } label: {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("End Tour")
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }
}
