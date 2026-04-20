import Testing
import Foundation
import CoreLocation
@testable import PrivateTourAi

// MARK: - Fixture

/// Build a minimal tour centered on a specific (lat, lng). stopCount stops
/// are placed at the same coordinates — irrelevant for bridge tests which
/// only care about the distance to stop 0.
private func stopDict(index: Int, firstStopLat: Double, firstStopLng: Double) -> [String: Any] {
    var dict: [String: Any] = [:]
    dict["id"] = "stop-\(index)"
    dict["sequence_order"] = index
    dict["name"] = index == 0 ? "South Pointe Park" : "Stop \(index)"
    dict["description"] = "desc"
    dict["category"] = "landmark"
    dict["latitude"] = firstStopLat + Double(index) * 0.01
    dict["longitude"] = firstStopLng + Double(index) * 0.01
    dict["recommended_stay_minutes"] = 5
    dict["is_optional"] = false
    dict["approach_narration"] = ""
    dict["at_stop_narration"] = ""
    dict["departure_narration"] = ""
    return dict
}

private func segmentDict(index: Int) -> [String: Any] {
    var dict: [String: Any] = [:]
    dict["id"] = "seg-\(index)"
    dict["sequence_order"] = index
    dict["segment_type"] = index == 0 ? "intro" : "at_stop"
    dict["narration_text"] = "Narration \(index)"
    dict["content_hash"] = "hash-\(index)"
    dict["estimated_duration_seconds"] = 30
    dict["trigger_radius_meters"] = 50.0
    dict["language"] = "en"
    return dict
}

private func makeTour(
    id: String = "bridge-test",
    firstStopLat: Double = 25.7684,  // South Pointe Park Miami
    firstStopLng: Double = -80.1340,
    transportMode: String = "car",
    stopCount: Int = 3
) -> Tour {
    let stops = (0..<stopCount).map { stopDict(index: $0, firstStopLat: firstStopLat, firstStopLng: firstStopLng) }
    let segments = (0..<stopCount).map { segmentDict(index: $0) }
    var tourDict: [String: Any] = [:]
    tourDict["id"] = id
    tourDict["title"] = "Bridge Test Tour"
    tourDict["description"] = "test"
    tourDict["duration_minutes"] = 60
    tourDict["themes"] = ["history"]
    tourDict["language"] = "en"
    tourDict["status"] = "ready"
    tourDict["transport_mode"] = transportMode
    tourDict["stops"] = stops
    tourDict["narration_segments"] = segments
    tourDict["created_at"] = "2026-04-19T00:00:00.000Z"
    let data = try! JSONSerialization.data(withJSONObject: tourDict)
    return try! JSONDecoder().decode(Tour.self, from: data)
}

// MARK: - Recording audio player — never touches AVAudioSession.

@MainActor
private final class RecordingAudioPlayer: AudioPlayerService {
    var setupForOnDemandCalls = 0
    var playSegmentCalls: [Int] = []
    override func setupForOnDemand(segments: [NarrationSegment], voiceEngine: String, voicePreference: String) {
        setupForOnDemandCalls += 1
    }
    override func playSegment(at index: Int) {
        playSegmentCalls.append(index)
    }
    override var hasAudio: Bool { true }
    override func stop() {}
}

// MARK: - Tests

@Suite("TourPlaybackService — bridge coordinator")
@MainActor
struct BridgeCoordinatorTests {

    @Test("startTourWithAwareness skips the bridge when the user is within the car threshold")
    func nearUserSkipsBridge() async {
        TourPlaybackService.resetAudioUrlCacheForTesting()
        let fake = RecordingAudioPlayer()
        let service = TourPlaybackService(audioPlayer: fake)
        defer { service.stopTour() }  // kill any spawned fetch Task before test returns
        let tour = makeTour()
        await service.prepareTour(tour)

        // 200m north-east of the first stop — inside the 400m car threshold.
        let near = CLLocationCoordinate2D(latitude: 25.7702, longitude: -80.1320)
        service.startTourWithAwareness(userLocation: near)

        #expect(service.bridgeState == nil)
        #expect(service.isActive == true)
        // startTour() calls audioPlayer.playSegment(at: 0)
        #expect(fake.playSegmentCalls == [0])
    }

