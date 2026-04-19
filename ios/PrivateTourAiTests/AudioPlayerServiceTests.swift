import Testing
import Foundation
import AVFoundation
@testable import PrivateTourAi

// MARK: - Fixtures

private func makeSegment(index: Int) -> NarrationSegment {
    let dict: [String: Any] = [
        "id": "seg-\(index)",
        "sequence_order": index,
        "segment_type": index == 0 ? "intro" : "at_stop",
        "narration_text": "Narration \(index)",
        "content_hash": "hash-\(index)",
        "estimated_duration_seconds": 5,
        "trigger_radius_meters": 50.0,
        "language": "en"
    ]
    let data = try! JSONSerialization.data(withJSONObject: dict)
    return try! JSONDecoder().decode(NarrationSegment.self, from: data)
}

private func makeSegments(_ count: Int) -> [NarrationSegment] {
    (0..<count).map { makeSegment(index: $0) }
}

/// Build a valid 16-bit PCM WAV (mono, 8kHz) big enough to clear the 100-byte guard
/// and short enough to keep tests fast.
private func makeSilentWAV(samples: Int = 400) -> Data {
    let sampleRate: UInt32 = 8000
    let bitsPerSample: UInt16 = 16
    let numChannels: UInt16 = 1
    let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
    let blockAlign = numChannels * (bitsPerSample / 8)
    let dataSize = UInt32(samples) * UInt32(blockAlign)
    let chunkSize = 36 + dataSize

    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
    data.append(contentsOf: "RIFF".utf8)
    append(chunkSize)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    append(UInt32(16))
    append(UInt16(1))          // PCM
    append(numChannels)
    append(sampleRate)
    append(byteRate)
    append(blockAlign)
    append(bitsPerSample)
    data.append(contentsOf: "data".utf8)
    append(dataSize)
    // 16-bit PCM silence = 0x0000
    data.append(Data(repeating: 0, count: Int(dataSize)))
    return data
}

