import Testing
import Foundation
@testable import PrivateTourAi

// MARK: - Fixtures

private func makeTour(id: String, createdAt: String) -> Tour {
    let dict: [String: Any] = [
        "id": id,
        "title": "Tour \(id)",
        "description": "desc",
        "duration_minutes": 60,
        "themes": ["history"],
        "language": "en",
        "status": "ready",
        "transport_mode": "car",
        "stops": [[
            "id": "s0",
            "sequence_order": 0,
            "name": "Stop",
            "description": "x",
            "category": "landmark",
            "latitude": 0.0,
            "longitude": 0.0,
            "recommended_stay_minutes": 5,
            "is_optional": false,
            "approach_narration": "",
            "at_stop_narration": "",
            "departure_narration": ""
        ]],
        "narration_segments": [],
        "created_at": createdAt
    ]
    let data = try! JSONSerialization.data(withJSONObject: dict)
    return try! JSONDecoder().decode(Tour.self, from: data)
}

private func isoNow(offsetHours: Double) -> String {
    let date = Date().addingTimeInterval(offsetHours * 3600)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

// MARK: - Tests

@Suite("TourViewModel.recentTour")
@MainActor
struct RecentTourTests {

    @Test("Returns nil when no saved tours exist")
    func noSavedTours() {
        let vm = TourViewModel()
        vm.savedTours = []
        vm.currentTour = nil
        vm.currentPreview = nil
        #expect(vm.recentTour == nil)
    }

    @Test("Returns the newest saved tour when created in the last 48 hours")
    func recentTourWithinWindow() {
        let vm = TourViewModel()
        vm.currentTour = nil
        vm.currentPreview = nil
        let fresh = makeTour(id: "fresh", createdAt: isoNow(offsetHours: -2))
        vm.savedTours = [fresh]
        #expect(vm.recentTour?.id == "fresh")
    }

    @Test("Returns nil when the newest tour is older than 48 hours")
    func olderThanWindow() {
        let vm = TourViewModel()
        vm.currentTour = nil
        vm.currentPreview = nil
        let stale = makeTour(id: "stale", createdAt: isoNow(offsetHours: -72))
        vm.savedTours = [stale]
        #expect(vm.recentTour == nil)
    }

    @Test("Returns nil when a tour is already active")
    func suppressedWhenTourActive() {
        let vm = TourViewModel()
        let recent = makeTour(id: "recent", createdAt: isoNow(offsetHours: -1))
        vm.savedTours = [recent]
        vm.currentTour = recent
        #expect(vm.recentTour == nil)
    }

    @Test("Still surfaces a tour when the timestamp is unparseable (fail-open)")
    func unparseableTimestampFallsOpen() {
        let vm = TourViewModel()
        vm.currentTour = nil
        vm.currentPreview = nil
        let weird = makeTour(id: "weird", createdAt: "not-a-timestamp")
        vm.savedTours = [weird]
        #expect(vm.recentTour?.id == "weird")
    }
}
