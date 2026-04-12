import SwiftUI
import MapKit
import FerrostarCore
import FerrostarCoreFFI
import FerrostarSwiftUI
import FerrostarMapLibreUI
import MapLibreSwiftUI
import CoreLocation

/// Wraps Ferrostar's DynamicallyOrientingNavigationView for turn-by-turn navigation.
struct FerrostarTurnByTurnView: View {
    let stops: [TourStop]
    let transportMode: String
    let onExit: () -> Void

    @State private var ferrostarCore: FerrostarCore?
    @State private var camera: MapViewCamera = .center(CLLocationCoordinate2D(latitude: 26.1, longitude: -80.1), zoom: 17)
    @State private var isMuted = false
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var hasStarted = false

    private let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    var body: some View {
        ZStack {
            if let core = ferrostarCore, let navState = core.state {
                DynamicallyOrientingNavigationView(
                    styleURL: styleURL,
                    camera: $camera,
                    navigationCamera: .automotiveNavigation(zoom: 17, pitch: 50),
                    navigationState: navState,
                    isMuted: isMuted,
                    onTapMute: { isMuted.toggle() },
                    onTapExit: onExit
                )
                .navigationFormatterCollection(FoundationFormatterCollection(
                    distanceFormatter: {
                        let f = MKDistanceFormatter()
                        f.units = .imperial
                        return f
                    }()
                ))
            } else if isLoading {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Calculating route...")
                        .foregroundStyle(.white)
                        .font(.subheadline)
                }
            } else if let error = errorMessage {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.white)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Try Again") {
                        Task { await startNavigation() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    Button("Exit", action: onExit)
                        .foregroundStyle(.white)
                }
            }
        }
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await startNavigation()
        }
    }

    private func startNavigation() async {
        isLoading = true
        errorMessage = nil

        guard stops.count >= 2 else {
            errorMessage = "Need at least 2 stops for navigation"
            isLoading = false
            return
        }

        do {
            let routeProvider = OSRMRouteProvider()
            routeProvider.profile = transportMode == "walk" ? "foot" : transportMode == "bike" ? "bike" : "driving"

            let firstStop = stops[0]
            let firstCoord = CLLocationCoordinate2D(latitude: firstStop.latitude, longitude: firstStop.longitude)

            // Try to get real location; fall back to simulated from first stop
            let locationProvider: any LocationProviding
            let coreLocProvider = CoreLocationProvider(
                activityType: .automotiveNavigation,
                allowBackgroundLocationUpdates: false
            )

            if coreLocProvider.lastLocation != nil {
                locationProvider = coreLocProvider
                print("[FerrostarTBT] Using real GPS location")
            } else {
                // No GPS fix — use simulated location at first stop for route calculation
                let simProvider = SimulatedLocationProvider()
                simProvider.lastLocation = FerrostarCoreFFI.UserLocation(
                    coordinates: GeographicCoordinate(lat: firstStop.latitude, lng: firstStop.longitude),
                    horizontalAccuracy: 10,
                    courseOverGround: CourseOverGround(degrees: 0, accuracy: 10),
                    timestamp: Date(),
                    speed: Speed(value: 0, accuracy: 0)
                )
                locationProvider = simProvider
                print("[FerrostarTBT] Using simulated location at first stop")
            }

            let config = SwiftNavigationControllerConfig(
                waypointAdvance: .waypointWithinRange(100),
                stepAdvanceCondition: stepAdvanceDistanceToEndOfStep(distance: 25, minimumHorizontalAccuracy: 32),
                arrivalStepAdvanceCondition: stepAdvanceDistanceToEndOfStep(distance: 25, minimumHorizontalAccuracy: 32),
                routeDeviationTracking: .staticThreshold(minimumHorizontalAccuracy: 25, maxAcceptableDeviation: 50),
                snappedLocationCourseFiltering: .snapToRoute
            )

            let core = FerrostarCore(
                customRouteProvider: routeProvider,
                locationProvider: locationProvider,
                navigationControllerConfig: config,
                networkSession: URLSession.shared
            )

            // Build waypoints from tour stops
            let waypoints = stops.dropFirst().map { stop in
                Waypoint(
                    coordinate: GeographicCoordinate(lat: stop.latitude, lng: stop.longitude),
                    kind: .break
                )
            }

            let userLoc = locationProvider.lastLocation ?? FerrostarCoreFFI.UserLocation(
                coordinates: GeographicCoordinate(lat: firstStop.latitude, lng: firstStop.longitude),
                horizontalAccuracy: 10,
                courseOverGround: CourseOverGround(degrees: 0, accuracy: 10),
                timestamp: Date(),
                speed: Speed(value: 0, accuracy: 0)
            )

            print("[FerrostarTBT] Getting routes from \(userLoc.coordinates.lat),\(userLoc.coordinates.lng)")

            let routes = try await core.getRoutes(initialLocation: userLoc, waypoints: waypoints)
            guard let route = routes.first else {
                errorMessage = "No route found"
                isLoading = false
                return
            }

            print("[FerrostarTBT] Route: \(route.geometry.count) points, \(route.steps.count) steps")

            try core.startNavigation(route: route)

            // If using simulated location, start simulating along the route
            if let simProvider = locationProvider as? SimulatedLocationProvider {
                simProvider.warpFactor = 2
                try simProvider.setSimulatedRoute(route)
                print("[FerrostarTBT] Started route simulation")
            }

            // Set camera to navigation mode tracking user
            camera = .automotiveNavigation(zoom: 17, pitch: 50)

            self.ferrostarCore = core
            isLoading = false
            print("[FerrostarTBT] Navigation started")

        } catch {
            print("[FerrostarTBT] Error: \(error)")
            errorMessage = "Route failed: \(error.localizedDescription)"
            isLoading = false
        }
    }
}