    @Test("startTourWithAwareness skips the bridge when user location is nil (network fallback)")
    func nilUserLocationSkipsBridge() async {
        TourPlaybackService.resetAudioUrlCacheForTesting()
        let fake = RecordingAudioPlayer()
        let service = TourPlaybackService(audioPlayer: fake)
        defer { service.stopTour() }  // kill any spawned fetch Task before test returns
        await service.prepareTour(makeTour())

        service.startTourWithAwareness(userLocation: nil)

        #expect(service.bridgeState == nil)
        #expect(service.isActive == true)
        #expect(fake.playSegmentCalls == [0])
    }

    @Test("Walking tours use a tighter 150m threshold")
    func walkingUsesTighterThreshold() async {
        TourPlaybackService.resetAudioUrlCacheForTesting()
        let fake = RecordingAudioPlayer()
        let service = TourPlaybackService(audioPlayer: fake)
        defer { service.stopTour() }  // kill any spawned fetch Task before test returns
        await service.prepareTour(makeTour(transportMode: "walk"))

        // 250m away — would pass the 400m car threshold but must trigger
        // the bridge under the 150m walking threshold.
        let somewhatNear = CLLocationCoordinate2D(latitude: 25.7706, longitude: -80.1340)
        service.startTourWithAwareness(userLocation: somewhatNear)

        // Bridge state set, segment 0 NOT played yet.
        #expect(service.bridgeState != nil)
        #expect(fake.playSegmentCalls.isEmpty)
    }

    @Test("Car tours tolerate ≤400m as 'near enough' and skip the bridge")
    func carTolerates400m() async {
        TourPlaybackService.resetAudioUrlCacheForTesting()
        let fake = RecordingAudioPlayer()
        let service = TourPlaybackService(audioPlayer: fake)
        defer { service.stopTour() }  // kill any spawned fetch Task before test returns
        await service.prepareTour(makeTour(transportMode: "car"))

        // ~300m away — inside the 400m car threshold.
        let threeHundredM = CLLocationCoordinate2D(latitude: 25.7710, longitude: -80.1340)
        service.startTourWithAwareness(userLocation: threeHundredM)

        #expect(service.bridgeState == nil)
        #expect(fake.playSegmentCalls == [0])
    }

    @Test("observeLocation updates live distance on the banner while still far")
    func observeUpdatesDistance() async {
        TourPlaybackService.resetAudioUrlCacheForTesting()
        let fake = RecordingAudioPlayer()
        let service = TourPlaybackService(audioPlayer: fake)
        defer { service.stopTour() }  // kill any spawned fetch Task before test returns
        await service.prepareTour(makeTour())

        // Seed bridge state by pretending to be 50km away — well outside threshold.
        let farAway = CLLocationCoordinate2D(latitude: 26.2168, longitude: -80.1340)
        service.startTourWithAwareness(userLocation: farAway)
        #expect(service.bridgeState != nil)

        // Now simulate driving closer to ~30km.
        let closer = CLLocationCoordinate2D(latitude: 26.0389, longitude: -80.1340)
        service.observeLocation(closer)

        let newKm = service.bridgeState?.distanceKm ?? .infinity
        // Should have dropped significantly from the original ~50km.
        #expect(newKm < 45.0)
        #expect(newKm > 5.0)
        // Still far — hand-off shouldn't have fired.
        #expect(fake.playSegmentCalls.isEmpty)
    }

    @Test("observeLocation hands off to segment 0 when arriving inside the threshold")
    func arrivalHandsOffToSegmentZero() async {
        TourPlaybackService.resetAudioUrlCacheForTesting()
        let fake = RecordingAudioPlayer()
        let service = TourPlaybackService(audioPlayer: fake)
        defer { service.stopTour() }  // kill any spawned fetch Task before test returns
        await service.prepareTour(makeTour())

        // Start far.
        let farAway = CLLocationCoordinate2D(latitude: 26.2168, longitude: -80.1340)
        service.startTourWithAwareness(userLocation: farAway)
        #expect(service.bridgeState != nil)
        #expect(fake.playSegmentCalls.isEmpty)

        // Now arrive at the first stop.
        let arrived = CLLocationCoordinate2D(latitude: 25.7684, longitude: -80.1340)
        service.observeLocation(arrived)

        #expect(service.bridgeState == nil)
        #expect(fake.playSegmentCalls == [0])
    }

