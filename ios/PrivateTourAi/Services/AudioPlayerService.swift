import Foundation
import AVFoundation

@MainActor
class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentSegmentIndex: Int = 0
    @Published var playbackProgress: Double = 0
    @Published var segmentFinished = false
    @Published var isBuffering = false

    private var player: AVAudioPlayer?
    private var audioData: [Data?] = []  // nil = not yet downloaded
    private(set) var segments: [NarrationSegment] = []
    private var audioUrls: [String] = []
    private var progressTimer: Timer?
    private var bufferTask: Task<Void, Never>?

    private let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AudioCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let bufferAhead = 3  // Buffer 3 ahead for smoother skip
    var voiceEngine: String = "google"
    var voicePreference: String = "premium"

    // MARK: - Setup

    func setup(segments: [NarrationSegment], audioUrls: [String]) {
        self.segments = segments
        self.audioUrls = audioUrls
        self.audioData = Array(repeating: nil, count: segments.count)

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)

        print("[AudioPlayer] Setup with \(segments.count) segments, will buffer progressively")
    }

    /// Setup without pre-generated URLs (will generate per-segment on demand)
    func setupForOnDemand(segments: [NarrationSegment], voiceEngine: String, voicePreference: String) {
        self.segments = segments
        self.audioUrls = Array(repeating: "", count: segments.count)
        self.audioData = Array(repeating: nil, count: segments.count)
        self.voiceEngine = voiceEngine
        self.voicePreference = voicePreference

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)

        print("[AudioPlayer] Setup for on-demand generation (\(voiceEngine)), \(segments.count) segments")
    }

    // MARK: - Progressive Buffering

    func bufferFrom(_ index: Int) async {
        let end = min(index + bufferAhead, segments.count)
        for i in index..<end {
            if audioData[i] != nil { continue }
            if audioUrls[i].isEmpty {
                // Generate URL on demand
                await generateAndDownload(at: i)
            } else {
                await downloadSegment(at: i)
            }
        }
    }

    func bufferInitial() async {
        isBuffering = true
        await bufferFrom(0)
        isBuffering = false
    }

    /// Minimum required to unblock the UI: download/generate segment 0 only.
    /// Remaining segments should be fetched via `ensureBuffered(around:)` afterward.
    func bufferFirst() async {
        isBuffering = true
        defer { isBuffering = false }
        guard !audioData.isEmpty, audioData[0] == nil else { return }
        if audioUrls[0].isEmpty {
            await generateAndDownload(at: 0)
        } else {
            await downloadSegment(at: 0)
        }
    }

    /// Seed a pre-fetched audio URL for a given segment without replacing the whole setup.
    /// Used when we want to prime segment 0 with an inline-generated URL while leaving
    /// the rest on-demand.
    func primeUrl(at index: Int, url: String) {
        guard index < audioUrls.count else { return }
        audioUrls[index] = url
    }

    /// Continue buffering ahead in background as playback progresses
    func ensureBuffered(around index: Int) {
        bufferTask?.cancel()
        bufferTask = Task {
            await bufferFrom(index)
        }
    }

    private func generateAndDownload(at index: Int) async {
        guard index < segments.count else { return }
        let seg = segments[index]
        do {
            let url = try await APIClient.shared.generateSegmentAudio(
                text: seg.narrationText,
                contentHash: seg.contentHash,
                voiceEngine: voiceEngine,
                voicePreference: voicePreference
            )
            audioUrls[index] = url
            await downloadSegment(at: index)
        } catch {
            print("[AudioPlayer] Generate failed for segment \(index + 1): \(error)")
            audioData[index] = Data()
        }
    }

    private func downloadSegment(at index: Int) async {
        guard index < audioUrls.count else { return }
        let url = audioUrls[index]

        // Check disk cache
        let cacheKey = url.components(separatedBy: "/").last ?? "\(index)"
        let cacheFile = cacheDir.appendingPathComponent(cacheKey)

        if let cached = try? Data(contentsOf: cacheFile), cached.count > 100 {
            audioData[index] = cached
            print("[AudioPlayer] Segment \(index + 1): disk cache (\(cached.count) bytes)")
            return
        }

        // Download
        guard let audioUrl = URL(string: url) else {
            audioData[index] = Data()
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: audioUrl)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200, data.count > 100 {
                audioData[index] = data
                try? data.write(to: cacheFile)
                print("[AudioPlayer] Segment \(index + 1): downloaded (\(data.count) bytes)")
            } else {
                audioData[index] = Data()
                print("[AudioPlayer] Segment \(index + 1): bad response \(status)")
            }
        } catch {
            audioData[index] = Data()
            print("[AudioPlayer] Segment \(index + 1) error: \(error)")
        }
    }

    // MARK: - Playback

    func playSegment(at index: Int) {
        stop()
        currentSegmentIndex = index
        segmentFinished = false

        // If segment not yet downloaded, buffer it first
        if index < audioData.count && audioData[index] == nil {
            print("[AudioPlayer] Segment \(index) not buffered yet, downloading...")
            Task {
                await bufferFrom(index)
                if let data = audioData[index], data.count > 100 {
                    startPlaying(data: data, index: index)
                } else {
                    segmentFinished = true
                }
            }
            return
        }

        guard index < audioData.count, let data = audioData[index], data.count > 100 else {
            print("[AudioPlayer] No audio data for segment \(index), marking as finished")
            segmentFinished = true
            return
        }

        startPlaying(data: data, index: index)
    }

    private func startPlaying(data: Data, index: Int) {
        do {
            player = try AVAudioPlayer(data: data)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
            isPlaying = true
            print("[AudioPlayer] Playing segment \(index), duration: \(player?.duration ?? 0)s")

            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let player = self.player else { return }
                    self.playbackProgress = player.currentTime / max(player.duration, 1)
                }
            }

            // Buffer ahead while playing
            ensureBuffered(around: index + 1)
        } catch {
            print("[AudioPlayer] Error playing segment \(index): \(error)")
            segmentFinished = true
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.playbackProgress = 1.0
            self.progressTimer?.invalidate()
            self.segmentFinished = true
            print("[AudioPlayer] Segment \(self.currentSegmentIndex) finished playing")
        }
    }

    func seek(to progress: Double) {
        guard let player else { return }
        let target = max(0, min(progress, 1.0)) * player.duration
        player.currentTime = target
        playbackProgress = progress
    }

    func pause() {
        player?.pause()
        isPlaying = false
        progressTimer?.invalidate()
    }

    func resume() {
        player?.play()
        isPlaying = true
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        playbackProgress = 0
        segmentFinished = false
        progressTimer?.invalidate()
    }

    func clearAll() {
        stop()
        bufferTask?.cancel()
        audioData = []
        audioUrls = []
        segments = []
        currentSegmentIndex = 0
    }

    func skipToNext() {
        let next = currentSegmentIndex + 1
        if next < segments.count {
            playSegment(at: next)
        } else {
            stop()
            segmentFinished = true
        }
    }

    func skipToPrevious() {
        let prev = max(currentSegmentIndex - 1, 0)
        playSegment(at: prev)
    }

    var currentSegment: NarrationSegment? {
        guard currentSegmentIndex < segments.count else { return nil }
        return segments[currentSegmentIndex]
    }

    var totalSegments: Int { segments.count }
    var hasAudio: Bool { audioData.contains(where: { ($0?.count ?? 0) > 100 }) }

    // Legacy compatibility
    func prepare(segments: [NarrationSegment], audioUrls: [String]) async {
        setup(segments: segments, audioUrls: audioUrls)
        await bufferInitial()
    }
}
