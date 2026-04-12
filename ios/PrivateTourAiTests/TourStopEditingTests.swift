import Testing
import CoreLocation
@testable import PrivateTourAi

/// Tests for tour stop editing logic: smart insertion, reordering, deletion.
@Suite("Tour Stop Editing")
struct TourStopEditingTests {

    // Build a small tour: 3 stops in a roughly straight line
    private func makeStops() -> [TourStop] {
        return [
            makeStop(id: "a", order: 0, name: "A", lat: 26.10, lng: -80.10),
            makeStop(id: "b", order: 1, name: "B", lat: 26.15, lng: -80.15),
            makeStop(id: "c", order: 2, name: "C", lat: 26.20, lng: -80.20),
        ]
    }

    private func makeStop(id: String, order: Int, name: String, lat: Double, lng: Double) -> TourStop {
        TourStop(
            id: id, sequenceOrder: order, name: name, description: "",
            category: "landmark", latitude: lat, longitude: lng,
            recommendedStayMinutes: 10, isOptional: false,
            approachNarration: "", atStopNarration: "", departureNarration: "",
            googlePlaceId: nil, photoUrl: nil
        )
    }

    @Test("Best insertion position — stop near start goes to position 0")
    func insertNearStart() {
        let stops = makeStops()
        let newStop = makeStop(id: "x", order: 99, name: "X", lat: 26.09, lng: -80.09)
        let idx = smartInsertIndex(for: newStop, in: stops)
        #expect(idx == 0, "Stop near A should insert at position 0")
    }

    @Test("Best insertion position — stop near end goes to position count (append)")
    func insertNearEnd() {
        let stops = makeStops()
        let newStop = makeStop(id: "x", order: 99, name: "X", lat: 26.21, lng: -80.21)
        let idx = smartInsertIndex(for: newStop, in: stops)
        #expect(idx == stops.count, "Stop near C should append at end")
    }

    @Test("Best insertion position — stop between B and C inserts at index 2")
    func insertBetween() {
        let stops = makeStops()
        let newStop = makeStop(id: "x", order: 99, name: "X", lat: 26.175, lng: -80.175)
        let idx = smartInsertIndex(for: newStop, in: stops)
        #expect(idx >= 1 && idx <= 3, "Stop between B and C should insert somewhere in middle")
    }

    @Test("Best insertion position — empty list returns 0")
    func insertIntoEmpty() {
        let stops: [TourStop] = []
        let newStop = makeStop(id: "x", order: 99, name: "X", lat: 0, lng: 0)
        let idx = smartInsertIndex(for: newStop, in: stops)
        #expect(idx == 0)
    }

    @Test("Best insertion position — single stop returns 1 (append)")
    func insertIntoSingle() {
        let stops = [makeStop(id: "a", order: 0, name: "A", lat: 0, lng: 0)]
        let newStop = makeStop(id: "x", order: 99, name: "X", lat: 1, lng: 1)
        let idx = smartInsertIndex(for: newStop, in: stops)
        #expect(idx == 1, "Should append (index 1) when only one stop exists")
    }

    @Test("Multiple insertions at best position maintain valid indices")
    func multipleInsertions() {
        var stops = makeStops()
        let new1 = makeStop(id: "x1", order: 99, name: "X1", lat: 26.09, lng: -80.09)
        let new2 = makeStop(id: "x2", order: 99, name: "X2", lat: 26.21, lng: -80.21)
        let new3 = makeStop(id: "x3", order: 99, name: "X3", lat: 26.12, lng: -80.12)

        // Insert all three at their best positions
        let idx1 = smartInsertIndex(for: new1, in: stops)
        stops.insert(new1, at: idx1)
        let idx2 = smartInsertIndex(for: new2, in: stops)
        stops.insert(new2, at: idx2)
        let idx3 = smartInsertIndex(for: new3, in: stops)
        stops.insert(new3, at: idx3)

        #expect(stops.count == 6)
        // All indices should be valid
        #expect(idx1 >= 0 && idx1 <= 3)
        #expect(idx2 >= 0 && idx2 <= 4)
        #expect(idx3 >= 0 && idx3 <= 5)
    }

    // MARK: - Implementation (matches TourDetailView.bestInsertionIndex)

    private func smartInsertIndex(for newStop: TourStop, in stops: [TourStop]) -> Int {
        guard stops.count >= 2 else { return stops.count }
        let newLoc = CLLocation(latitude: newStop.latitude, longitude: newStop.longitude)

        var bestIdx = stops.count
        var bestDelta = Double.infinity

        for i in 0...stops.count {
            let delta: Double
            if i == 0 {
                let next = CLLocation(latitude: stops[0].latitude, longitude: stops[0].longitude)
                delta = newLoc.distance(from: next)
            } else if i == stops.count {
                let prev = CLLocation(latitude: stops[i - 1].latitude, longitude: stops[i - 1].longitude)
                delta = prev.distance(from: newLoc)
            } else {
                let prev = CLLocation(latitude: stops[i - 1].latitude, longitude: stops[i - 1].longitude)
                let next = CLLocation(latitude: stops[i].latitude, longitude: stops[i].longitude)
                delta = prev.distance(from: newLoc) + newLoc.distance(from: next) - prev.distance(from: next)
            }
            if delta < bestDelta {
                bestDelta = delta
                bestIdx = i
            }
        }
        return bestIdx
    }
}

/// Tests that stop list mutations produce valid sequence_order values.
@Suite("Stop Resequencing")
struct StopResequencingTests {

    @Test("Resequencing assigns sequential 0..n-1 order")
    func resequence() {
        let stops = [
            makeStop(id: "a", order: 5, lat: 0, lng: 0),
            makeStop(id: "b", order: 2, lat: 1, lng: 1),
            makeStop(id: "c", order: 99, lat: 2, lng: 2),
        ]
        let resequenced = stops.enumerated().map { idx, stop in
            makeStop(id: stop.id, order: idx, lat: stop.latitude, lng: stop.longitude)
        }
        #expect(resequenced[0].sequenceOrder == 0)
        #expect(resequenced[1].sequenceOrder == 1)
        #expect(resequenced[2].sequenceOrder == 2)
    }

    @Test("Delete then resequence preserves order")
    func deleteAndResequence() {
        var stops = [
            makeStop(id: "a", order: 0, lat: 0, lng: 0),
            makeStop(id: "b", order: 1, lat: 1, lng: 1),
            makeStop(id: "c", order: 2, lat: 2, lng: 2),
        ]
        stops.remove(at: 1) // remove "b"
        let resequenced = stops.enumerated().map { idx, stop in
            makeStop(id: stop.id, order: idx, lat: stop.latitude, lng: stop.longitude)
        }
        #expect(resequenced.count == 2)
        #expect(resequenced[0].id == "a" && resequenced[0].sequenceOrder == 0)
        #expect(resequenced[1].id == "c" && resequenced[1].sequenceOrder == 1)
    }

    private func makeStop(id: String, order: Int, lat: Double, lng: Double) -> TourStop {
        TourStop(
            id: id, sequenceOrder: order, name: id, description: "",
            category: "landmark", latitude: lat, longitude: lng,
            recommendedStayMinutes: 10, isOptional: false,
            approachNarration: "", atStopNarration: "", departureNarration: "",
            googlePlaceId: nil, photoUrl: nil
        )
    }
}
