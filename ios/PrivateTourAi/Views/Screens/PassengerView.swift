import SwiftUI

/// Passenger Mode — a simplified, GPS-free, map-free playback surface optimized
/// for someone in the passenger seat of a moving car or reading on a phone.
///
/// Larger type, manual next/previous, big play/pause. Looks good in portrait
/// on a handheld without needing to squint. Reachable from:
///  - a shared link like `https://waipoint.o11r.com/passenger/<shareId>`
///  - the "Passenger Mode" toggle on TourDetailView
struct PassengerView: View {
    let tour: Tour
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback = TourPlaybackService()
    @State private var isPreparing = true

    var body: some View {
        ZStack {
            Color.brandDarkNavy.ignoresSafeArea()

            VStack(spacing: 20) {
                header

                Spacer()

                if isPreparing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.brandGold)
                        .scaleEffect(1.5)
                    Text(playback.audioProgress.isEmpty ? "Preparing audio..." : playback.audioProgress)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else {
                    narrationContent
                }

                Spacer()

                controls
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .task {
            await playback.prepareTour(tour)
            isPreparing = false
        }
        .onDisappear { playback.stopTour() }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                // High-contrast gold capsule "Close" button so the dismiss
                // control is obvious (prior chevron-only was invisible to
                // some beta testers).
                Button { dismiss() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                        Text("Close")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color.brandNavy)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.brandGold, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Passenger Mode")

                Spacer(minLength: 8)
            }

            VStack(spacing: 2) {
                Text("PASSENGER MODE")
                    .font(.caption2).tracking(2)
                    .foregroundStyle(.brandGold.opacity(0.7))
                Text(tour.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var narrationContent: some View {
        VStack(spacing: 14) {
            Text(playback.segmentLabel)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.brandGold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            ScrollView(showsIndicators: false) {
                Text(playback.currentNarrationText)
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(8)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: 380)

            segmentCounter
        }
        .frame(maxWidth: .infinity)
    }

    private var segmentCounter: some View {
        HStack(spacing: 12) {
            ForEach(0..<max(playback.audioPlayer.totalSegments, 1), id: \.self) { idx in
                Capsule()
                    .fill(idx == playback.audioPlayer.currentSegmentIndex
                          ? Color.brandGold
                          : Color.white.opacity(0.25))
                    .frame(width: idx == playback.audioPlayer.currentSegmentIndex ? 24 : 8, height: 4)
                    .animation(.easeInOut(duration: 0.2),
                               value: playback.audioPlayer.currentSegmentIndex)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 32) {
            bigButton(systemName: "backward.fill", diameter: 56) {
                playback.previousSegment()
            }
            .accessibilityLabel("Previous segment")

            bigButton(
                systemName: playback.audioPlayer.isPlaying ? "pause.fill" : "play.fill",
                diameter: 88,
                filled: true
            ) {
                if !playback.isActive {
                    playback.startTour()
                } else {
                    playback.togglePlayPause()
                }
            }
            .accessibilityLabel(playback.audioPlayer.isPlaying ? "Pause" : "Play")

            bigButton(systemName: "forward.fill", diameter: 56) {
                playback.nextSegment()
            }
            .accessibilityLabel("Next segment")
        }
        .disabled(isPreparing || !playback.audioReady)
        .opacity((isPreparing || !playback.audioReady) ? 0.4 : 1)
    }

    private func bigButton(systemName: String, diameter: CGFloat, filled: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(filled ? Color.brandGold : Color.white.opacity(0.08))
                    .frame(width: diameter, height: diameter)
                Image(systemName: systemName)
                    .font(.system(size: diameter * 0.4, weight: .bold))
                    .foregroundStyle(filled ? Color.brandNavy : .white)
            }
        }
        .buttonStyle(.plain)
    }
}
