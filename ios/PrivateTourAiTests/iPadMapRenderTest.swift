import Testing
import SwiftUI
import MapKit
import MapLibre
import UIKit
import CoreLocation
@testable import PrivateTourAi

/// Test both Apple Maps and MapLibre rendering in an iPad-sized window,
/// simulating the fullScreenCover presentation used in TourDetailView.
@Suite("iPad Map Rendering")
@MainActor
struct iPadMapRenderTests {

    // iPad mini resolution
    private let iPadFrame = CGRect(x: 0, y: 0, width: 744, height: 1133)

    @Test("Apple Maps renders in iPad-sized fullScreenCover")
    func appleMapsOnIPad() async throws {
        let stops = makeTestStops()
        var cameraPosition: MapCameraPosition = .automatic

        // Simulate the Apple Maps path from GuidedTourView
        let mapContent = Map(position: .constant(cameraPosition)) {
            UserAnnotation()
            ForEach(stops) { stop in
                Annotation(stop.name, coordinate: CLLocationCoordinate2D(
                    latitude: stop.latitude, longitude: stop.longitude
                )) {
                    Circle().fill(Color.yellow).frame(width: 20, height: 20)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .ignoresSafeArea()

        let wrappedView = ZStack {
            mapContent
            VStack {
                Text("TOP CONTROLS").padding()
                Spacer()
                Text("BOTTOM CARD").padding().background(.ultraThickMaterial)
            }
        }

        let hostingVC = UIHostingController(rootView: wrappedView)
        let window = UIWindow(frame: iPadFrame)
        window.rootViewController = hostingVC
        window.makeKeyAndVisible()

        hostingVC.view.setNeedsLayout()
        hostingVC.view.layoutIfNeeded()

        print("[iPadTest] Apple Maps - Window: \(window.frame)")
        print("[iPadTest] Apple Maps - HostingVC: \(hostingVC.view.frame)")

        // Wait for layout
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        let snapshot = hostingVC.view.snapshotView(afterScreenUpdates: true)
        print("[iPadTest] Apple Maps - Snapshot: \(snapshot?.frame ?? .zero)")
        #expect(snapshot != nil, "Apple Maps should produce a snapshot on iPad")
        #expect(hostingVC.view.frame.width == iPadFrame.width)

        window.isHidden = true
    }

    @Test("MapLibre renders in iPad-sized fullScreenCover")
    func mapLibreOnIPad() async throws {
        let stops = makeTestStops()
        let routeCoords = [stops.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }]

        let mapView = MapLibreNavigationView(
            routeCoordinates: routeCoords,
            stops: stops,
            currentStopIndex: 0,
            followUser: false,
            heading: 0,
            use3DMap: false
        )

        let wrappedView = ZStack {
            mapView.ignoresSafeArea()
            VStack {
                Text("TOP CONTROLS").padding()
                Spacer()
                Text("BOTTOM CARD").padding().background(.ultraThickMaterial)
            }
        }

        let hostingVC = UIHostingController(rootView: wrappedView)
        let window = UIWindow(frame: iPadFrame)
        window.rootViewController = hostingVC
        window.makeKeyAndVisible()

        hostingVC.view.setNeedsLayout()
        hostingVC.view.layoutIfNeeded()

        print("[iPadTest] MapLibre - Window: \(window.frame)")

        // Wait for MLNMapView to appear and style to load
        let deadline = Date().addingTimeInterval(10)
        var mlnMapView: MLNMapView?
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
            mlnMapView = findMLNMapView(in: hostingVC.view)
            if let mlnMapView, mlnMapView.style != nil {
                break
            }
        }

        if let map = mlnMapView {
            print("[iPadTest] MapLibre - MLNMapView frame: \(map.frame)")
            print("[iPadTest] MapLibre - Style: \(map.style?.name ?? "nil")")
            print("[iPadTest] MapLibre - Center: \(map.centerCoordinate.latitude), \(map.centerCoordinate.longitude)")
            #expect(map.frame.width > 0, "MapLibre should have width on iPad")
            #expect(map.frame.height > 0, "MapLibre should have height on iPad")
            #expect(map.style != nil, "Style should load on iPad")

            // Verify route was drawn
            if let style = map.style {
                let routeSource = style.source(withIdentifier: "route-source-0")
                print("[iPadTest] MapLibre - Route source: \(routeSource != nil)")
                #expect(routeSource != nil, "Route should be drawn")
            }
        } else {
            Issue.record("MLNMapView not found in iPad view hierarchy")
            // Dump hierarchy for debugging
            dumpViewHierarchy(hostingVC.view, indent: 0)
        }

        window.isHidden = true
    }

    // MARK: - Helpers

    private func findMLNMapView(in view: UIView) -> MLNMapView? {
        if let mapView = view as? MLNMapView { return mapView }
        for subview in view.subviews {
            if let found = findMLNMapView(in: subview) { return found }
        }
        return nil
    }

    private func dumpViewHierarchy(_ view: UIView, indent: Int) {
        let prefix = String(repeating: "  ", count: indent)
        print("\(prefix)\(type(of: view)) frame=\(view.frame) hidden=\(view.isHidden) alpha=\(view.alpha)")
        for subview in view.subviews {
            dumpViewHierarchy(subview, indent: indent + 1)
        }
    }

    private func makeTestStops() -> [TourStop] {
        [
            TourStop(id: "1", sequenceOrder: 0, name: "Fort Lauderdale Beach", description: "Beach",
                     category: "landmark", latitude: 26.1224, longitude: -80.1373,
                     recommendedStayMinutes: 10, isOptional: false,
                     approachNarration: "", atStopNarration: "", departureNarration: "",
                     googlePlaceId: nil, photoUrl: nil),
            TourStop(id: "2", sequenceOrder: 1, name: "Las Olas Blvd", description: "Shopping",
                     category: "viewpoint", latitude: 26.1186, longitude: -80.1314,
                     recommendedStayMinutes: 15, isOptional: false,
                     approachNarration: "", atStopNarration: "", departureNarration: "",
                     googlePlaceId: nil, photoUrl: nil),
            TourStop(id: "3", sequenceOrder: 2, name: "Riverwalk", description: "Park",
                     category: "park", latitude: 26.1216, longitude: -80.1454,
                     recommendedStayMinutes: 20, isOptional: false,
                     approachNarration: "", atStopNarration: "", departureNarration: "",
                     googlePlaceId: nil, photoUrl: nil)
        ]
    }
}
