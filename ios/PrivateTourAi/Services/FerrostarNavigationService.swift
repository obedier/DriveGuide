import Foundation
import CoreLocation
import Combine
import os

private let logger = Logger(subsystem: "com.privatetourai.app", category: "FerrostarNav")

// MARK: - OSRM Route Response Models

struct OSRMResponse: Decodable {
    let routes: [OSRMRouteResult]
}

struct OSRMRouteResult: Decodable {
    let geometry: OSRMGeometry
    let legs: [OSRMLeg]
    let distance: Double
    let duration: Double
}

struct OSRMGeometry: Decodable {
    let coordinates: [[Double]] // [lng, lat]
}

struct OSRMLeg: Decodable {
    let steps: [OSRMStep]
}

struct OSRMStep: Decodable {
    let maneuver: OSRMManeuver
    let name: String
    let distance: Double
    let duration: Double
    let geometry: OSRMGeometry
}

struct OSRMManeuver: Decodable {
    let type: String
    let modifier: String?
    let location: [Double] // [lng, lat]
}

// MARK: - Route Leg Model

struct RouteLeg {
    let coordinates: [CLLocationCoordinate2D]
    let steps: [RouteStepInfo]
    let totalDistance: Double // meters
    let totalDuration: Double // seconds
}

struct RouteStepInfo {
    let instruction: String
    let distance: Double
    let duration: Double
    let maneuverLocation: CLLocationCoordinate2D
    let maneuverType: String
    let maneuverModifier: String?
}

// MARK: - Ferrostar Navigation Service

@MainActor
class FerrostarNavigationService: NSObject, ObservableObject {
    // Published state matching NavigationService interface
    @Published var routeCoordinates: [[CLLocationCoordinate2D]] = []
    @Published var currentStepInstruction: String = ""
    @Published var distanceToNextStop: CLLocationDistance = 0
    @Published var etaToNextStop: TimeInterval = 0
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var heading: CLLocationDirection = 0
    @Published var isNavigating = false
    @Published var arrivedAtStop = false

    /// Emits the stop index the user just arrived at. Used by
    /// RouteAwarePlaybackCoordinator (2.11) to auto-play the matching
    /// narration segment. `ArrivalProvider` conformance lives at the
    /// bottom of this file.
    private let arrivalSubject = PassthroughSubject<Int, Never>()

    private let locationManager = CLLocationManager()
    private var stops: [TourStop] = []
    private var currentTargetIndex = 0
    private var routeLegs: [RouteLeg] = []
    private var currentStepIndex = 0
    private var transportMode: String = "car"
    private var isProcessingArrival = false

    private let arrivalRadius: CLLocationDistance = 80 // meters

