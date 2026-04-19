import Testing
import Foundation
@testable import PrivateTourAi

// MARK: - Fake audio player that records orchestration calls without touching
// the network or AVAudioSession. Subclasses AudioPlayerService so it can be
// injected wherever the concrete type is expected.

@MainActor
final class FakeAudioPlayer: AudioPlayerService {
    var setupForOnDemandCalls: [(segments: [NarrationSegment], engine: String, preference: String)] = []
    var primedUrls: [(index: Int, url: String)] = []
    var bufferFirstCount = 0
    var bufferFromIndices: [Int] = []
    var stopCalled = 0
    var clearAllCalled = 0
    var hasAudioFake = true

    override func setupForOnDemand(segments: [NarrationSegment], voiceEngine: String, voicePreference: String) {
        setupForOnDemandCalls.append((segments, voiceEngine, voicePreference))
    }

    override func primeUrl(at index: Int, url: String) {
        primedUrls.append((index, url))
    }

    override func bufferFirst() async {
        bufferFirstCount += 1
    }

    override func bufferFrom(_ index: Int) async {
        bufferFromIndices.append(index)
    }

    override func stop() { stopCalled += 1 }

    override func clearAll() { clearAllCalled += 1 }

    override var hasAudio: Bool { hasAudioFake }
}

// MARK: - Helpers — build Tour fixtures via JSON decoding because the models
// only expose Decodable initializers.

private func makeTour(stopCount: Int = 3, segmentCount: Int = 4) -> Tour {
    let stops: [[String: Any]] = (0..<stopCount).map { i in
        [
            "id": "stop-\(i)",
            "sequence_order": i,
            "name": "Stop \(i)",
            "description": "desc \(i)",
            "category": "landmark",
            "latitude": 25.76,
            "longitude": -80.19,
            "recommended_stay_minutes": 5,
            "is_optional": false,
            "approach_narration": "",
            "at_stop_narration": "",
            "departure_narration": ""
        ]
    }
    let segments: [[String: Any]] = (0..<segmentCount).map { i in
        [
            "id": "seg-\(i)",
            "sequence_order": i,
            "segment_type": i == 0 ? "intro" : "at_stop",
            "narration_text": "Narration \(i)",
            "content_hash": "hash-\(i)",
            "estimated_duration_seconds": 30,
            "trigger_radius_meters": 50.0,
            "language": "en",
            "to_stop_id": i == 0 ? NSNull() : "stop-\(i)" as Any
        ]
    }
    let dict: [String: Any] = [
        "id": "tour-1",
        "title": "Test Tour",
        "description": "Test",
        "duration_minutes": 60,
        "themes": ["history"],
        "language": "en",
        "status": "ready",
        "transport_mode": "car",
        "stops": stops,
        "narration_segments": segments,
        "created_at": ""
    ]
    let data = try! JSONSerialization.data(withJSONObject: dict)
    return try! JSONDecoder().decode(Tour.self, from: data)
}

// MARK: - prepareTour behavior

@Suite("Tour Playback Service — prepareTour")
@MainActor
struct TourPlaybackServiceTests {

    @Test("prepareTour with empty segments reports progress and does not set audioReady")
    func emptySegments() async {
        TourPlaybackService.resetAudioUrlCacheForTesting()
        let fake = FakeAudioPlayer()
        let service = TourPlaybackService(audioPlayer: fake)
        let tour = makeTour(segmentCount: 0)

        await service.prepareTour(tour)

        #expect(service.audioReady == false)
        #expect(service.audioProgress.contains("No narration"))
        #expect(fake.setupForOnDemandCalls.isEmpty)
        #expect(fake.bufferFirstCount == 0)
    }

    @Test("prepareTour unblocks UI after bufferFirst, audioReady flips true")
    func unblocksAfterFirstSegment() async {
        TourPlaybackService.resetAudioUrlCacheForTesting()
        let fake = FakeAudioPlayer()
        fake.hasAudioFake = true
        let service = TourPlaybackService(audioPlayer: fake)

        await service.prepareTour(makeTour())

        #expect(service.audioReady == true)
        #expect(fake.setupForOnDemandCalls.count == 1)
        #expect(fake.bufferFirstCount == 1)
        #expect(service.audioProgress == "")
    }

    @Test("prepareTour kicks off background prefetch starting from segment 1")
    func backgroundPrefetchStartsFromOne() async {
        TourPlaybackService.resetAudioUrlCacheForTesting()
        let fake = FakeAudioPlayer()
        fake.hasAudioFake = true
        let service = TourPlaybackService(audioPlayer: fake)

        await service.prepareTour(makeTour())

        // Background task runs on the main actor; allow it to make progress.
        for _ in 0..<10 where fake.bufferFromIndices.isEmpty {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(fake.bufferFromIndices.contains(1))
    }

    @Test("prepareTour with audioReady false surfaces unavailable message")
    func audioUnavailableMessage() async {
        TourPlaybackService.resetAudioUrlCacheForTesting()
        let fake = FakeAudioPlayer()
        fake.hasAudioFake = false  // Simulate failed download/generation
        let service = TourPlaybackService(audioPlayer: fake)

        await service.prepareTour(makeTour())

        #expect(service.audioReady == false)
        #expect(service.audioProgress.contains("Audio unavailable"))
        #expect(fake.setupForOnDemandCalls.count == 1)
        #expect(fake.bufferFirstCount == 1)
    }

    @Test("prepareTour is idempotent when already prepared for same tour+engine")
    func idempotentWhenReady() async {
        TourPlaybackService.resetAudioUrlCacheForTesting()
        let fake = FakeAudioPlayer()
        fake.hasAudioFake = true
        let service = TourPlaybackService(audioPlayer: fake)

        await service.prepareTour(makeTour())
        await service.prepareTour(makeTour())

        // Second call should short-circuit — still only one setup
        #expect(fake.setupForOnDemandCalls.count == 1)
        #expect(fake.bufferFirstCount == 1)
    }

    @Test("stopTour cancels background prefetch and stops the player")
    func stopTourCancelsPrefetch() async {
        TourPlaybackService.resetAudioUrlCacheForTesting()
        let fake = FakeAudioPlayer()
        fake.hasAudioFake = true
        let service = TourPlaybackService(audioPlayer: fake)
        await service.prepareTour(makeTour())

        service.stopTour()

        #expect(fake.stopCalled >= 1)
        #expect(service.isActive == false)
        #expect(service.currentStopIndex == -1)
    }
}
