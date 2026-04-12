import Testing
import CoreLocation
import FerrostarCore
import FerrostarCoreFFI
@testable import PrivateTourAi

/// Tests the OSRM route provider and Ferrostar integration.
@Suite("Ferrostar Integration")
struct FerrostarIntegrationTests {

    @Test("OSRMRouteProvider returns valid Ferrostar routes")
    func osrmRouteProviderWorks() async throws {
        let provider = OSRMRouteProvider()
        provider.profile = "driving"

        let userLoc = FerrostarCoreFFI.UserLocation(
            coordinates: GeographicCoordinate(lat: 26.0958, lng: -80.3831),
            horizontalAccuracy: 10,
            courseOverGround: CourseOverGround(degrees: 0, accuracy: 10),
            timestamp: Date(),
            speed: Speed(value: 0, accuracy: 0)
        )

        let waypoints = [
            Waypoint(
                coordinate: GeographicCoordinate(lat: 26.1003, lng: -80.3995),
                kind: .break
            )
        ]

        let routes = try await provider.getRoutes(userLocation: userLoc, waypoints: waypoints)
        #expect(!routes.isEmpty, "Should return at least one route")

        let route = routes[0]
        print("[Test] Route: \(route.geometry.count) points, \(route.steps.count) steps")
        #expect(route.geometry.count > 10, "Route should have geometry points")
        #expect(route.steps.count > 1, "Route should have steps")
        #expect(!route.steps[0].instruction.isEmpty, "Steps should have instructions")
        print("[Test] ✅ First step: \(route.steps[0].instruction)")
    }

    @Test("OSRMRouteProvider handles multiple waypoints for tour stops")
    func multipleWaypoints() async throws {
        let provider = OSRMRouteProvider()

        let userLoc = FerrostarCoreFFI.UserLocation(
            coordinates: GeographicCoordinate(lat: 26.0958, lng: -80.3831),
            horizontalAccuracy: 10,
            courseOverGround: CourseOverGround(degrees: 0, accuracy: 10),
            timestamp: Date(),
            speed: Speed(value: 0, accuracy: 0)
        )

        // 3 waypoints = 4 stops in a tour
        let waypoints = [
            Waypoint(coordinate: GeographicCoordinate(lat: 26.1003, lng: -80.3995), kind: .break),
            Waypoint(coordinate: GeographicCoordinate(lat: 26.0867, lng: -80.4013), kind: .break),
            Waypoint(coordinate: GeographicCoordinate(lat: 26.1168, lng: -80.3695), kind: .break)
        ]

        let routes = try await provider.getRoutes(userLocation: userLoc, waypoints: waypoints)
        #expect(!routes.isEmpty)
        print("[Test] ✅ Multi-waypoint route: \(routes[0].geometry.count) points, \(routes[0].steps.count) steps")
    }

    @Test("SimulatedLocationProvider can be set with tour stop location")
    func simulatedLocationProvider() {
        let sim = SimulatedLocationProvider()
        let loc = FerrostarCoreFFI.UserLocation(
            coordinates: GeographicCoordinate(lat: 26.0958, lng: -80.3831),
            horizontalAccuracy: 10,
            courseOverGround: CourseOverGround(degrees: 45, accuracy: 10),
            timestamp: Date(),
            speed: Speed(value: 10, accuracy: 5)
        )
        sim.lastLocation = loc
        #expect(sim.lastLocation != nil)
        #expect(sim.lastLocation?.coordinates.lat == 26.0958)
        print("[Test] ✅ SimulatedLocationProvider set correctly")
    }
}