    /// Base URL for OSRM routing. Defaults to the public demo server.
    /// ⚠️ Replace with your own Valhalla/OSRM instance before production release.
    /// The public OSRM demo server prohibits production use.
    var routingBaseURL: String = "https://router.project-osrm.org"

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.activityType = .automotiveNavigation
    }

    // MARK: - Route Calculation

    func calculateRoutes(for stops: [TourStop], transportMode: String) async {
        self.stops = stops
        self.transportMode = transportMode
        routeCoordinates = []
        routeLegs = []

        logger.info("calculateRoutes: \(stops.count) stops, mode=\(transportMode)")
        guard stops.count >= 2 else {
            logger.warning("calculateRoutes: need at least 2 stops, got \(stops.count)")
            return
        }

        // Request location authorization early so we may have a fix for the first leg
        locationManager.requestWhenInUseAuthorization()

        let profile = OSRMRouteParser.osrmProfile(for: transportMode)

        // First leg: user's current location to first stop (if location available)
        if let userLoc = locationManager.location?.coordinate {
            let firstDest = CLLocationCoordinate2D(
                latitude: stops[0].latitude, longitude: stops[0].longitude
            )
            if let leg = await fetchRoute(from: userLoc, to: firstDest, profile: profile) {
                routeLegs.append(leg)
                routeCoordinates.append(leg.coordinates)
            }
        } else {
            logger.info("No location fix yet — first leg (user → stop 0) will be calculated when navigation starts")
        }

        // Subsequent legs: between consecutive stops
        for i in 0..<(stops.count - 1) {
            let origin = CLLocationCoordinate2D(
                latitude: stops[i].latitude, longitude: stops[i].longitude
            )
            let dest = CLLocationCoordinate2D(
                latitude: stops[i + 1].latitude, longitude: stops[i + 1].longitude
            )
            if let leg = await fetchRoute(from: origin, to: dest, profile: profile) {
                routeLegs.append(leg)
                routeCoordinates.append(leg.coordinates)
            } else {
                // Fallback: straight line if routing fails
                routeLegs.append(RouteLeg(
                    coordinates: [origin, dest], steps: [], totalDistance: 0, totalDuration: 0
                ))
                routeCoordinates.append([origin, dest])
            }
        }
    }

    // MARK: - Navigation Control

    func startNavigation(targetStopIndex: Int = 0) {
        locationManager.requestWhenInUseAuthorization()
        currentTargetIndex = targetStopIndex
        currentStepIndex = 0
        isNavigating = true
        arrivedAtStop = false
        isProcessingArrival = false
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        updateCurrentInstruction()
    }

    func advanceToNextStop() {
        guard !isProcessingArrival else { return }
        isProcessingArrival = true
        currentTargetIndex += 1
        currentStepIndex = 0
        arrivedAtStop = false
        if currentTargetIndex < stops.count {
            updateCurrentInstruction()
            isProcessingArrival = false
        } else {
            stopNavigation()
            isProcessingArrival = false
        }
    }

    func stopNavigation() {
        isNavigating = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        currentStepInstruction = ""
    }

    // MARK: - OSRM Routing

    private func fetchRoute(
        from origin: CLLocationCoordinate2D,
        to dest: CLLocationCoordinate2D,
        profile: String
    ) async -> RouteLeg? {
        let coords = "\(origin.longitude),\(origin.latitude);\(dest.longitude),\(dest.latitude)"
        let urlStr = "\(routingBaseURL)/route/v1/\(profile)/\(coords)?overview=full&geometries=geojson&steps=true"

        guard let url = URL(string: urlStr) else {
            logger.error("Invalid URL constructed for route request")
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                logger.warning("Route request failed: HTTP \(code)")
                return nil
            }

            let leg = try OSRMRouteParser.parseResponse(data: data)
            if let leg {
                logger.info("Route parsed: \(leg.coordinates.count) coords, \(leg.steps.count) steps, \(Int(leg.totalDistance))m")
            } else {
                logger.warning("Route response had no routes")
            }
            return leg
        } catch {
            logger.error("Route fetch error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Navigation State Updates

    private func handleLocationUpdate(_ location: CLLocation) {
        userLocation = location.coordinate
        guard isNavigating else { return }
        checkArrival(at: location)
    }

    private func updateCurrentInstruction() {
        let legIndex = currentTargetIndex
        guard legIndex < routeLegs.count else {
            currentStepInstruction = "Head to \(stops[safe: currentTargetIndex]?.name ?? "next stop")"
            return
        }

        let leg = routeLegs[legIndex]
        if currentStepIndex < leg.steps.count {
            currentStepInstruction = leg.steps[currentStepIndex].instruction
        } else {
            currentStepInstruction = "Arriving at \(stops[safe: currentTargetIndex]?.name ?? "stop")"
        }
    }

    private func checkArrival(at location: CLLocation) {
        guard currentTargetIndex < stops.count else { return }
        let target = stops[currentTargetIndex]
        let targetLocation = CLLocation(latitude: target.latitude, longitude: target.longitude)
        let distance = location.distance(from: targetLocation)

        distanceToNextStop = distance

        if location.speed > 0 {
            etaToNextStop = distance / location.speed
        }

        if distance < arrivalRadius && !arrivedAtStop && !isProcessingArrival {
            arrivedAtStop = true
            currentStepInstruction = "You've arrived at \(target.name)"
            arrivalSubject.send(currentTargetIndex)
        }

        if !arrivedAtStop {
            updateStepBasedOnLocation(location)
        }
    }

    private func updateStepBasedOnLocation(_ location: CLLocation) {
        let legIndex = currentTargetIndex
        guard legIndex < routeLegs.count else { return }
        let steps = routeLegs[legIndex].steps

        for (i, step) in steps.enumerated() where i >= currentStepIndex {
            let dist = location.distance(from: CLLocation(
                latitude: step.maneuverLocation.latitude,
                longitude: step.maneuverLocation.longitude
            ))
            if dist < 50 && i + 1 < steps.count {
                currentStepIndex = i + 1
                currentStepInstruction = steps[i + 1].instruction
                break
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension FerrostarNavigationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.handleLocationUpdate(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor [weak self] in
            self?.heading = newHeading.trueHeading
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("Location error: \(error.localizedDescription)")
    }
}

// MARK: - OSRM Route Parser (pure functions, no actor isolation)

enum OSRMRouteParser {
    static func buildInstruction(maneuverType: String, maneuverModifier: String?, streetName: String) -> String {
        let modifier = maneuverModifier ?? ""
        let name = streetName.isEmpty ? "" : " onto \(streetName)"

        switch maneuverType {
        case "depart": return "Head\(name)"
        case "arrive": return "Arrive at destination"
        case "turn":
            let direction = modifier.replacingOccurrences(of: "sharp ", with: "sharp ")
            return "Turn \(direction)\(name)"
        case "merge": return "Merge\(name)"
        case "fork": return "Take the \(modifier) fork\(name)"
        case "roundabout", "rotary": return "Enter roundabout\(name)"
        case "new name": return "Continue\(name)"
        case "continue": return "Continue \(modifier)\(name)"
        case "end of road": return "At end of road, turn \(modifier)\(name)"
        default:
            if modifier.isEmpty { return "" }
            return "\(modifier.capitalized)\(name)"
        }
    }

    static func buildInstruction(_ step: OSRMStep) -> String {
        buildInstruction(
            maneuverType: step.maneuver.type,
            maneuverModifier: step.maneuver.modifier,
            streetName: step.name
        )
    }

    static func osrmProfile(for mode: String) -> String {
        switch mode {
        case "walk": return "foot"
        case "bike": return "bike"
        default: return "driving"
        }
    }

    /// Parse an OSRM JSON response into a RouteLeg with bounds-checked coordinate access.
    static func parseResponse(data: Data) throws -> RouteLeg? {
        let osrmResponse = try JSONDecoder().decode(OSRMResponse.self, from: data)
        guard let route = osrmResponse.routes.first else { return nil }

        // Bounds-checked coordinate conversion: skip malformed entries
        let coordinates = route.geometry.coordinates.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }

        let steps = route.legs.flatMap { leg in
            leg.steps.compactMap { step -> RouteStepInfo? in
                let instruction = buildInstruction(step)
                guard !instruction.isEmpty else { return nil }
                // Bounds-check maneuver location
                guard step.maneuver.location.count >= 2 else { return nil }
                return RouteStepInfo(
                    instruction: instruction,
                    distance: step.distance,
                    duration: step.duration,
                    maneuverLocation: CLLocationCoordinate2D(
                        latitude: step.maneuver.location[1],
                        longitude: step.maneuver.location[0]
                    ),
                    maneuverType: step.maneuver.type,
                    maneuverModifier: step.maneuver.modifier
                )
            }
        }

        return RouteLeg(
            coordinates: coordinates,
            steps: steps,
            totalDistance: route.distance,
            totalDuration: route.duration
        )
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - ArrivalProvider (2.11 route-aware narration)

extension FerrostarNavigationService: ArrivalProvider {
    var arrivedAtStopPublisher: AnyPublisher<Int, Never> {
        arrivalSubject.eraseToAnyPublisher()
    }
}
