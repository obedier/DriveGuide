import Testing
import Foundation
@testable import PrivateTourAi

// MARK: - Fixtures

private func makeTour(id: String = "offline-tour-\(UUID().uuidString.prefix(6))",
                     segmentCount: Int = 3) -> Tour {
    let stops: [[String: Any]] = (0..<max(segmentCount, 1)).map { i in
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
            "content_hash": "hash-\(id)-\(i)",
            "estimated_duration_seconds": 30,
            "trigger_radius_meters": 50.0,
            "language": "en"
        ]
    }
    let dict: [String: Any] = [
        "id": id,
        "title": "Offline Fixture",
        "description": "test",
        "duration_minutes": 60,
        "themes": ["history"],
        "language": "en",
        "status": "ready",
        "transport_mode": "car",
        "stops": stops,
        "narration_segments": segments,
        "created_at": "2026-04-19T00:00:00.000Z"
    ]
    let data = try! JSONSerialization.data(withJSONObject: dict)
    return try! JSONDecoder().decode(Tour.self, from: data)
}

private func tempRoot() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("OfflineTourStoreTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func fakeAudio(size: Int = 1024, byte: UInt8 = 0x42) -> Data {
    Data(repeating: byte, count: size)
}

// MARK: - Tests

@Suite("OfflineTourStore")
struct OfflineTourStoreTests {

    @Test("saveTour persists tour.json, manifest, and one audio file per segment")
    func saveRoundTrip() async throws {
        let store = OfflineTourStore(root: tempRoot())
        let tour = makeTour(segmentCount: 3)
        let audio: [String: Data] = Dictionary(uniqueKeysWithValues: tour.narrationSegments.map {
            ($0.contentHash, fakeAudio(size: 2048))
        })

        try await store.saveTour(tour, audioByContentHash: audio,
                                 voiceEngine: "google", voicePreference: "premium")

        #expect(await store.isDownloaded(tourId: tour.id) == true)
        let manifest = try await store.manifest(for: tour.id)
        #expect(manifest.tourId == tour.id)
        #expect(manifest.segments.count == 3)
        #expect(manifest.totalBytes == 6144)
        #expect(manifest.voiceEngine == "google")

        let reloaded = try await store.loadTour(tourId: tour.id)
        #expect(reloaded.id == tour.id)
        #expect(reloaded.narrationSegments.count == 3)
    }

    @Test("audioData is addressable by contentHash across reloads")
    func audioDataAddressable() async throws {
        let root = tempRoot()
        let tour = makeTour(segmentCount: 2)
        let payload1 = fakeAudio(byte: 0xAA)
        let payload2 = fakeAudio(byte: 0xBB)
        let audio: [String: Data] = [
            tour.narrationSegments[0].contentHash: payload1,
            tour.narrationSegments[1].contentHash: payload2
        ]

        do {
            let store = OfflineTourStore(root: root)
            try await store.saveTour(tour, audioByContentHash: audio,
                                     voiceEngine: "google", voicePreference: "premium")
        }

        // Simulate app relaunch: new store instance pointing at the same dir
        let store2 = OfflineTourStore(root: root)
        let got1 = await store2.audioData(tourId: tour.id, contentHash: tour.narrationSegments[0].contentHash)
        let got2 = await store2.audioData(tourId: tour.id, contentHash: tour.narrationSegments[1].contentHash)
        #expect(got1 == payload1)
        #expect(got2 == payload2)
    }

    @Test("allAudioData returns bytes in segment order, empty Data for gaps")
    func allAudioDataPreservesOrder() async throws {
        let store = OfflineTourStore(root: tempRoot())
        let tour = makeTour(segmentCount: 3)
        // Only persist segment 0 and 2 — segment 1 missing to simulate a partial download.
        let audio: [String: Data] = [
            tour.narrationSegments[0].contentHash: fakeAudio(byte: 0x01),
            tour.narrationSegments[2].contentHash: fakeAudio(byte: 0x03)
        ]
        try await store.saveTour(tour, audioByContentHash: audio,
                                 voiceEngine: "google", voicePreference: "premium")

        let ordered = await store.allAudioData(for: tour)
        #expect(ordered.count == 3)
        #expect(ordered[0].first == 0x01)
        #expect(ordered[1].isEmpty)
        #expect(ordered[2].first == 0x03)
    }

