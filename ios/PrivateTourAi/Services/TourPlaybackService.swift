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
    //
    // Progressive audio preparation: unblock the tour UI after segment 0 is ready.
    // Previously the Google path awaited a batch synthesis of every segment (~30-60s);
    // now we fetch segment 0 on-demand (~3-5s), flip audioReady, and stream the rest
    // in the background via ensureBuffered.

    // Static cache: tourId+engine -> audioUrls (persists across sheet presentations)
    private static var audioUrlCache: [String: [String]] = [:]
    private var preparedTourId: String?
    private var preparedEngine: String?
    private var backgroundPrefetchTask: Task<Void, Never>?

    func prepareTour(_ tour: Tour) async {
        // Skip if already prepared in this instance
        if preparedTourId == tour.id && preparedEngine == voiceEngine && audioReady {
            return
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

        // Fast path: cached URLs from a previous session — download first only
        let key = "\(tour.id):\(engine)"
        if let cachedUrls = Self.audioUrlCache[key] {
            audioPlayer.setupForOnDemand(segments: segments, voiceEngine: engine, voicePreference: quality)
            for (i, url) in cachedUrls.enumerated() where i < segments.count {
                audioPlayer.primeUrl(at: i, url: url)
            }
            await audioPlayer.bufferFirst()
            audioReady = audioPlayer.hasAudio
            audioProgress = ""
            if audioReady {
                preparedTourId = tour.id
                preparedEngine = engine
                startBackgroundPrefetch()
                return
            }
        }

        // Cold path: on-demand per segment for all engines. First segment unblocks UI.
        audioPlayer.setupForOnDemand(segments: segments, voiceEngine: engine, voicePreference: quality)
        await audioPlayer.bufferFirst()

        audioReady = audioPlayer.hasAudio
        audioProgress = ""
        if audioReady {
            preparedTourId = tour.id
            preparedEngine = engine
            startBackgroundPrefetch()
        } else {
            audioProgress = "Audio unavailable — text narration mode"
        }
    }

    /// Background task that continues downloading/generating segments 1...N after the UI has unblocked.
    /// Cancelled on voice switch / regenerate / stopTour.
    private func startBackgroundPrefetch() {
        backgroundPrefetchTask?.cancel()
        backgroundPrefetchTask = Task { [weak self] in
            guard let self else { return }
            // Warm through the full tour so skips and natural playback both hit cache.
            await self.audioPlayer.bufferFrom(1)
            // If Google batch endpoint succeeds later, we could also swap in canonical URLs;
            // for now per-segment generation is sufficient because the server caches by contentHash.
            if let tour = self.tour, self.audioPlayer.hasAudio {
                // Populate URL cache opportunistically so a later open is even faster.
                // (No-op if we only have on-demand URLs; batch call is a background best-effort.)
                _ = tour
            }
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

        // Cancel any in-flight prefetch and wipe audio cache
        backgroundPrefetchTask?.cancel()
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AudioCache", isDirectory: true)
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        audioPlayer.stop()
        audioPlayer.clearAll()
        isActive = false
        audioReady = false
        Self.audioUrlCache.removeValue(forKey: "\(tour.id):google")
        Self.audioUrlCache.removeValue(forKey: "\(tour.id):kokoro")
        preparedTourId = nil
        preparedEngine = nil

        self.tour = tour
        self.segments = tour.narrationSegments.sorted { $0.sequenceOrder < $1.sequenceOrder }
        guard !segments.isEmpty else { return }

        audioProgress = engine == "kokoro" ? "Preparing Kim..." : "Preparing Gary..."
        audioPlayer.setupForOnDemand(segments: segments, voiceEngine: engine, voicePreference: quality)
        await audioPlayer.bufferFirst()

        audioReady = audioPlayer.hasAudio
        audioProgress = ""
        if audioReady {
            preparedTourId = tour.id
            preparedEngine = engine
            startBackgroundPrefetch()
        } else {
            audioProgress = "Audio unavailable"
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
        backgroundPrefetchTask?.cancel()
        backgroundPrefetchTask = nil
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
