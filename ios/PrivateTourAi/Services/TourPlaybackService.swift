import Foundation
import CoreLocation

@MainActor
class TourPlaybackService: ObservableObject {
    @Published var isActive = false
    @Published var currentStopIndex: Int = -1  // -1 = intro
    @Published var currentSegmentType: String = "intro"
    @Published var isSimulating = false
    @Published var audioReady = false
    @Published var audioProgress: String = ""

    let audioPlayer = AudioPlayerService()

    private var tour: Tour?
    private var segments: [NarrationSegment] = []
    private var audioUrls: [String] = []
    private var simulationTask: Task<Void, Never>?

    // MARK: - Prepare Tour

    func prepareTour(_ tour: Tour) async {
        self.tour = tour
        self.segments = tour.narrationSegments.sorted { $0.sequenceOrder < $1.sequenceOrder }

        // Generate audio via API
        audioProgress = "Generating audio narration..."
        do {
            let response = try await APIClient.shared.generateAudio(tourId: tour.id)
            audioUrls = response.segments.map(\.audioUrl)
            audioProgress = "Downloading audio (\(response.segments.count) segments)..."

            // Map API audio segments to narration segments by order
            // The API returns segments in the same order as narration_segments
            await audioPlayer.prepare(segments: segments, audioUrls: audioUrls)
            audioReady = true
            audioProgress = ""
        } catch {
            audioProgress = "Audio unavailable — showing text narration"
            audioReady = false
            // Still allow text-based tour
        }
    }

    // MARK: - Start Tour (Real GPS)

    func startTour() {
        guard tour != nil else { return }
        isActive = true
        currentStopIndex = -1
        currentSegmentType = "intro"

        // Play intro segment
        if let introIdx = segments.firstIndex(where: { $0.segmentType == "intro" }) {
            audioPlayer.playSegment(at: introIdx)
        }
    }

    // MARK: - Simulate Tour (for testing without driving)

    func startSimulation() {
        guard let tour else { return }
        isActive = true
        isSimulating = true
        currentStopIndex = -1

        simulationTask = Task {
            // Play through each segment with pauses
            for (i, segment) in segments.enumerated() {
                if Task.isCancelled { break }

                currentSegmentType = segment.segmentType

                // Update current stop index based on segment
                if let toStopId = segment.toStopId,
                   let stopIdx = tour.stops.firstIndex(where: { $0.id == toStopId }) {
                    currentStopIndex = stopIdx
                }

                // Play audio if available
                if audioReady {
                    audioPlayer.playSegment(at: i)
                    // Wait for audio to finish (check every second)
                    while audioPlayer.isPlaying && !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                    }
                    // Brief pause between segments
                    try? await Task.sleep(for: .seconds(1))
                } else {
                    // No audio — show text for estimated duration
                    let duration = max(segment.estimatedDurationSeconds, 5)
                    try? await Task.sleep(for: .seconds(min(Double(duration), 10)))
                }
            }

            if !Task.isCancelled {
                isActive = false
                isSimulating = false
                currentSegmentType = "complete"
            }
        }
    }

    // MARK: - Navigate segments manually

    func nextSegment() {
        audioPlayer.skipToNext()
        updateCurrentStop()
    }

    func previousSegment() {
        audioPlayer.skipToPrevious()
        updateCurrentStop()
    }

    func togglePlayPause() {
        if audioPlayer.isPlaying {
            audioPlayer.pause()
        } else {
            audioPlayer.resume()
        }
    }

    // MARK: - Stop

    func stopTour() {
        simulationTask?.cancel()
        simulationTask = nil
        audioPlayer.stop()
        isActive = false
        isSimulating = false
        currentStopIndex = -1
    }

    // MARK: - Helpers

    private func updateCurrentStop() {
        let idx = audioPlayer.currentSegmentIndex
        guard idx < segments.count else { return }
        let segment = segments[idx]
        currentSegmentType = segment.segmentType

        if let toStopId = segment.toStopId,
           let stopIdx = tour?.stops.firstIndex(where: { $0.id == toStopId }) {
            currentStopIndex = stopIdx
        }
    }

    var currentNarrationText: String {
        let idx = audioPlayer.currentSegmentIndex
        guard idx < segments.count else { return "" }
        return segments[idx].narrationText
    }

    var currentStop: TourStop? {
        guard let tour, currentStopIndex >= 0, currentStopIndex < tour.stops.count else { return nil }
        return tour.stops[currentStopIndex]
    }

    var segmentLabel: String {
        switch currentSegmentType {
        case "intro": return "Welcome"
        case "approach": return "Approaching \(currentStop?.name ?? "stop")"
        case "at_stop": return currentStop?.name ?? "At Stop"
        case "departure": return "Departing \(currentStop?.name ?? "stop")"
        case "between_stops": return "On the road"
        case "outro": return "Tour Complete"
        case "complete": return "Tour Finished!"
        default: return currentSegmentType
        }
    }
}