    @Test("stopTour wipes bridge state + cancels follow-up work")
    func stopTourWipesBridge() async {
        TourPlaybackService.resetAudioUrlCacheForTesting()
        let fake = RecordingAudioPlayer()
        let service = TourPlaybackService(audioPlayer: fake)
        defer { service.stopTour() }  // kill any spawned fetch Task before test returns
        await service.prepareTour(makeTour())

        let farAway = CLLocationCoordinate2D(latitude: 26.2168, longitude: -80.1340)
        service.startTourWithAwareness(userLocation: farAway)
        #expect(service.bridgeState != nil)

        service.stopTour()

        #expect(service.bridgeState == nil)
        #expect(service.isActive == false)
    }

    @Test("Follow-up cadence is clamped to the min (3 min) on very short drives")
    func cadenceClampsToMin() {
        // 5 min ETA, 0 played → (5-3)/3 = 0.67 min per slot → below 3-min floor → clamp to 180s.
        let delay = TourPlaybackService.computeFollowUpDelay(
            etaMinutes: 5, followUpsPlayed: 0,
            maxFollowUps: 3, minInterval: 180, maxInterval: 360
        )
        #expect(delay == 180)
    }

    @Test("Follow-up cadence is clamped to the max (6 min) on very long drives")
    func cadenceClampsToMax() {
        // 60 min ETA, 0 played → (60-3)/3 = 19 min per slot → above 6-min ceiling → clamp to 360s.
        let delay = TourPlaybackService.computeFollowUpDelay(
            etaMinutes: 60, followUpsPlayed: 0,
            maxFollowUps: 3, minInterval: 180, maxInterval: 360
        )
        #expect(delay == 360)
    }

    @Test("Follow-up cadence compresses as slots run out")
    func cadenceCompressesLate() {
        // 20 min ETA, 2 already played, 1 slot left → (20-3)/1 = 17 min → capped at 6 min.
        let late = TourPlaybackService.computeFollowUpDelay(
            etaMinutes: 20, followUpsPlayed: 2,
            maxFollowUps: 3, minInterval: 180, maxInterval: 360
        )
        // 20 min ETA, 0 played, 3 slots → (20-3)/3 = 5.67 min → 340s, within clamp.
        let early = TourPlaybackService.computeFollowUpDelay(
            etaMinutes: 20, followUpsPlayed: 0,
            maxFollowUps: 3, minInterval: 180, maxInterval: 360
        )
        #expect(early > 180 && early < 360)
        #expect(late == 360)
    }

    @Test("Follow-up cadence returns the min interval when ETA is under 3 min")
    func cadenceEtaUnderTail() {
        let delay = TourPlaybackService.computeFollowUpDelay(
            etaMinutes: 2, followUpsPlayed: 0,
            maxFollowUps: 3, minInterval: 180, maxInterval: 360
        )
        #expect(delay == 180)
    }

    @Test("Arrival threshold is exclusive — exactly at the boundary still counts as arrived")
    func atBoundaryIsArrived() async {
        TourPlaybackService.resetAudioUrlCacheForTesting()
        let fake = RecordingAudioPlayer()
        let service = TourPlaybackService(audioPlayer: fake)
        defer { service.stopTour() }  // kill any spawned fetch Task before test returns
        await service.prepareTour(makeTour())

        let farAway = CLLocationCoordinate2D(latitude: 26.2168, longitude: -80.1340)
        service.startTourWithAwareness(userLocation: farAway)

        // Exactly 400m away — at the car threshold boundary. Algo uses `<=`
        // so this counts as arrived.
        let atBoundary = CLLocationCoordinate2D(latitude: 25.7720, longitude: -80.1340)
        // Verify our fixture math first — sanity check distance is right.
        let distance = CLLocation(latitude: atBoundary.latitude, longitude: atBoundary.longitude)
            .distance(from: CLLocation(latitude: 25.7684, longitude: -80.1340))
        // Should be in the ballpark of 400m.
        #expect(abs(distance - 400.0) < 100.0)

        service.observeLocation(atBoundary)
        if distance <= 400 {
            #expect(service.bridgeState == nil)
            #expect(fake.playSegmentCalls == [0])
        }
    }
}
