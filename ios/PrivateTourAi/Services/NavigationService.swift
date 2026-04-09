import Foundation
import MapKit
import CoreLocation

@MainActor
class NavigationService: NSObject, ObservableObject {
    @Published var routePolylines: [MKPolyline] = []
    @Published var currentStepInstruction: String = ""
    @Published var distanceToNextStop: CLLocationDistance = 0
    @Published var etaToNextStop: TimeInterval = 0
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var heading: CLLocationDirection = 0
    @Published var isNavigating = false
    @Published var arrivedAtStop = false

    private let locationManager = CLLocationManager()
    private var stops: [TourStop] = []
    private var currentTargetIndex = 0
    private var routeSteps: [[MKRoute.Step]] = []
    private var currentStepIndex = 0
    private var transportMode: String = "car"

    // Geofence radius for stop arrival
    private let arrivalRadius: CLLocationDistance = 80 // meters

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // update every 10m
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.activityType = .automotiveNavigation
    }

    // MARK: - Calculate Routes

    func calculateRoutes(for stops: [TourStop], transportMode: String) async {
        self.stops = stops
        self.transportMode = transportMode
        routePolylines = []
        routeSteps = []

        guard stops.count >= 2 else { return }

        let mkTransportType: MKDirectionsTransportType = {
            switch transportMode {
            case "walk": return .walking
            default: return .automobile
            }
        }()

        // Calculate route between consecutive stops
        for i in 0..<(stops.count - 1) {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
                latitude: stops[i].latitude, longitude: stops[i].longitude
            )))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
                latitude: stops[i + 1].latitude, longitude: stops[i + 1].longitude
            )))
            request.transportType = mkTransportType
            request.requestsAlternateRoutes = false

            do {
                let directions = MKDirections(request: request)
                let response = try await directions.calculate()
                if let route = response.routes.first {
                    routePolylines.append(route.polyline)
                    routeSteps.append(route.steps.filter { !$0.instructions.isEmpty })
                }
            } catch {
                print("[Nav] Route calculation failed for leg \(i): \(error)")
                routeSteps.append([])
            }
        }
    }

    // MARK: - Start Navigation

    func startNavigation(targetStopIndex: Int = 0) {
        locationManager.requestWhenInUseAuthorization()
        currentTargetIndex = targetStopIndex
        currentStepIndex = 0
        isNavigating = true
        arrivedAtStop = false
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        updateCurrentInstruction()
    }

    func advanceToNextStop() {
        currentTargetIndex += 1
        currentStepIndex = 0
        arrivedAtStop = false
        if currentTargetIndex < stops.count {
            updateCurrentInstruction()
        } else {
            stopNavigation()
        }
    }

    func stopNavigation() {
        isNavigating = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        currentStepInstruction = ""
    }

    // MARK: - Update Logic

    private func updateCurrentInstruction() {
        // Get steps for current leg (from previous stop to current target)
        let legIndex = max(0, currentTargetIndex - 1)
        guard legIndex < routeSteps.count else {
            currentStepInstruction = "Head to \(stops[safe: currentTargetIndex]?.name ?? "next stop")"
            return
        }

        let steps = routeSteps[legIndex]
        if currentStepIndex < steps.count {
            currentStepInstruction = steps[currentStepIndex].instructions
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

        // Estimate ETA based on average speed
        if location.speed > 0 {
            etaToNextStop = distance / location.speed
        }

        if distance < arrivalRadius && !arrivedAtStop {
            arrivedAtStop = true
            currentStepInstruction = "You've arrived at \(target.name)"
        }

        // Update turn instruction based on distance to next step
        if !arrivedAtStop {
            updateStepBasedOnLocation(location)
        }
    }

    private func updateStepBasedOnLocation(_ location: CLLocation) {
        let legIndex = max(0, currentTargetIndex - 1)
        guard legIndex < routeSteps.count else { return }
        let steps = routeSteps[legIndex]

        // Find the closest upcoming step
        for (i, step) in steps.enumerated() where i >= currentStepIndex {
            let stepEnd = step.polyline.coordinate
            let dist = location.distance(from: CLLocation(latitude: stepEnd.latitude, longitude: stepEnd.longitude))
            if dist < 50 && i + 1 < steps.count {
                currentStepIndex = i + 1
                currentStepInstruction = steps[i + 1].instructions
                break
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension NavigationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            userLocation = location.coordinate
            checkArrival(at: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            heading = newHeading.trueHeading
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Nav] Location error: \(error)")
    }
}

// Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
