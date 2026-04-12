import Testing
import MapLibre
import CoreLocation
@testable import PrivateTourAi

@Suite("MapLibre Rendering")
@MainActor
struct MapLibreRenderingTests {

    @Test("MapLibre demo style loads successfully")
    func demoStyleLoads() async throws {
        let styleURL = URL(string: "https://demotiles.maplibre.org/style.json")!
        let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 400), styleURL: styleURL)

        // Wait for style to load (up to 10 seconds)
        let loaded = await withCheckedContinuation { continuation in
            let delegate = StyleLoadDelegate(onLoad: {
                continuation.resume(returning: true)
            }, onFail: { error in
                print("[TEST] Style FAILED: \(error)")
                continuation.resume(returning: false)
            })
            mapView.delegate = delegate
            // Keep delegate alive
            withExtendedLifetime(delegate) {
                // Pump the run loop to let networking happen
                let deadline = Date().addingTimeInterval(10)
                while Date() < deadline && !delegate.completed {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
                }
            }
            if !delegate.completed {
                continuation.resume(returning: false)
            }
        }

        #expect(loaded, "MapLibre style should load from demotiles.maplibre.org")
        #expect(mapView.style != nil, "Style should be non-nil after loading")
        if let style = mapView.style {
            print("[TEST] Style loaded: \(style.name ?? "unnamed"), layers: \(style.layers.count), sources: \(style.sources.count)")
            #expect(style.layers.count > 0, "Style should have layers")
            #expect(style.sources.count > 0, "Style should have sources")
        }
    }

    @Test("OpenFreeMap style loads successfully")
    func openFreeMapStyleLoads() async throws {
        let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!
        let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 400), styleURL: styleURL)

        let loaded = await withCheckedContinuation { continuation in
            let delegate = StyleLoadDelegate(onLoad: {
                continuation.resume(returning: true)
            }, onFail: { error in
                print("[TEST] OpenFreeMap style FAILED: \(error)")
                continuation.resume(returning: false)
            })
            mapView.delegate = delegate
            withExtendedLifetime(delegate) {
                let deadline = Date().addingTimeInterval(10)
                while Date() < deadline && !delegate.completed {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
                }
            }
            if !delegate.completed {
                continuation.resume(returning: false)
            }
        }

        #expect(loaded, "OpenFreeMap style should load")
    }

    @Test("Route polyline can be added to style")
    func routePolylineAdded() async throws {
        let styleURL = URL(string: "https://demotiles.maplibre.org/style.json")!
        let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 400), styleURL: styleURL)

        // Wait for style
        let delegate = StyleLoadDelegate(onLoad: {}, onFail: { _ in })
        mapView.delegate = delegate
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && !delegate.completed {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        guard let style = mapView.style else {
            Issue.record("Style didn't load — can't test polyline")
            return
        }

        // Add a route polyline
        var coords = [
            CLLocationCoordinate2D(latitude: 26.1, longitude: -80.1),
            CLLocationCoordinate2D(latitude: 26.2, longitude: -80.2),
            CLLocationCoordinate2D(latitude: 26.3, longitude: -80.3)
        ]
        let polyline = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
        let source = MLNShapeSource(identifier: "test-route", shape: polyline, options: nil)
        style.addSource(source)

        let layer = MLNLineStyleLayer(identifier: "test-route-layer", source: source)
        layer.lineColor = NSExpression(forConstantValue: UIColor.systemYellow)
        layer.lineWidth = NSExpression(forConstantValue: 5)
        style.addLayer(layer)

        #expect(style.source(withIdentifier: "test-route") != nil, "Route source should be added")
        #expect(style.layer(withIdentifier: "test-route-layer") != nil, "Route layer should be added")
        print("[TEST] ✅ Polyline added successfully to MapLibre style")
    }
}

// MARK: - Helper Delegate

private class StyleLoadDelegate: NSObject, MLNMapViewDelegate {
    var completed = false
    let onLoad: () -> Void
    let onFail: (Error) -> Void

    init(onLoad: @escaping () -> Void, onFail: @escaping (Error) -> Void) {
        self.onLoad = onLoad
        self.onFail = onFail
    }

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        guard !completed else { return }
        completed = true
        onLoad()
    }

    func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
        guard !completed else { return }
        completed = true
        onFail(error)
    }
}
