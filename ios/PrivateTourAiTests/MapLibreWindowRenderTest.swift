import Testing
import MapLibre
import UIKit
import CoreLocation
@testable import PrivateTourAi

/// Tests MapLibre rendering in a real UIWindow — the closest simulation to how
/// MapLibreNavigationView works in production inside GuidedTourView.
@Suite("MapLibre Window Rendering")
@MainActor
struct MapLibreWindowRenderTests {

    @Test("MLNMapView renders in a real UIWindow")
    func rendersInWindow() async throws {
        let styleURL = URL(string: "https://demotiles.maplibre.org/style.json")!

        // Create a real window with the map view — simulates the UIViewRepresentable path
        let window = UIWindow(frame: UIScreen.main.bounds)
        let mapView = MLNMapView(frame: window.bounds, styleURL: styleURL)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let vc = UIViewController()
        vc.view.addSubview(mapView)
        window.rootViewController = vc
        window.makeKeyAndVisible()

        print("[WindowTest] Window: \(window.frame), MapView: \(mapView.frame)")
        #expect(mapView.frame.width > 0, "Map should have non-zero width")
        #expect(mapView.frame.height > 0, "Map should have non-zero height")

        // Wait for style to load
        let delegate = TestMapDelegate()
        mapView.delegate = delegate

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline && !delegate.styleLoaded && delegate.loadError == nil {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        if let error = delegate.loadError {
            Issue.record("Map failed to load: \(error)")
            return
        }

        #expect(delegate.styleLoaded, "Style should have loaded within 15s")
        print("[WindowTest] ✅ Style loaded in window context")

        // Now add route polylines — same code path as MapLibreNavigationView.Coordinator
        guard let style = mapView.style else {
            Issue.record("Style is nil after loading")
            return
        }

        var coords = [
            CLLocationCoordinate2D(latitude: 26.1224, longitude: -80.1373),  // Fort Lauderdale
            CLLocationCoordinate2D(latitude: 26.1416, longitude: -80.1494),
            CLLocationCoordinate2D(latitude: 26.1516, longitude: -80.1554),
            CLLocationCoordinate2D(latitude: 26.1616, longitude: -80.1234)
        ]
        let polyline = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
        let source = MLNShapeSource(identifier: "route-source-0", shape: polyline, options: nil)
        style.addSource(source)

        let layer = MLNLineStyleLayer(identifier: "route-layer-0", source: source)
        layer.lineColor = NSExpression(forConstantValue: UIColor.systemYellow)
        layer.lineWidth = NSExpression(forConstantValue: 5)
        layer.lineCap = NSExpression(forConstantValue: "round")
        layer.lineJoin = NSExpression(forConstantValue: "round")
        style.addLayer(layer)

        #expect(style.source(withIdentifier: "route-source-0") != nil)
        #expect(style.layer(withIdentifier: "route-layer-0") != nil)
        print("[WindowTest] ✅ Route polyline added in window context")

        // Add a stop annotation
        let point = MLNPointAnnotation()
        point.coordinate = coords[0]
        point.title = "1. Test Stop"
        mapView.addAnnotation(point)
        #expect(mapView.annotations?.count ?? 0 > 0)
        print("[WindowTest] ✅ Stop annotation added")

        // Fit camera to route
        var bounds = MLNCoordinateBounds(sw: coords[0], ne: coords[0])
        for coord in coords {
            bounds.sw.latitude = min(bounds.sw.latitude, coord.latitude)
            bounds.sw.longitude = min(bounds.sw.longitude, coord.longitude)
            bounds.ne.latitude = max(bounds.ne.latitude, coord.latitude)
            bounds.ne.longitude = max(bounds.ne.longitude, coord.longitude)
        }
        let camera = mapView.cameraThatFitsCoordinateBounds(
            bounds, edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 200, right: 40)
        )
        mapView.setCamera(camera, animated: false)
        print("[WindowTest] ✅ Camera fitted to route bounds")

        // Let it render a couple frames
        let renderDeadline = Date().addingTimeInterval(2)
        while Date() < renderDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        // Take a snapshot to verify rendering
        let snapshot = mapView.snapshotView(afterScreenUpdates: true)
        #expect(snapshot != nil, "Map should produce a snapshot")
        if let snapshot {
            print("[WindowTest] ✅ Snapshot produced: \(snapshot.frame)")
        }

        // Verify the map center is near our route (not at 0,0)
        let center = mapView.centerCoordinate
        print("[WindowTest] Map center: \(center.latitude), \(center.longitude)")
        #expect(center.latitude > 20 && center.latitude < 30, "Map should be centered near Fort Lauderdale, not at 0,0")
        #expect(center.longitude > -85 && center.longitude < -75, "Map should be centered near Fort Lauderdale")

        // Clean up
        window.isHidden = true
    }
}

private class TestMapDelegate: NSObject, MLNMapViewDelegate {
    var styleLoaded = false
    var loadError: Error?

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        print("[WindowTest] didFinishLoading style: \(style.name ?? "unnamed"), layers: \(style.layers.count)")
        styleLoaded = true
    }

    func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
        print("[WindowTest] ❌ FAILED: \(error)")
        loadError = error
    }

    func mapViewDidFinishRenderingMap(_ mapView: MLNMapView, fullyRendered: Bool) {
        print("[WindowTest] Rendered (fully: \(fullyRendered))")
    }
}
