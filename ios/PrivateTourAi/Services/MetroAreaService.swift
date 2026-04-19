import Foundation
import CoreLocation

/// A major metro area with coordinates.
struct MetroArea: Codable, Identifiable, Equatable, Sendable {
    let name: String
    let state: String
    let country: String
    let lat: Double
    let lng: Double

    var id: String { "\(country)-\(state)-\(name)" }
    var displayName: String { "\(name), \(state)" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

private struct MetroAreasFile: Codable {
    let metros: [MetroArea]
}

/// Lookup result states. Drives the sheet UI explicitly so every branch has copy + recovery.
enum MetroLookupState: Equatable {
    case idle
    case loading
    case permissionDenied
    case locationUnavailable
    case loaded(metros: [MetroAreaService.MetroWithDistance], fallback: Bool)
    case empty
}

/// Source of the user's current location. Protocol so tests can substitute a stub.
protocol MetroLocationProviding: Sendable {
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorizationIfNeeded()
    func currentLocation() async -> CLLocation?
    func countryCode(for location: CLLocation) async -> String?
}

/// Service for finding the user's nearest major metro areas from a curated list.
/// Data is bundled with the app — works offline.
@MainActor
final class MetroAreaService: ObservableObject {
    @Published private(set) var state: MetroLookupState = .idle

    private var allMetros: [MetroArea] = []
    private let locationProvider: MetroLocationProviding

    struct MetroWithDistance: Identifiable, Equatable, Sendable {
        let metro: MetroArea
        let distanceMiles: Double
        var id: String { metro.id }
    }

    init(locationProvider: MetroLocationProviding = MetroCoreLocationProvider()) {
        self.locationProvider = locationProvider
        loadMetros()
    }

    /// Loads the bundled metro-areas.json file.
    private func loadMetros() {
        guard let url = Bundle.main.url(forResource: "metro-areas", withExtension: "json") else {
            print("[MetroArea] Bundle file not found")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(MetroAreasFile.self, from: data)
            allMetros = file.metros
            print("[MetroArea] Loaded \(allMetros.count) metros")
        } catch {
            print("[MetroArea] Failed to decode: \(error)")
        }
    }

    /// Resolves the sheet state: checks permission, fetches location, sorts metros by distance.
    /// Safe to call repeatedly — the sheet drives this on .task.
    func resolve(count: Int = 10) async {
        let status = locationProvider.authorizationStatus
        if status == .denied || status == .restricted {
            state = .permissionDenied
            return
        }
        if status == .notDetermined {
            locationProvider.requestWhenInUseAuthorizationIfNeeded()
        }

        state = .loading

        guard let loc = await locationProvider.currentLocation() else {
            state = .locationUnavailable
            return
        }

        let country = await locationProvider.countryCode(for: loc) ?? "US"
        let inCountry = allMetros.filter { $0.country == country }
        let usingFallback = inCountry.isEmpty
        let pool = usingFallback ? allMetros : inCountry

        let withDistance = pool.map { metro -> MetroWithDistance in
            let metroLoc = CLLocation(latitude: metro.lat, longitude: metro.lng)
            let meters = loc.distance(from: metroLoc)
            return MetroWithDistance(metro: metro, distanceMiles: meters * 0.000621371)
        }
        let sorted = Array(withDistance.sorted { $0.distanceMiles < $1.distanceMiles }.prefix(count))

        state = sorted.isEmpty ? .empty : .loaded(metros: sorted, fallback: usingFallback)
    }

    /// Test hook: force a specific state without having to drive the full
    /// permission + location + geocode pipeline.
    func overrideStateForTesting(_ state: MetroLookupState) {
        self.state = state
    }

    /// Returns top N nearest metros from a given coordinate — for testing or manual use.
    func nearestMetros(to coord: CLLocationCoordinate2D, inCountry country: String = "US", count: Int = 3) -> [MetroWithDistance] {
        let userLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let pool = allMetros.filter { $0.country == country }
        let withDistance = pool.map { metro -> MetroWithDistance in
            let metroLoc = CLLocation(latitude: metro.lat, longitude: metro.lng)
            let meters = userLoc.distance(from: metroLoc)
            return MetroWithDistance(metro: metro, distanceMiles: meters * 0.000621371)
        }
        return Array(withDistance.sorted { $0.distanceMiles < $1.distanceMiles }.prefix(count))
    }
}

// MARK: - Default CoreLocation Provider

/// Production CoreLocation-backed implementation of MetroLocationProviding.
final class MetroCoreLocationProvider: NSObject, MetroLocationProviding, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestWhenInUseAuthorizationIfNeeded() {
        manager.requestWhenInUseAuthorization()
    }

    func currentLocation() async -> CLLocation? {
        if let cached = manager.location { return cached }
        manager.startUpdatingLocation()
        defer { manager.stopUpdatingLocation() }
        for _ in 0..<15 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let loc = manager.location { return loc }
        }
        return nil
    }

    func countryCode(for location: CLLocation) async -> String? {
        await withCheckedContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                continuation.resume(returning: placemarks?.first?.isoCountryCode)
            }
        }
    }
}
