import Foundation
import AVFoundation

@MainActor
class AudioPlayerService: ObservableObject {
    @Published var isPlaying = false
    @Published var currentSegmentIndex: Int = 0
    @Published var playbackProgress: Double = 0

    private var player: AVAudioPlayer?
    private var audioData: [Data] = []
    private var segments: [NarrationSegment] = []
    private var progressTimer: Timer?

    func prepare(segments: [NarrationSegment], audioUrls: [String]) async {
        self.segments = segments

        // Configure audio session for playback (works in background)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        // Download audio files
        audioData = []
        for url in audioUrls {
            if let audioUrl = URL(string: url),
               let (data, _) = try? await URLSession.shared.data(from: audioUrl) {
                audioData.append(data)
            } else {
                audioData.append(Data()) // placeholder for failed downloads
            }
        }
    }

    func playSegment(at index: Int) {
        guard index < audioData.count, !audioData[index].isEmpty else {
            // No audio data — skip to next
            currentSegmentIndex = index
            return
        }

        stop()
        currentSegmentIndex = index

        do {
            player = try AVAudioPlayer(data: audioData[index])
            player?.prepareToPlay()
            player?.play()
            isPlaying = true

            // Track progress
            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let player = self.player else { return }
                    if player.isPlaying {
                        self.playbackProgress = player.currentTime / max(player.duration, 1)
                    } else {
                        self.isPlaying = false
                        self.progressTimer?.invalidate()
                    }
                }
            }
        } catch {
            print("[AudioPlayer] Error playing segment \(index): \(error)")
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
        progressTimer?.invalidate()
    }

    func skipToNext() {
        let next = currentSegmentIndex + 1
        if next < audioData.count {
            playSegment(at: next)
        } else {
            stop()
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

    var hasAudio: Bool { !audioData.isEmpty && audioData.contains(where: { !$0.isEmpty }) }
}
