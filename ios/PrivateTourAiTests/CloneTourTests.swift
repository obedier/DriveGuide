import Testing
import Foundation
@testable import PrivateTourAi

// MARK: - Fixture

private func makeTour(id: String, title: String, isPublic: Bool = true, shareId: String? = "sid-\(UUID().uuidString.prefix(6))") -> Tour {
    var dict: [String: Any] = [
        "id": id,
        "title": title,
        "description": "fixture",
        "duration_minutes": 120,
        "themes": ["history"],
        "language": "en",
        "status": "ready",
        "transport_mode": "car",
        "is_public": isPublic,
        "stops": [[
            "id": "stop-0",
            "sequence_order": 0,
            "name": "Stop 0",
            "description": "",
            "category": "landmark",
            "latitude": 0.0, "longitude": 0.0,
            "recommended_stay_minutes": 5,
            "is_optional": false,
            "approach_narration": "", "at_stop_narration": "", "departure_narration": ""
        ]],
        "narration_segments": [],
        "created_at": "2026-04-19T00:00:00.000Z"
    ]
    if let shareId { dict["share_id"] = shareId }
    let data = try! JSONSerialization.data(withJSONObject: dict)
    return try! JSONDecoder().decode(Tour.self, from: data)
}

// MARK: - Tests

@Suite("TourViewModel — clone for editing")
@MainActor
struct CloneTourTests {

    @Test("isOwnedByCurrentUser returns false for a tour not in savedTours")
    func ownershipNegative() {
        let vm = TourViewModel()
        vm.savedTours = []
        let stranger = makeTour(id: "public-123", title: "Paris Classics")
        #expect(vm.isOwnedByCurrentUser(stranger) == false)
    }

    @Test("isOwnedByCurrentUser returns true for a tour already saved")
    func ownershipPositive() {
        let vm = TourViewModel()
        let mine = makeTour(id: "mine-123", title: "My Tour")
        vm.savedTours = [mine]
        #expect(vm.isOwnedByCurrentUser(mine) == true)
    }

    @Test("cloneTourForEditing assigns a new id, clears shareId, flips isPublic, prefixes title")
    func cloneAssignsNewIdentity() {
        let vm = TourViewModel()
        vm.savedTours = []
        let source = makeTour(id: "public-source", title: "Miami Deco Drive", isPublic: true)

        vm.cloneTourForEditing(source)

        guard let clone = vm.currentTour else {
            Issue.record("currentTour was not set after clone")
            return
        }
        #expect(clone.id != source.id)
        #expect(clone.id.hasPrefix("user-"))
        #expect(clone.shareId == nil)
        #expect(clone.isPublic == false)
        #expect(clone.title == "My Miami Deco Drive")
        #expect(vm.showTourDetail == true)
    }

    @Test("cloning does not double-prefix already-My titles")
    func cloneNoDoublePrefix() {
        let vm = TourViewModel()
        vm.savedTours = []
        let source = makeTour(id: "public-x", title: "My Own Route")

        vm.cloneTourForEditing(source)

        #expect(vm.currentTour?.title == "My Own Route")
    }

    @Test("cloning preserves stops + narration segments structurally")
    func clonePreservesContent() {
        let vm = TourViewModel()
        vm.savedTours = []
        let source = makeTour(id: "public-y", title: "NYC Highlights")

        vm.cloneTourForEditing(source)

        #expect(vm.currentTour?.stops.count == source.stops.count)
        #expect(vm.currentTour?.stops.first?.name == source.stops.first?.name)
    }

    @Test("after clone, isOwnedByCurrentUser flips true")
    func postCloneOwnership() {
        let vm = TourViewModel()
        vm.savedTours = []
        let source = makeTour(id: "public-z", title: "LA Cruise")

        vm.cloneTourForEditing(source)

        guard let clone = vm.currentTour else {
            Issue.record("clone missing")
            return
        }
        #expect(vm.isOwnedByCurrentUser(clone) == true)
    }
}