private func audioCacheDir() -> URL {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("AudioCache", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Seed the production cache directory with fixture audio for a given URL so that
/// `downloadSegment` finds it and skips the network path.
private func seedCache(url: String, data: Data) {
    let key = url.components(separatedBy: "/").last ?? "seed"
    let file = audioCacheDir().appendingPathComponent(key)
    try? data.write(to: file)
}

private func wipeCache() {
    let dir = audioCacheDir()
    try? FileManager.default.removeItem(at: dir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
}

// MARK: - bufferFirst / primeUrl internals (item 1)

@Suite("AudioPlayerService — bufferFirst / primeUrl")
@MainActor
struct AudioPlayerBufferTests {

    @Test("primeUrl sets the URL at a valid index without affecting others")
    func primeUrlAssignsAtIndex() async {
        wipeCache()
        let player = AudioPlayerService()
        player.setupForOnDemand(segments: makeSegments(3), voiceEngine: "google", voicePreference: "premium")

        let url = "https://test.example/primed-\(UUID().uuidString).mp3"
        player.primeUrl(at: 1, url: url)

        // Seed disk cache so bufferFrom(1) succeeds without network.
        seedCache(url: url, data: makeSilentWAV())
        await player.bufferFrom(1)

        #expect(player.hasAudio == true)
    }

    @Test("primeUrl ignores out-of-range index without crashing")
    func primeUrlOutOfRange() async {
        wipeCache()
        let player = AudioPlayerService()
        player.setupForOnDemand(segments: makeSegments(2), voiceEngine: "google", voicePreference: "premium")

        // Should not crash or extend the internal urls array.
        player.primeUrl(at: 99, url: "https://test.example/oob.mp3")

        #expect(player.hasAudio == false)
    }

    @Test("bufferFirst loads segment 0 from disk cache when URL is primed")
    func bufferFirstUsesDiskCache() async {
        wipeCache()
        let player = AudioPlayerService()
        player.setupForOnDemand(segments: makeSegments(3), voiceEngine: "google", voicePreference: "premium")

        let url = "https://test.example/first-\(UUID().uuidString).mp3"
        seedCache(url: url, data: makeSilentWAV())
        player.primeUrl(at: 0, url: url)

        await player.bufferFirst()

        #expect(player.hasAudio == true)
        #expect(player.isBuffering == false)
    }

    @Test("bufferFirst is a no-op when audioData[0] is already populated")
    func bufferFirstIsIdempotent() async {
        wipeCache()
        let player = AudioPlayerService()
        player.setupForOnDemand(segments: makeSegments(2), voiceEngine: "google", voicePreference: "premium")

        let url = "https://test.example/idem-\(UUID().uuidString).mp3"
        seedCache(url: url, data: makeSilentWAV())
        player.primeUrl(at: 0, url: url)

        await player.bufferFirst()
        #expect(player.hasAudio == true)

        // Call again — should short-circuit without a second download. We can't
        // directly observe "no re-download", but hasAudio must still be true and
        // isBuffering must end up false.
        await player.bufferFirst()
        #expect(player.hasAudio == true)
        #expect(player.isBuffering == false)
    }

    @Test("bufferFirst with no segments does not crash and leaves hasAudio false")
    func bufferFirstEmptySegments() async {
        wipeCache()
        let player = AudioPlayerService()
        player.setupForOnDemand(segments: [], voiceEngine: "google", voicePreference: "premium")

        await player.bufferFirst()

        #expect(player.hasAudio == false)
        #expect(player.isBuffering == false)
    }

    @Test("hasAudio reflects whether at least one segment has non-trivial data")
    func hasAudioReflectsState() async {
        wipeCache()
        let player = AudioPlayerService()
        player.setupForOnDemand(segments: makeSegments(2), voiceEngine: "google", voicePreference: "premium")
        #expect(player.hasAudio == false)

        let url = "https://test.example/has-\(UUID().uuidString).mp3"
        seedCache(url: url, data: makeSilentWAV())
        player.primeUrl(at: 1, url: url)
        await player.bufferFrom(1)

        #expect(player.hasAudio == true)
    }

    @Test("clearAll wipes audio data, urls, and segments")
    func clearAllResets() async {
        wipeCache()
        let player = AudioPlayerService()
        player.setupForOnDemand(segments: makeSegments(2), voiceEngine: "google", voicePreference: "premium")
        let url = "https://test.example/clear-\(UUID().uuidString).mp3"
        seedCache(url: url, data: makeSilentWAV())
        player.primeUrl(at: 0, url: url)
        await player.bufferFirst()
        #expect(player.hasAudio == true)

        player.clearAll()

        #expect(player.hasAudio == false)
        #expect(player.totalSegments == 0)
    }
}

// MARK: - Actual AVAudioPlayer playback (item 2)

@Suite("AudioPlayerService — AVAudioPlayer playback")
@MainActor
struct AudioPlayerPlaybackTests {

    @Test("playSegment with valid WAV data starts playback (isPlaying=true)")
    func playbackStartsWithValidData() async {
        wipeCache()
        let player = AudioPlayerService()
        player.setupForOnDemand(segments: makeSegments(2), voiceEngine: "google", voicePreference: "premium")
        let url = "https://test.example/play-\(UUID().uuidString).wav"
        seedCache(url: url, data: makeSilentWAV(samples: 800))  // ~0.1s
        player.primeUrl(at: 0, url: url)
        await player.bufferFirst()

        player.playSegment(at: 0)

        // AVAudioPlayer.play() returns synchronously after setting isPlaying=true.
        #expect(player.isPlaying == true)
        #expect(player.currentSegmentIndex == 0)

        player.stop()
        #expect(player.isPlaying == false)
    }

    @Test("playSegment with invalid audio data marks segmentFinished and does not play")
    func invalidDataMarksFinished() async {
        wipeCache()
        let player = AudioPlayerService()
        player.setupForOnDemand(segments: makeSegments(2), voiceEngine: "google", voicePreference: "premium")
        // Seed with garbage that is long enough to pass the 100-byte guard but
        // AVAudioPlayer cannot decode.
        let url = "https://test.example/bad-\(UUID().uuidString).bin"
        seedCache(url: url, data: Data(repeating: 0xAB, count: 512))
        player.primeUrl(at: 0, url: url)
        await player.bufferFirst()

        player.playSegment(at: 0)

        #expect(player.isPlaying == false)
        #expect(player.segmentFinished == true)
    }

    @Test("playSegment with out-of-range index synchronously marks segmentFinished")
    func outOfRangeIndexMarksFinished() async {
        wipeCache()
        let player = AudioPlayerService()
        player.setupForOnDemand(segments: makeSegments(2), voiceEngine: "google", voicePreference: "premium")

        player.playSegment(at: 99)

        #expect(player.segmentFinished == true)
        #expect(player.isPlaying == false)
    }

    @Test("skipToNext advances currentSegmentIndex within bounds")
    func skipToNextWithinBounds() async {
        wipeCache()
        let player = AudioPlayerService()
        player.setupForOnDemand(segments: makeSegments(3), voiceEngine: "google", voicePreference: "premium")
        let url0 = "https://test.example/n0-\(UUID().uuidString).wav"
        let url1 = "https://test.example/n1-\(UUID().uuidString).wav"
        seedCache(url: url0, data: makeSilentWAV())
        seedCache(url: url1, data: makeSilentWAV())
        player.primeUrl(at: 0, url: url0)
        player.primeUrl(at: 1, url: url1)
        await player.bufferFirst()
        await player.bufferFrom(1)

        player.playSegment(at: 0)
        player.skipToNext()

        #expect(player.currentSegmentIndex == 1)
    }

    @Test("skipToPrevious is bounded at 0")
    func skipToPreviousBounded() async {
        wipeCache()
        let player = AudioPlayerService()
        player.setupForOnDemand(segments: makeSegments(2), voiceEngine: "google", voicePreference: "premium")
        let url = "https://test.example/p-\(UUID().uuidString).wav"
        seedCache(url: url, data: makeSilentWAV())
        player.primeUrl(at: 0, url: url)
        await player.bufferFirst()

        player.playSegment(at: 0)
        player.skipToPrevious()
        player.skipToPrevious()

        #expect(player.currentSegmentIndex == 0)
    }

    @Test("pause/resume toggles isPlaying without losing segment index")
    func pauseResume() async {
        wipeCache()
        let player = AudioPlayerService()
        player.setupForOnDemand(segments: makeSegments(1), voiceEngine: "google", voicePreference: "premium")
        let url = "https://test.example/pr-\(UUID().uuidString).wav"
        seedCache(url: url, data: makeSilentWAV(samples: 1600))  // ~0.2s
        player.primeUrl(at: 0, url: url)
        await player.bufferFirst()

        player.playSegment(at: 0)
        #expect(player.isPlaying == true)

        player.pause()
        #expect(player.isPlaying == false)
        #expect(player.currentSegmentIndex == 0)

        player.resume()
        #expect(player.isPlaying == true)

        player.stop()
    }
}
