import Foundation
import CoreLocation
import SwiftUI

@MainActor
class TourPlaybackService: ObservableObject {
    @AppStorage("voiceQuality") var voiceQuality = "premium"
    @AppStorage("voiceEngine") var voiceEngine = "google"
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

    // Static cache: tourId+engine -> audioUrls (persists across sheet presentations)
    private static var audioUrlCache: [String: [String]] = [:]
    private var preparedTourId: String?
    private var preparedEngine: String?

    private var cacheKey: String { "\(tour?.id ?? ""):\(voiceEngine)" }

    func prepareTour(_ tour: Tour) async {
        // Skip if already prepared in this instance
        if preparedTourId == tour.id && preparedEngine == voiceEngine && audioReady {
            return
        }

        // Check static cache — audio URLs from previous session
        let key = "\(tour.id):\(voiceEngine)"
        // Check URL cache (from previous session)
        if let cachedUrls = Self.audioUrlCache[key] {
            self.tour = tour
            self.segments = tour.narrationSegments.sorted { $0.sequenceOrder < $1.sequenceOrder }
            audioProgress = "Loading audio..."
            audioPlayer.setup(segments: segments, audioUrls: cachedUrls)
            await audioPlayer.bufferInitial()  // Only downloads first 2 segments
            audioReady = audioPlayer.hasAudio
            audioProgress = ""
            preparedTourId = tour.id
            preparedEngine = voiceEngine
            if audioReady { return }
        }

        self.tour = tour
        self.segments = tour.narrationSegments.sorted { $0.sequenceOrder < $1.sequenceOrder }

        guard !segments.isEmpty else {
            audioProgress = "No narration segments found"
            return
        }

        let engine = voiceEngine
        let quality = voiceQuality
        audioProgress = engine == "kokoro" ? "Preparing Kim..." : "Preparing audio..."

        if engine == "kokoro" {
            // Kokoro: on-demand per segment (fast first audio, ~5s)
            audioPlayer.setupForOnDemand(segments: segments, voiceEngine: engine, voicePreference: quality)
            await audioPlayer.bufferInitial()
        } else {
            // Google: batch all URLs at once (fast, <3s total)
            do {
                let response: AudioResponse
                do {
                    response = try await APIClient.shared.generateAudio(tourId: tour.id, voicePreference: quality, voiceEngine: engine)
                } catch {
                    response = try await APIClient.shared.generateAudioInline(segments: segments, voicePreference: quality, voiceEngine: engine)
                }
                let audioUrls = response.segments.map(\.audioUrl)
                audioPlayer.setup(segments: segments, audioUrls: audioUrls)
                await audioPlayer.bufferInitial()
                if audioPlayer.hasAudio {
                    Self.audioUrlCache["\(tour.id):\(engine)"] = audioUrls
                }
            } catch {
                print("[Playback] Google audio error: \(error)")
                audioProgress = "Audio unavailable — text narration mode"
                audioReady = false
                return
            }
        }

        audioReady = audioPlayer.hasAudio
        audioProgress = ""
        if audioReady {
            preparedTourId = tour.id
            preparedEngine = engine
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

    // MARK: - Voice Switching

    func switchVoice(engine: String, quality: String) {
        print("[Playback] Switching voice: \(voiceEngine) -> \(engine)")
        // Set engine BEFORE regenerating — pass explicitly to avoid @AppStorage sync issues
        voiceEngine = engine
        voiceQuality = quality
        Task {
            // Regenerate with explicit engine parameter
            await regenerateAudioWith(engine: engine, quality: quality)
        }
    }

    // MARK: - Regenerate Audio

    func regenerateAudio() async {
        await regenerateAudioWith(engine: voiceEngine, quality: voiceQuality)
    }

    private func regenerateAudioWith(engine: String, quality: String) async {
        guard let tour else { return }

        // Wipe entire audio cache to force fresh downloads
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AudioCache", isDirectory: true)
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Stop current playback and reset
        audioPlayer.stop()
        audioPlayer.clearAll()
        isActive = false
        audioReady = false
        // Clear ALL cached URLs for this tour (both engines)
        Self.audioUrlCache.removeValue(forKey: "\(tour.id):google")
        Self.audioUrlCache.removeValue(forKey: "\(tour.id):kokoro")
        preparedTourId = nil
        preparedEngine = nil

        // Generate with explicit engine (don't rely on @AppStorage)
        self.tour = tour
        self.segments = tour.narrationSegments.sorted { $0.sequenceOrder < $1.sequenceOrder }
        guard !segments.isEmpty else { return }

        audioProgress = engine == "kokoro" ? "Preparing Kim..." : "Preparing Gary..."

        if engine == "kokoro" {
            audioPlayer.setupForOnDemand(segments: segments, voiceEngine: engine, voicePreference: quality)
            await audioPlayer.bufferInitial()
        } else {
            do {
                let response: AudioResponse
                do {
                    response = try await APIClient.shared.generateAudio(tourId: tour.id, voicePreference: quality, voiceEngine: engine)
                } catch {
                    response = try await APIClient.shared.generateAudioInline(segments: segments, voicePreference: quality, voiceEngine: engine)
                }
                let audioUrls = response.segments.map(\.audioUrl)
                audioPlayer.setup(segments: segments, audioUrls: audioUrls)
                await audioPlayer.bufferInitial()
                if audioPlayer.hasAudio {
                    Self.audioUrlCache["\(tour.id):\(engine)"] = audioUrls
                }
            } catch {
                audioProgress = "Audio unavailable"
                audioReady = false
                return
            }
        }

        audioReady = audioPlayer.hasAudio
        audioProgress = ""
        if audioReady {
            preparedTourId = tour.id
            preparedEngine = engine
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
        if !isActive {
            // Tour not started — start simulation
            startSimulation()
        } else if audioPlayer.isPlaying {
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
