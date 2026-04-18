import Testing
import CoreLocation
@testable import PrivateTourAi

// MARK: - Stub location provider for testing MetroLookupState transitions

final class StubLocationProvider: MetroLocationProviding, @unchecked Sendable {
    var authorizationStatus: CLAuthorizationStatus
    var locationToReturn: CLLocation?
    var countryToReturn: String?
    var requestAuthCalled = false

    init(
        authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse,
        location: CLLocation? = nil,
        country: String? = "US"
    ) {
        self.authorizationStatus = authorizationStatus
        self.locationToReturn = location
        self.countryToReturn = country
    }

    func requestWhenInUseAuthorizationIfNeeded() { requestAuthCalled = true }
    func currentLocation() async -> CLLocation? { locationToReturn }
    func countryCode(for location: CLLocation) async -> String? { countryToReturn }
}

@Suite("Metro Area Service")
@MainActor
struct MetroAreaServiceTests {

    // MARK: - Data loading

    @Test("Bundled JSON loads at least 60 metros")
    func jsonLoads() {
        let service = MetroAreaService(locationProvider: StubLocationProvider())
        let miami = CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
        let near = service.nearestMetros(to: miami, inCountry: "US", count: 100)
        #expect(near.count >= 60, "Expected at least 60 US metros in bundled data")
    }

    @Test("MetroArea id is unique per metro")
    func idsUnique() {
        let service = MetroAreaService(locationProvider: StubLocationProvider())
        let anywhere = CLLocationCoordinate2D(latitude: 40.0, longitude: -100.0)
        let all = service.nearestMetros(to: anywhere, inCountry: "US", count: 100)
        let ids = all.map { $0.metro.id }
        #expect(Set(ids).count == ids.count, "Duplicate metro ids found")
    }

    // MARK: - Distance sorting

    @Test("Nearest to Miami surfaces Miami first")
    func nearestToMiami() {
        let service = MetroAreaService(locationProvider: StubLocationProvider())
        let miami = CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
        let top3 = service.nearestMetros(to: miami, inCountry: "US", count: 3)
        #expect(top3.count == 3)
        #expect(top3[0].metro.name == "Miami")
        #expect(top3[0].distanceMiles < 10, "Miami should be ~0 mi from Miami")
    }

    @Test("Nearest to Weston FL includes Miami / Fort Lauderdale / West Palm Beach")
    func nearestToWeston() {
        let service = MetroAreaService(locationProvider: StubLocationProvider())
        let weston = CLLocationCoordinate2D(latitude: 26.1003, longitude: -80.3995)
        let top3 = service.nearestMetros(to: weston, inCountry: "US", count: 3)
        #expect(top3.count == 3)
        let names = Set(top3.map { $0.metro.name })
        #expect(names.contains("Fort Lauderdale") || names.contains("Miami"))
    }

    @Test("Nearest to Seattle includes Seattle + Portland")
    func nearestToSeattle() {
        let service = MetroAreaService(locationProvider: StubLocationProvider())
        let seattle = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        let top3 = service.nearestMetros(to: seattle, inCountry: "US", count: 3)
        #expect(top3[0].metro.name == "Seattle")
        let names = Set(top3.map { $0.metro.name })
        #expect(names.contains("Portland"))
    }

    @Test("Distance computation is roughly correct (Miami to New York ~1090 mi)")
    func distanceIsReasonable() {
        let service = MetroAreaService(locationProvider: StubLocationProvider())
        let miami = CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
        let all = service.nearestMetros(to: miami, inCountry: "US", count: 100)
        guard let ny = all.first(where: { $0.metro.name == "New York" }) else {
            Issue.record("New York not in results")
            return
        }
        #expect(ny.distanceMiles > 900 && ny.distanceMiles < 1300)
    }

    // MARK: - State machine coverage

    @Test("resolve → permissionDenied when auth denied")
    func stateIsPermissionDenied() async {
        let stub = StubLocationProvider(authorizationStatus: .denied)
        let service = MetroAreaService(locationProvider: stub)
        await service.resolve(count: 10)
        if case .permissionDenied = service.state { } else {
            Issue.record("Expected permissionDenied, got \(service.state)")
        }
    }

    @Test("resolve → permissionDenied when auth restricted")
    func stateIsPermissionDeniedWhenRestricted() async {
        let stub = StubLocationProvider(authorizationStatus: .restricted)
        let service = MetroAreaService(locationProvider: stub)
        await service.resolve(count: 10)
        if case .permissionDenied = service.state { } else {
            Issue.record("Expected permissionDenied, got \(service.state)")
        }
    }

    @Test("resolve → locationUnavailable when location times out")
    func stateIsLocationUnavailable() async {
        let stub = StubLocationProvider(authorizationStatus: .authorizedWhenInUse, location: nil)
        let service = MetroAreaService(locationProvider: stub)
        await service.resolve(count: 10)
        if case .locationUnavailable = service.state { } else {
            Issue.record("Expected locationUnavailable, got \(service.state)")
        }
    }

    @Test("resolve → loaded with US metros sorted by distance")
    func stateIsLoadedUS() async {
        let miami = CLLocation(latitude: 25.7617, longitude: -80.1918)
        let stub = StubLocationProvider(location: miami, country: "US")
        let service = MetroAreaService(locationProvider: stub)
        await service.resolve(count: 3)
        guard case let .loaded(metros, fallback) = service.state else {
            Issue.record("Expected loaded, got \(service.state)"); return
        }
        #expect(fallback == false)
        #expect(metros.count == 3)
        #expect(metros[0].metro.name == "Miami")
    }

    @Test("resolve → loaded with fallback flag when user is outside curated countries")
    func stateIsLoadedFallback() async {
        // Location in France, no French metros in the bundled JSON
        let paris = CLLocation(latitude: 48.8566, longitude: 2.3522)
        let stub = StubLocationProvider(location: paris, country: "FR")
        let service = MetroAreaService(locationProvider: stub)
        await service.resolve(count: 3)
        guard case let .loaded(metros, fallback) = service.state else {
            Issue.record("Expected loaded, got \(service.state)"); return
        }
        #expect(fallback == true)
        #expect(metros.count == 3)
    }

    @Test("resolve calls requestAuthorization when status is notDetermined")
    func requestsAuthOnNotDetermined() async {
        let stub = StubLocationProvider(authorizationStatus: .notDetermined, location: nil)
        let service = MetroAreaService(locationProvider: stub)
        await service.resolve(count: 3)
        #expect(stub.requestAuthCalled == true)
    }
}
