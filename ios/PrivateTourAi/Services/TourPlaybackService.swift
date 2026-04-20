import Foundation
import CoreLocation
import SwiftUI
import AVFoundation

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

    /// 2.16: Bridge-narration state. Non-nil when the user started the tour
    /// while far from the first stop; the app plays a dynamically-generated
    /// drive-to narration and holds segment 0 until they're in range.
    @Published var bridgeState: BridgeState?

    struct BridgeState: Equatable {
        var distanceKm: Double
        var etaMinutes: Int
        var firstStopName: String
        /// `true` while the bridge is playing, `false` once the user arrived
        /// at the first stop and segment 0 took over.
        var isPlaying: Bool
    }

    /// Distance threshold below which we skip the bridge and start segment 0
    /// immediately. Configurable per transport mode since "far" means
    /// different things at 40mph vs. 3mph.
    private func bridgeThresholdMeters(for transport: String?) -> Double {
        switch transport {
        case "walk", "bike": return 150
        default: return 400  // car / boat / plane / default
        }
    }

    /// Player dedicated to the bridge narration — separate from the main
    /// audioPlayer so we don't fight its segment state.
    private var bridgePlayer: AVAudioPlayer?
    private var bridgeDelegate: BridgePlayerDelegate?

    let audioPlayer: AudioPlayerService

    private var tour: Tour?

    /// Read-only accessor to the currently prepared tour — used by the
    /// SegmentListSheet so it can resolve stop names for each segment.
    var currentTour: Tour? { tour }
    private var segments: [NarrationSegment] = []
    private var simulationTask: Task<Void, Never>?

    /// Production init — creates a real AudioPlayerService.
    convenience init() {
        self.init(audioPlayer: AudioPlayerService())
    }

    /// Dependency-injected init so tests can substitute a fake subclass
    /// that records orchestration calls without touching the network or AVAudioSession.
    init(audioPlayer: AudioPlayerService) {
        self.audioPlayer = audioPlayer
    }

    /// Static-cache seam for tests. Exposed as internal so unit tests can wipe it
    /// between test runs.
    static func resetAudioUrlCacheForTesting() {
        audioUrlCache.removeAll()
    }

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

        // Fastest path: this tour has been saved for offline playback. Skip the
        // network entirely, load all audio bytes from disk, and flip audioReady.
        if await OfflineTourStore.shared.isDownloaded(tourId: tour.id) {
            let audio = await OfflineTourStore.shared.allAudioData(for: tour)
            audioPlayer.setupFromOffline(segments: segments, audioBytes: audio)
            audioReady = audioPlayer.hasAudio
            audioProgress = audioReady ? "" : "Offline audio unavailable"
            if audioReady {
                preparedTourId = tour.id
                preparedEngine = engine
            }
            return
        }

        // Fast path for pre-generated / already-synthesized tours: every
        // segment in the API response already carries an audio_url. Skip
        // bufferFirst's re-synthesis round-trip entirely — just hand the URLs
        // to the player and we're ready. This is the common case for wAIpoint
        // Featured tours where audio was synthesized at seed time.
        let serverUrls = segments.map { $0.audioUrl ?? "" }
        if !serverUrls.contains(where: { $0.isEmpty }) {
            audioPlayer.setup(segments: segments, audioUrls: serverUrls)
            audioReady = true
            audioProgress = ""
            preparedTourId = tour.id
            preparedEngine = engine
            // Prefetch segment 0 in background so first play is instant.
            Task { await audioPlayer.bufferFirst() }
            startBackgroundPrefetch()
            return
        }

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

    /// 2.16: Start a tour with awareness of where the user physically is.
    /// If they're far from stop 0, fetch a dynamically-generated "drive-to"
    /// bridge narration, play it immediately, and hold the pre-generated
    /// segment 0 until they arrive within the threshold.
    ///
    /// Callers (GuidedTourView) should feed subsequent location updates in
    /// via `observeLocation(_:)` so the coordinator can detect arrival and
    /// hand off to segment 0.
    func startTourWithAwareness(userLocation: CLLocationCoordinate2D?) {
        guard let tour, let firstStop = tour.stops.first, !segments.isEmpty else {
            startTour()
            return
        }
        guard let userLoc = userLocation else {
            startTour()
            return
        }
        let firstCoord = CLLocationCoordinate2D(latitude: firstStop.latitude, longitude: firstStop.longitude)
        let distanceMeters = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
            .distance(from: CLLocation(latitude: firstCoord.latitude, longitude: firstCoord.longitude))
        let threshold = bridgeThresholdMeters(for: tour.transportMode)
        if distanceMeters <= threshold {
            startTour()
            return
        }
        isActive = true
        currentStopIndex = -1
        currentSegmentType = "intro"

        let km = distanceMeters / 1000.0
        bridgeState = BridgeState(
            distanceKm: km,
            etaMinutes: Int(ceil(km / estimatedSpeedKph(for: tour.transportMode) * 60)),
            firstStopName: firstStop.name,
            isPlaying: false
        )

        // Track the in-flight fetch so stopTour / cancelBridge can kill it
        // before the URLSession resolves — otherwise tests and fast
        // dismissals leave hanging requests that touch deallocated state.
        bridgeFetchTask = Task { [weak self] in
            await self?.fetchAndPlayBridge(tour: tour, userLat: userLoc.latitude, userLng: userLoc.longitude)
        }
    }

    private func estimatedSpeedKph(for transport: String?) -> Double {
        switch transport {
        case "walk": return 5
        case "bike": return 16
        default: return 45
        }
    }

    private func fetchAndPlayBridge(tour: Tour, userLat: Double, userLng: Double) async {
        do {
            let response = try await APIClient.shared.getBridgeNarration(
                tourId: tour.id, userLat: userLat, userLng: userLng,
                etaMinutes: bridgeState?.etaMinutes
            )
            // Bail silently if the owning view / test has moved on.
            if Task.isCancelled { return }
            // Distance may have dropped below the threshold during the
            // fetch round-trip (user was driving). If so, skip the bridge
            // and hand straight to segment 0 — the latest location is in
            // lastObservedLocation via observeLocation().
            if let latest = lastObservedLocation,
               let firstStop = tour.stops.first {
                let distance = CLLocation(latitude: firstStop.latitude, longitude: firstStop.longitude)
                    .distance(from: CLLocation(latitude: latest.latitude, longitude: latest.longitude))
                if distance <= bridgeThresholdMeters(for: tour.transportMode) {
                    bridgeState = nil
                    startTour()
                    return
                }
            }
            try await startBridgePlayback(audioUrlString: response.audioUrl)
            if Task.isCancelled { bridgePlayer?.stop(); return }
            previousBridgeOpeners.append(firstPhrase(of: response.narrationText))
            if var state = bridgeState {
                state.etaMinutes = response.etaMinutes
                state.distanceKm = response.distanceKm
                state.isPlaying = true
                bridgeState = state
            }
            scheduleFollowUpBridgeIfNeeded()
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            print("[TourPlayback] bridge narration failed: \(error) — falling back to segment 0")
            bridgeState = nil
            startTour()
        }
    }

    /// Most recent location observed via `observeLocation(_:)`. Used to
    /// short-circuit the bridge playback if the user has already reached
    /// the threshold while we were fetching narration.
    private var lastObservedLocation: CLLocationCoordinate2D?

    /// In-flight fetch for the opener bridge. Cancelled by cancelBridge /
    /// stopTour so URLSession requests don't outlive the service.
    private var bridgeFetchTask: Task<Void, Never>?

    /// First-phrase signatures of bridges already played on this trip. Fed
    /// back into the server so Gemini doesn't recycle the same opening device.
    private var previousBridgeOpeners: [String] = []

    /// Hard clamp on follow-up cadence. Short floor keeps us from hammering
    /// the API; ceiling keeps the ride from going silent for too long.
    private let followUpMinInterval: TimeInterval = 3 * 60   // 3 min
    private let followUpMaxInterval: TimeInterval = 6 * 60   // 6 min

    /// Cap on total follow-ups per trip. Opener + 3 follow-ups covers an
    /// hour-plus drive before we just let silence ride.
    private let maxFollowUpBridges = 3
    private var followUpBridgesPlayed = 0
    private var followUpBridgeTask: Task<Void, Never>?

    /// Pure-function version — testable without touching instance state.
    /// Spreads the remaining-ETA-minus-3min across slots_left slots, clamped
    /// to [minInterval, maxInterval]. Exposed as `internal` so tests can
    /// exercise the math.
    static func computeFollowUpDelay(
        etaMinutes: Int,
        followUpsPlayed: Int,
        maxFollowUps: Int,
        minInterval: TimeInterval,
        maxInterval: TimeInterval
    ) -> TimeInterval {
        let remainingMinutes = max(0, etaMinutes - 3)  // reserve 3 min tail
        let slotsLeft = max(1, maxFollowUps - followUpsPlayed)
        let perSlot = Double(remainingMinutes) / Double(slotsLeft)
        let seconds = perSlot * 60
        return max(minInterval, min(seconds, maxInterval))
    }

    /// Instance wrapper — reads current bridge state + played-count.
    private func nextFollowUpDelay() -> TimeInterval {
        Self.computeFollowUpDelay(
            etaMinutes: bridgeState?.etaMinutes ?? 0,
            followUpsPlayed: followUpBridgesPlayed,
            maxFollowUps: maxFollowUpBridges,
            minInterval: followUpMinInterval,
            maxInterval: followUpMaxInterval
        )
    }

    private func scheduleFollowUpBridgeIfNeeded() {
        followUpBridgeTask?.cancel()
        let delay = nextFollowUpDelay()
        followUpBridgeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            await self?.fireFollowUpBridgeIfStillFar()
        }
    }

    @MainActor
    private func fireFollowUpBridgeIfStillFar() async {
        guard let tour, let firstStop = tour.stops.first, bridgeState != nil else { return }
        if followUpBridgesPlayed >= maxFollowUpBridges { return }
        guard let userLoc = lastObservedLocation else { return }
        let distance = CLLocation(latitude: firstStop.latitude, longitude: firstStop.longitude)
            .distance(from: CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude))
        let threshold = bridgeThresholdMeters(for: tour.transportMode)
        // Too close to the first stop OR barely any ETA left? Skip the follow-up.
        let etaMinutes = Int(ceil(distance / 1000.0 / estimatedSpeedKph(for: tour.transportMode) * 60))
        if distance <= threshold || etaMinutes < 2 { return }

        do {
            let response = try await APIClient.shared.getBridgeNarration(
                tourId: tour.id, userLat: userLoc.latitude, userLng: userLoc.longitude,
                etaMinutes: etaMinutes, kind: "follow_up",
                previousOpeners: previousBridgeOpeners
            )
            // Distance might have dropped below threshold during fetch.
            if let latest = lastObservedLocation {
                let recheck = CLLocation(latitude: firstStop.latitude, longitude: firstStop.longitude)
                    .distance(from: CLLocation(latitude: latest.latitude, longitude: latest.longitude))
                if recheck <= threshold { return }
            }
            try await startBridgePlayback(audioUrlString: response.audioUrl)
            previousBridgeOpeners.append(firstPhrase(of: response.narrationText))
            followUpBridgesPlayed += 1
            if var state = bridgeState {
                state.etaMinutes = response.etaMinutes
                state.distanceKm = response.distanceKm
                state.isPlaying = true
                bridgeState = state
            }
            scheduleFollowUpBridgeIfNeeded()
        } catch {
            print("[TourPlayback] follow-up bridge failed: \(error)")
        }
    }

    private func firstPhrase(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.split(whereSeparator: { ",.!?—;".contains($0) }).first {
            return String(first).prefix(60).trimmingCharacters(in: .whitespaces)
        }
        return String(trimmed.prefix(60))
    }

    private func startBridgePlayback(audioUrlString: String) async throws {
        guard let url = URL(string: audioUrlString) else { return }
        let (data, _) = try await URLSession.shared.data(from: url)

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)

        let player = try AVAudioPlayer(data: data)
        let delegate = BridgePlayerDelegate { [weak self] in
            // Bridge finished naturally: leave bridgeState in place (still
            // showing "driving to…"), don't auto-start segment 0 — wait for
            // the location handoff.
            guard let self else { return }
            if var state = self.bridgeState {
                state.isPlaying = false
                self.bridgeState = state
            }
        }
        player.delegate = delegate
        player.prepareToPlay()
        player.play()
        bridgePlayer = player
        bridgeDelegate = delegate
    }

    /// Fed from GuidedTourView's CLLocationManager. When the user gets within
    /// the arrival threshold of the first stop, stop the bridge (if still
    /// playing), clear bridgeState, and kick off segment 0.
    func observeLocation(_ coordinate: CLLocationCoordinate2D) {
        lastObservedLocation = coordinate
        guard let tour, let firstStop = tour.stops.first, bridgeState != nil else { return }
        let firstCoord = CLLocation(latitude: firstStop.latitude, longitude: firstStop.longitude)
        let distance = firstCoord.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        let threshold = bridgeThresholdMeters(for: tour.transportMode)
        // Update the live distance for the UI banner.
        if var state = bridgeState {
            state.distanceKm = distance / 1000.0
            state.etaMinutes = max(0, Int(ceil(state.distanceKm / estimatedSpeedKph(for: tour.transportMode) * 60)))
            bridgeState = state
        }
        if distance <= threshold {
            bridgePlayer?.stop()
            bridgePlayer = nil
            bridgeDelegate = nil
            bridgeState = nil
            followUpBridgeTask?.cancel()
            followUpBridgeTask = nil
            startTour()
        }
    }

    /// Abort the bridge — called by stopTour() so we don't leak an audio
    /// player or a hanging URLSession request.
    private func cancelBridge() {
        bridgeFetchTask?.cancel()
        bridgeFetchTask = nil
        followUpBridgeTask?.cancel()
        followUpBridgeTask = nil
        bridgePlayer?.stop()
        bridgePlayer = nil
        bridgeDelegate = nil
        bridgeState = nil
        followUpBridgesPlayed = 0
        previousBridgeOpeners.removeAll()
        lastObservedLocation = nil
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
        cancelBridge()
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

/// Delegate used only by the bridge narration's AVAudioPlayer so
/// TourPlaybackService can react when the bridge finishes playing.
private final class BridgePlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in onFinish() }
    }
}
