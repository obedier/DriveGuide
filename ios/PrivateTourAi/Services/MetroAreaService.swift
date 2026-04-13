import Foundation
import CoreLocation

/// A major metro area with coordinates and an iconic image URL.
struct MetroArea: Codable, Identifiable, Equatable {
    let name: String
    let state: String
    let country: String
    let lat: Double
    let lng: Double
    let image: String

    var id: String { "\(country)-\(state)-\(name)" }
    var displayName: String { "\(name), \(state)" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    var imageURL: URL? { URL(string: image) }
}

private struct MetroAreasFile: Codable {
    let metros: [MetroArea]
}

/// Service for finding the user's nearest major metro areas from a curated list.
/// Data is bundled with the app — works offline.
@MainActor
final class MetroAreaService: ObservableObject {
    @Published private(set) var nearestMetros: [MetroWithDistance] = []
    @Published private(set) var isLoading = false
    @Published var userCountry: String?

    private var allMetros: [MetroArea] = []
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    struct MetroWithDistance: Identifiable, Equatable {
        let metro: MetroArea
        let distanceMiles: Double
        var id: String { metro.id }
    }

    init() {
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

    /// Fetches user location, determines country, and computes top N nearest metros.
    func refreshNearest(count: Int = 3) async {
        isLoading = true
        defer { isLoading = false }

        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        // Get last-known or request a new fix
        var location = locationManager.location
        if location == nil {
            location = try? await requestLocation()
        }
        guard let loc = location else {
            print("[MetroArea] No location available")
            return
        }

        // Determine country via reverse geocoding (best-effort; fall back to US)
        let country = await reverseGeocodeCountry(for: loc) ?? "US"
        userCountry = country

        // Filter by country, compute distances, take top N
        let inCountry = allMetros.filter { $0.country == country }
        let pool = inCountry.isEmpty ? allMetros : inCountry
        let withDistance = pool.map { metro -> MetroWithDistance in
            let metroLoc = CLLocation(latitude: metro.lat, longitude: metro.lng)
            let meters = loc.distance(from: metroLoc)
            return MetroWithDistance(metro: metro, distanceMiles: meters * 0.000621371)
        }
        nearestMetros = withDistance
            .sorted { $0.distanceMiles < $1.distanceMiles }
            .prefix(count)
            .map { $0 }
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

    private func requestLocation() async throws -> CLLocation? {
        // Try to get a fix via startUpdatingLocation; wait up to 3 seconds
        locationManager.startUpdatingLocation()
        defer { locationManager.stopUpdatingLocation() }
        for _ in 0..<15 {
            try await Task.sleep(nanoseconds: 200_000_000)
            if let loc = locationManager.location { return loc }
        }
        return nil
    }

    private func reverseGeocodeCountry(for location: CLLocation) async -> String? {
        await withCheckedContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                continuation.resume(returning: placemarks?.first?.isoCountryCode)
            }
        }
    }
}