    @Test("saveTour skips audio below the 100-byte playable threshold")
    func skipsTinyAudio() async throws {
        let store = OfflineTourStore(root: tempRoot())
        let tour = makeTour(segmentCount: 2)
        let audio: [String: Data] = [
            tour.narrationSegments[0].contentHash: fakeAudio(size: 50),   // too small
            tour.narrationSegments[1].contentHash: fakeAudio(size: 2048)
        ]
        try await store.saveTour(tour, audioByContentHash: audio,
                                 voiceEngine: "google", voicePreference: "premium")

        let manifest = try await store.manifest(for: tour.id)
        #expect(manifest.segments.count == 1)
        #expect(manifest.segments.first?.index == 1)
    }

    @Test("isDownloaded is false before save, true after, false after delete")
    func downloadLifecycle() async throws {
        let store = OfflineTourStore(root: tempRoot())
        let tour = makeTour(segmentCount: 1)
        #expect(await store.isDownloaded(tourId: tour.id) == false)

        try await store.saveTour(tour,
                                 audioByContentHash: [tour.narrationSegments[0].contentHash: fakeAudio()],
                                 voiceEngine: "google", voicePreference: "premium")
        #expect(await store.isDownloaded(tourId: tour.id) == true)

        try await store.delete(tourId: tour.id)
        #expect(await store.isDownloaded(tourId: tour.id) == false)
    }

    @Test("allDownloadedManifests lists tours newest-first")
    func listNewestFirst() async throws {
        let store = OfflineTourStore(root: tempRoot())
        let a = makeTour(id: "a", segmentCount: 1)
        let b = makeTour(id: "b", segmentCount: 1)

        try await store.saveTour(a,
                                 audioByContentHash: [a.narrationSegments[0].contentHash: fakeAudio()],
                                 voiceEngine: "google", voicePreference: "premium")
        // Tiny delay so download timestamps differ measurably
        try await Task.sleep(for: .milliseconds(20))
        try await store.saveTour(b,
                                 audioByContentHash: [b.narrationSegments[0].contentHash: fakeAudio()],
                                 voiceEngine: "google", voicePreference: "premium")

        let manifests = await store.allDownloadedManifests()
        #expect(manifests.count == 2)
        #expect(manifests.first?.tourId == "b")
        #expect(manifests.last?.tourId == "a")
    }

    @Test("evictIfOverBudget drops oldest until under cap")
    func evictionKeepsNewest() async throws {
        let store = OfflineTourStore(root: tempRoot())
        let a = makeTour(id: "a-evict", segmentCount: 1)
        let b = makeTour(id: "b-evict", segmentCount: 1)

        // Each tour ~2KB on disk. Set cap to 3KB so one must be evicted.
        try await store.saveTour(a,
                                 audioByContentHash: [a.narrationSegments[0].contentHash: fakeAudio(size: 2000)],
                                 voiceEngine: "google", voicePreference: "premium")
        try await Task.sleep(for: .milliseconds(20))
        try await store.saveTour(b,
                                 audioByContentHash: [b.narrationSegments[0].contentHash: fakeAudio(size: 2000)],
                                 voiceEngine: "google", voicePreference: "premium")

        let removed = await store.evictIfOverBudget(maxBytes: 3000)
        #expect(removed == ["a-evict"])
        #expect(await store.isDownloaded(tourId: "a-evict") == false)
        #expect(await store.isDownloaded(tourId: "b-evict") == true)
    }

    @Test("loadTour on a missing tour throws notDownloaded")
    func loadMissingTourThrows() async {
        let store = OfflineTourStore(root: tempRoot())
        await #expect(throws: OfflineTourStore.OfflineError.self) {
            _ = try await store.loadTour(tourId: "does-not-exist")
        }
    }
}
