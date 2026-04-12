import Testing
import SwiftUI
import MapLibre
import UIKit
import CoreLocation
@testable import PrivateTourAi

/// Test MapLibreNavigationView in a SwiftUI hosting context — exactly how GuidedTourView uses it.
@Suite("MapLibre SwiftUI Integration")
@MainActor
struct MapLibreSwiftUIRenderTests {

    @Test("MapLibreNavigationView renders in SwiftUI hosting controller")
    func rendersInHostingController() async throws {
        // Create test tour stops
        let stops = makeTestStops()
        let routeCoordinates = [stops.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }]

        // Create the exact same view used in GuidedTourView
        let mapView = MapLibreNavigationView(
            routeCoordinates: routeCoordinates,
            stops: stops,
            currentStopIndex: 0,
            followUser: false,
            heading: 0,
            use3DMap: false
        )

        // Host in a real window via UIHostingController — this is the SwiftUI rendering path
        let hostingVC = UIHostingController(rootView: mapView.ignoresSafeArea())
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = hostingVC
        window.makeKeyAndVisible()

        print("[SwiftUITest] Window: \(window.frame)")
        print("[SwiftUITest] HostingVC view: \(hostingVC.view.frame)")

        // Force layout pass
        hostingVC.view.setNeedsLayout()
        hostingVC.view.layoutIfNeeded()

        // Wait for layout + style load
        let deadline = Date().addingTimeInterval(15)
        var mlnMapView: MLNMapView?

        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
            hostingVC.view.setNeedsLayout()
            hostingVC.view.layoutIfNeeded()

            // Find the MLNMapView in the view hierarchy
            mlnMapView = findMLNMapView(in: hostingVC.view)
            if let mlnMapView, mlnMapView.style != nil {
                break
            }
        }

        // Debug: dump view hierarchy if map not found
        if mlnMapView == nil {
            print("[SwiftUITest] View hierarchy:")
            dumpViewHierarchy(hostingVC.view, indent: 0)
        }

        guard let foundMap = mlnMapView else {
            Issue.record("MLNMapView not found in SwiftUI view hierarchy")
            window.isHidden = true
            return
        }

        print("[SwiftUITest] MLNMapView frame: \(foundMap.frame)")
        print("[SwiftUITest] MLNMapView style: \(foundMap.style?.name ?? "nil")")
        print("[SwiftUITest] MLNMapView superview: \(String(describing: type(of: foundMap.superview)))")

        #expect(foundMap.frame.width > 0, "Map view should have non-zero width in SwiftUI")
        #expect(foundMap.frame.height > 0, "Map view should have non-zero height in SwiftUI")
        #expect(foundMap.style != nil, "Style should load in SwiftUI context")

        if let style = foundMap.style {
            print("[SwiftUITest] ✅ Style loaded: \(style.name ?? "unnamed"), layers: \(style.layers.count)")
            #expect(style.layers.count > 0)

            // Check if route source was added
            let routeSource = style.source(withIdentifier: "route-source-0")
            print("[SwiftUITest] Route source present: \(routeSource != nil)")
        }

        // Check center is near our test coordinates (not at 0,0 default)
        let center = foundMap.centerCoordinate
        print("[SwiftUITest] Map center: lat=\(center.latitude), lng=\(center.longitude)")

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
        print("\(prefix)\(type(of: view)) frame=\(view.frame) subviews=\(view.subviews.count)")
        for subview in view.subviews {
            dumpViewHierarchy(subview, indent: indent + 1)
        }
    }

    private func makeTestStops() -> [TourStop] {
        [
            TourStop(
                id: "1", sequenceOrder: 0, name: "Stop A", description: "Desc A",
                category: "landmark", latitude: 26.1224, longitude: -80.1373,
                recommendedStayMinutes: 10, isOptional: false,
                approachNarration: "Approaching", atStopNarration: "At stop", departureNarration: "Leaving",
                googlePlaceId: nil, photoUrl: nil
            ),
            TourStop(
                id: "2", sequenceOrder: 1, name: "Stop B", description: "Desc B",
                category: "viewpoint", latitude: 26.1516, longitude: -80.1554,
                recommendedStayMinutes: 15, isOptional: false,
                approachNarration: "Approaching", atStopNarration: "At stop", departureNarration: "Leaving",
                googlePlaceId: nil, photoUrl: nil
            ),
            TourStop(
                id: "3", sequenceOrder: 2, name: "Stop C", description: "Desc C",
                category: "restaurant", latitude: 26.1616, longitude: -80.1234,
                recommendedStayMinutes: 20, isOptional: false,
                approachNarration: "Approaching", atStopNarration: "At stop", departureNarration: "Leaving",
                googlePlaceId: nil, photoUrl: nil
            )
        ]
    }
}
