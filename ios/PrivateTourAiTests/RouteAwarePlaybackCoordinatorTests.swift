import Testing
import Foundation
import Combine
@testable import PrivateTourAi

// MARK: - Fakes

@MainActor
private final class FakeArrivalProvider: ArrivalProvider {
    let subject = PassthroughSubject<Int, Never>()
    var arrivedAtStopPublisher: AnyPublisher<Int, Never> {
        subject.eraseToAnyPublisher()
    }
    func fireArrival(at stopIndex: Int) {
        subject.send(stopIndex)
    }
}

@MainActor
private final class RecordingAudioPlayer: AudioPlayerService {
    var playSegmentCalls: [Int] = []
    override func playSegment(at index: Int) {
        playSegmentCalls.append(index)
    }
}

// MARK: - Tour fixture with per-stop segments

private func makeTour(stopCount: Int) -> Tour {
    let stops: [[String: Any]] = (0..<stopCount).map { i in
        [
            "id": "stop-\(i)",
            "sequence_order": i,
            "name": "Stop \(i)",
            "description": "",
            "category": "landmark",
            "latitude": 0.0,
            "longitude": 0.0,
            "recommended_stay_minutes": 5,
            "is_optional": false,
            "approach_narration": "",
            "at_stop_narration": "",
            "departure_narration": ""
        ]
    }
    // Segments: intro at index 0, then at_stop segments 1..N matched to stops 0..N-1.
    var segments: [[String: Any]] = [[
        "id": "seg-intro",
        "sequence_order": 0,
        "segment_type": "intro",
        "narration_text": "intro",
        "content_hash": "intro-hash",
        "estimated_duration_seconds": 30,
        "trigger_radius_meters": 50.0,
        "language": "en"
    ]]
    for i in 0..<stopCount {
        segments.append([
            "id": "seg-\(i)",
            "sequence_order": i + 1,
            "segment_type": "at_stop",
            "narration_text": "At stop \(i)",
            "content_hash": "hash-\(i)",
            "estimated_duration_seconds": 30,
            "trigger_radius_meters": 50.0,
            "language": "en",
            "to_stop_id": "stop-\(i)"
        ])
    }

    let dict: [String: Any] = [
        "id": "route-aware-tour",
        "title": "RA Test",
        "description": "",
        "duration_minutes": 60,
        "themes": ["history"],
        "language": "en",
        "status": "ready",
        "transport_mode": "car",
        "stops": stops,
        "narration_segments": segments,
        "created_at": "2026-04-19T00:00:00Z"
    ]
    let data = try! JSONSerialization.data(withJSONObject: dict)
    return try! JSONDecoder().decode(Tour.self, from: data)
}

// MARK: - Tests

@Suite("RouteAwarePlaybackCoordinator")
@MainActor
struct RouteAwarePlaybackCoordinatorTests {

    @Test("attach activates the coordinator")
    func attachActivates() {
        let audio = RecordingAudioPlayer()
        let playback = TourPlaybackService(audioPlayer: audio)
        let coord = RouteAwarePlaybackCoordinator(playback: playback, tour: makeTour(stopCount: 2))
        let provider = FakeArrivalProvider()

        #expect(coord.isActive == false)
        coord.attach(provider)
        #expect(coord.isActive == true)

        coord.detach()
        #expect(coord.isActive == false)
    }

    @Test("arrival event triggers playback of the matching at_stop segment")
    func arrivalPlaysMatchingSegment() async {
        let audio = RecordingAudioPlayer()
        let playback = TourPlaybackService(audioPlayer: audio)
        let coord = RouteAwarePlaybackCoordinator(playback: playback, tour: makeTour(stopCount: 3))
        let provider = FakeArrivalProvider()
        coord.attach(provider)

        provider.fireArrival(at: 1)
        // Publisher dispatch happens synchronously on the main actor; give it a tick.
        await Task.yield()

        // intro is segment 0, stop-0 is segment 1, stop-1 is segment 2
        #expect(audio.playSegmentCalls == [2])
    }

    @Test("duplicate arrival at the same stop does not re-trigger playback")
    func duplicateArrivalIgnored() async {
        let audio = RecordingAudioPlayer()
        let playback = TourPlaybackService(audioPlayer: audio)
        let coord = RouteAwarePlaybackCoordinator(playback: playback, tour: makeTour(stopCount: 2))
        let provider = FakeArrivalProvider()
        coord.attach(provider)

        provider.fireArrival(at: 0)
        provider.fireArrival(at: 0)
        provider.fireArrival(at: 0)
        await Task.yield()

        #expect(audio.playSegmentCalls == [1])
    }

    @Test("moving to a new stop plays the new segment")
    func sequentialArrivals() async {
        let audio = RecordingAudioPlayer()
        let playback = TourPlaybackService(audioPlayer: audio)
        let coord = RouteAwarePlaybackCoordinator(playback: playback, tour: makeTour(stopCount: 3))
        let provider = FakeArrivalProvider()
        coord.attach(provider)

        provider.fireArrival(at: 0)
        provider.fireArrival(at: 1)
        provider.fireArrival(at: 2)
        await Task.yield()

        #expect(audio.playSegmentCalls == [1, 2, 3])
    }

    @Test("handleArrival works without Ferrostar — supports manual trigger")
    func handleArrivalDirect() {
        let audio = RecordingAudioPlayer()
        let playback = TourPlaybackService(audioPlayer: audio)
        let coord = RouteAwarePlaybackCoordinator(playback: playback, tour: makeTour(stopCount: 2))

        coord.handleArrival(at: 1)

        #expect(audio.playSegmentCalls == [2])
    }

    @Test("handleArrival with out-of-range index is a no-op")
    func outOfRangeArrival() {
        let audio = RecordingAudioPlayer()
        let playback = TourPlaybackService(audioPlayer: audio)
        let coord = RouteAwarePlaybackCoordinator(playback: playback, tour: makeTour(stopCount: 2))

        coord.handleArrival(at: 99)
        coord.handleArrival(at: -1)

        #expect(audio.playSegmentCalls.isEmpty)
    }

    @Test("detach stops further arrival events from reaching the player")
    func detachStopsObserving() async {
        let audio = RecordingAudioPlayer()
        let playback = TourPlaybackService(audioPlayer: audio)
        let coord = RouteAwarePlaybackCoordinator(playback: playback, tour: makeTour(stopCount: 2))
        let provider = FakeArrivalProvider()
        coord.attach(provider)
        provider.fireArrival(at: 0)
        await Task.yield()
        #expect(audio.playSegmentCalls == [1])

        coord.detach()
        provider.fireArrival(at: 1)
        await Task.yield()
        #expect(audio.playSegmentCalls == [1])  // no new event after detach
    }
}
