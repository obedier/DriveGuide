import Foundation
import AVFoundation

@MainActor
class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentSegmentIndex: Int = 0
    @Published var playbackProgress: Double = 0
    @Published var segmentFinished = false  // signals simulation to advance

    private var player: AVAudioPlayer?
    private var audioData: [Data] = []
    private var segments: [NarrationSegment] = []
    private var progressTimer: Timer?

    func prepare(segments: [NarrationSegment], audioUrls: [String]) async {
        self.segments = segments

        // Configure audio session for playback
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        // Download audio files (with disk cache)
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AudioCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        audioData = []
        for (i, url) in audioUrls.enumerated() {
            // Check disk cache first
            let cacheKey = url.components(separatedBy: "/").last ?? "\(i)"
            let cacheFile = cacheDir.appendingPathComponent(cacheKey)

            if let cached = try? Data(contentsOf: cacheFile), cached.count > 100 {
                audioData.append(cached)
                print("[AudioPlayer] Segment \(i + 1): cached (\(cached.count) bytes)")
                continue
            }

            print("[AudioPlayer] Downloading segment \(i + 1)/\(audioUrls.count)...")
            if let audioUrl = URL(string: url) {
                do {
                    let (data, response) = try await URLSession.shared.data(from: audioUrl)
                    let httpResponse = response as? HTTPURLResponse
                    if httpResponse?.statusCode == 200, data.count > 100 {
                        audioData.append(data)
                        try? data.write(to: cacheFile) // Save to disk cache
                        print("[AudioPlayer] Segment \(i + 1): downloaded + cached (\(data.count) bytes)")
                    } else {
                        print("[AudioPlayer] Segment \(i + 1): bad response \(httpResponse?.statusCode ?? 0)")
                        audioData.append(Data())
                    }
                } catch {
                    print("[AudioPlayer] Segment \(i + 1) error: \(error)")
                    audioData.append(Data())
                }
            } else {
                audioData.append(Data())
            }
        }
        print("[AudioPlayer] Prepared \(audioData.filter { !$0.isEmpty }.count)/\(audioData.count) audio segments")
    }

    func playSegment(at index: Int) {
        stop()
        currentSegmentIndex = index
        segmentFinished = false

        guard index < audioData.count, audioData[index].count > 100 else {
            print("[AudioPlayer] No audio data for segment \(index), marking as finished")
            segmentFinished = true
            return
        }

        do {
            player = try AVAudioPlayer(data: audioData[index])
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
        } catch {
            print("[AudioPlayer] Error playing segment \(index): \(error)")
            segmentFinished = true
        }
    }

    // AVAudioPlayerDelegate — called when segment finishes naturally
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.playbackProgress = 1.0
            self.progressTimer?.invalidate()
            self.segmentFinished = true
            print("[AudioPlayer] Segment \(self.currentSegmentIndex) finished playing")
        }
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
    var hasAudio: Bool { !audioData.isEmpty && audioData.contains(where: { $0.count > 100 }) }
}
