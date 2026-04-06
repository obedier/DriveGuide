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
    private var simulationTask: Task<Void, Never>?

    // MARK: - Prepare Tour

    func prepareTour(_ tour: Tour) async {
        self.tour = tour
        self.segments = tour.narrationSegments.sorted { $0.sequenceOrder < $1.sequenceOrder }

        guard !segments.isEmpty else {
            audioProgress = "No narration segments found"
            return
        }

        audioProgress = "Generating audio narration (\(segments.count) segments)..."
        do {
            let response = try await APIClient.shared.generateAudio(tourId: tour.id)
            let audioUrls = response.segments.map(\.audioUrl)
            audioProgress = "Downloading audio..."

            await audioPlayer.prepare(segments: segments, audioUrls: audioUrls)
            audioReady = audioPlayer.hasAudio
            audioProgress = audioReady ? "" : "Audio generation failed — using text narration"
            print("[Playback] Audio ready: \(audioReady), segments: \(segments.count)")
        } catch {
            print("[Playback] Audio generation error: \(error)")
            audioProgress = "Audio unavailable — text narration mode"
            audioReady = false
        }
    }

    // MARK: - Start Tour (manual playback)

    func startTour() {
        guard tour != nil, !segments.isEmpty else { return }
        isActive = true
        currentStopIndex = -1
        currentSegmentType = "intro"
        audioPlayer.playSegment(at: 0)
        updateCurrentStop()
    }

    // MARK: - Simulate Tour

    func startSimulation() {
        guard let tour, !segments.isEmpty else { return }
        isActive = true
        isSimulating = true
        currentStopIndex = -1

        simulationTask = Task { [weak self] in
            guard let self else { return }

            for (i, segment) in self.segments.enumerated() {
                if Task.isCancelled { break }

                // Update UI state
                self.currentSegmentType = segment.segmentType
                if let toStopId = segment.toStopId,
                   let stopIdx = tour.stops.firstIndex(where: { $0.id == toStopId }) {
                    self.currentStopIndex = stopIdx
                }

                if self.audioReady {
                    // Play audio and wait for it to finish
                    self.audioPlayer.playSegment(at: i)

                    // Wait for segmentFinished signal
                    while !self.audioPlayer.segmentFinished && !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(0.3))
                    }

                    // Brief pause between segments
                    if !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1.5))
                    }
                } else {
                    // No audio — display text for a few seconds then advance
                    let showDuration = min(Double(max(segment.estimatedDurationSeconds, 5)), 8.0)
                    try? await Task.sleep(for: .seconds(showDuration))
                }
            }

            if !Task.isCancelled {
                self.currentSegmentType = "complete"
                self.isActive = false
                self.isSimulating = false
            }
        }
    }

    // MARK: - Controls

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

    func stopTour() {
        simulationTask?.cancel()
        simulationTask = nil
        audioPlayer.stop()
        isActive = false
        isSimulating = false
        currentStopIndex = -1
        currentSegmentType = "intro"
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
        guard idx < segments.count else {
            if currentSegmentType == "complete" { return "Thank you for joining this tour! We hope you enjoyed it." }
            return ""
        }
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
