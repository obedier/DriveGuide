import Foundation
import CoreLocation
import FerrostarCore
import FerrostarCoreFFI

/// Custom route provider that fetches routes from OSRM and returns Ferrostar Route objects.
class OSRMRouteProvider: CustomRouteProvider {
    /// Base URL for OSRM routing. Replace with your own instance for production.
    var baseURL: String = "https://router.project-osrm.org"
    var profile: String = "driving"

    func getRoutes(userLocation: UserLocation, waypoints: [Waypoint]) async throws -> [Route] {
        // Build coordinate string: origin;wp1;wp2;...;dest
        var coords = "\(userLocation.coordinates.lng),\(userLocation.coordinates.lat)"
        for wp in waypoints {
            coords += ";\(wp.coordinate.lng),\(wp.coordinate.lat)"
        }

        let urlStr = "\(baseURL)/route/v1/\(profile)/\(coords)?overview=full&geometries=polyline6&steps=true&alternatives=true"
        guard let url = URL(string: urlStr) else {
            throw NSError(domain: "OSRMRouteProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid OSRM URL"])
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "OSRMRouteProvider", code: code, userInfo: [NSLocalizedDescriptionKey: "OSRM returned HTTP \(code)"])
        }

        // Parse the OSRM response to extract individual route + waypoints JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let routesArray = json["routes"] as? [[String: Any]],
              let waypointsArray = json["waypoints"] as? [[String: Any]] else {
            throw NSError(domain: "OSRMRouteProvider", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid OSRM response structure"])
        }

        let waypointsData = try JSONSerialization.data(withJSONObject: waypointsArray)

        // Convert each OSRM route into a Ferrostar Route using the built-in parser
        var ferrostarRoutes: [Route] = []
        for osrmRoute in routesArray {
            let routeData = try JSONSerialization.data(withJSONObject: osrmRoute)
            let route = try Route.initFromOsrm(route: routeData, waypoints: waypointsData, polylinePrecision: 6)
            ferrostarRoutes.append(route)
        }

        return ferrostarRoutes
    }
}
