import SwiftUI
import MapLibre
import os

private let mapLogger = Logger(subsystem: "com.privatetourai.app", category: "MapLibreNav")

/// SwiftUI wrapper for MLNMapView with route polyline rendering and user location tracking.
struct MapLibreNavigationView: UIViewRepresentable {
    /// Route leg coordinate arrays to draw as polylines
    let routeCoordinates: [[CLLocationCoordinate2D]]
    /// Tour stop annotations
    let stops: [TourStop]
    /// Currently active stop index (for highlighting)
    let currentStopIndex: Int
    /// Whether to follow the user's location with heading
    let followUser: Bool
    /// User heading for camera orientation
    let heading: CLLocationDirection
    /// Whether to use 3D perspective
    let use3DMap: Bool
    /// Whether turn-by-turn navigation is active
    var isNavigating: Bool = false
    /// User's current location (for navigation camera)
    var userLocation: CLLocationCoordinate2D? = nil

    /// MapLibre style URL. Uses OpenFreeMap (free, no API key, full OSM detail).
    static let defaultStyleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    /// Optional local .mbtiles file name (without extension) bundled in the app.
    /// When set, tiles are loaded from the local file instead of the network.
    var offlineMBTilesFile: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let styleURL: URL
        if let localFile = offlineMBTilesFile,
           let localURL = Bundle.main.url(forResource: localFile, withExtension: "json") {
            styleURL = localURL
        } else {
            styleURL = Self.defaultStyleURL
        }

        print("[MapLibre] Creating MLNMapView with style: \(styleURL.absoluteString)")

        // Use screen bounds to ensure Metal renderer initializes with a real frame
        let mapView = MLNMapView(frame: UIScreen.main.bounds, styleURL: styleURL)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.compassViewPosition = .topRight
        mapView.logoView.isHidden = true
        mapView.attributionButtonPosition = .bottomLeft

        // Set initial camera to first stop so map never starts at 0,0
        if let firstStop = stops.first {
            mapView.setCenter(
                CLLocationCoordinate2D(latitude: firstStop.latitude, longitude: firstStop.longitude),
                zoomLevel: 12,
                animated: false
            )
            print("[MapLibre] Initial center: \(firstStop.latitude), \(firstStop.longitude)")
        }

        if followUser {
            mapView.userTrackingMode = .followWithHeading
        }

        print("[MapLibre] MLNMapView created, waiting for style to load...")
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.parent = self

        // Guard: don't update until the map has a real frame and style
        guard mapView.frame.width > 0 && mapView.frame.height > 0 else { return }
        guard mapView.style != nil else { return }

        // Navigation mode: camera follows user with heading and 3D tilt
        if isNavigating && followUser {
            if mapView.userTrackingMode != .followWithHeading {
                mapView.userTrackingMode = .followWithHeading
            }
            // Set navigation pitch (3D driving perspective)
            if mapView.camera.pitch < 40 {
                let camera = mapView.camera
                camera.pitch = 55
                camera.altitude = 500
                mapView.setCamera(camera, animated: true)
            }
        } else if isNavigating, let loc = userLocation {
            // Navigating but user panned away — update camera position without tracking
            mapView.userTrackingMode = .none
            if use3DMap && mapView.camera.pitch < 40 {
                let camera = MLNMapCamera(
                    lookingAtCenter: loc, altitude: 600,
                    pitch: 55, heading: heading
                )
                mapView.setCamera(camera, withDuration: 0.5, animationTimingFunction: nil)
            }
        } else {
            // Overview mode
            if followUser && mapView.userTrackingMode != .followWithHeading {
                mapView.userTrackingMode = .followWithHeading
            } else if !followUser && mapView.userTrackingMode != .none {
                mapView.userTrackingMode = .none
            }
            if use3DMap && mapView.camera.pitch < 40 {
                let camera = mapView.camera
                camera.pitch = 55
                mapView.setCamera(camera, animated: true)
            } else if !use3DMap && mapView.camera.pitch > 10 {
                let camera = mapView.camera
                camera.pitch = 0
                mapView.setCamera(camera, animated: true)
            }
        }

        // Update route polylines and annotations
        context.coordinator.updateRoutes(on: mapView)
        context.coordinator.updateStopAnnotations(on: mapView)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapLibreNavigationView
        private var lastRouteTotalCoordCount = 0
        private var lastStopCount = 0
        private var lastCurrentStopIndex = -1

        init(parent: MapLibreNavigationView) {
            self.parent = parent
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            print("[MapLibre] ✅ Style loaded: \(style.name ?? "unnamed"), sources: \(style.sources.count), layers: \(style.layers.count)")
            lastRouteTotalCoordCount = 0
            lastStopCount = 0
            lastCurrentStopIndex = -1
            updateRoutes(on: mapView)
            updateStopAnnotations(on: mapView)
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            print("[MapLibre] ❌ Map FAILED to load: \(error)")
        }

        func mapView(_ mapView: MLNMapView, didFailToLoadImage imageName: String) -> UIImage? {
            mapLogger.warning("Failed to load image: \(imageName)")
            return nil
        }

        func updateRoutes(on mapView: MLNMapView) {
            guard let style = mapView.style else { return }
            let routes = parent.routeCoordinates

            // Skip if routes haven't changed (compare total coordinate count for reroute detection)
            let totalCoords = routes.reduce(0) { $0 + $1.count }
            if totalCoords == lastRouteTotalCoordCount && lastRouteTotalCoordCount > 0 { return }
            lastRouteTotalCoordCount = totalCoords
            mapLogger.info("Drawing \(routes.count) route legs with \(totalCoords) total coordinates")

            // Remove existing route layers/sources
            for i in 0..<20 {
                if let layer = style.layer(withIdentifier: "route-outline-layer-\(i)") {
                    style.removeLayer(layer)
                }
                if let layer = style.layer(withIdentifier: "route-layer-\(i)") {
                    style.removeLayer(layer)
                }
                if let source = style.source(withIdentifier: "route-outline-\(i)") {
                    style.removeSource(source)
                }
                if let source = style.source(withIdentifier: "route-source-\(i)") {
                    style.removeSource(source)
                }
            }

            // Add route polylines — active leg is bold, future legs are dimmer
            let activeIdx = parent.currentStopIndex
            let isNav = parent.isNavigating

            for (i, coords) in routes.enumerated() {
                guard coords.count >= 2 else { continue }
                var mutableCoords = coords

                // Add route outline (shadow) for active leg during navigation
                if isNav && i == activeIdx {
                    let outlinePolyline = MLNPolylineFeature(
                        coordinates: &mutableCoords,
                        count: UInt(mutableCoords.count)
                    )
                    let outlineSource = MLNShapeSource(
                        identifier: "route-outline-\(i)",
                        shape: outlinePolyline,
                        options: nil
                    )
                    style.addSource(outlineSource)
                    let outlineLayer = MLNLineStyleLayer(identifier: "route-outline-layer-\(i)", source: outlineSource)
                    outlineLayer.lineColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.3))
                    outlineLayer.lineWidth = NSExpression(forConstantValue: 10)
                    outlineLayer.lineCap = NSExpression(forConstantValue: "round")
                    outlineLayer.lineJoin = NSExpression(forConstantValue: "round")
                    style.addLayer(outlineLayer)
                }

                let polyline = MLNPolylineFeature(
                    coordinates: &mutableCoords,
                    count: UInt(mutableCoords.count)
                )
                let source = MLNShapeSource(
                    identifier: "route-source-\(i)",
                    shape: polyline,
                    options: nil
                )
                style.addSource(source)

                let layer = MLNLineStyleLayer(identifier: "route-layer-\(i)", source: source)
                let isActiveLeg = isNav && i == activeIdx
                let goldColor = UIColor(named: "BrandGold") ?? .systemYellow
                layer.lineColor = NSExpression(forConstantValue: isActiveLeg ? goldColor : goldColor.withAlphaComponent(0.4))
                layer.lineWidth = NSExpression(forConstantValue: isActiveLeg ? 7 : 4)
                layer.lineCap = NSExpression(forConstantValue: "round")
                layer.lineJoin = NSExpression(forConstantValue: "round")
                layer.lineOpacity = NSExpression(forConstantValue: 1.0)
                style.addLayer(layer)
            }

            // Routes drawn — lastRouteTotalCoordCount tracks staleness

            // Fit camera to show all routes
            let allCoords = routes.flatMap { $0 }
            if !allCoords.isEmpty {
                var bounds = MLNCoordinateBounds(sw: allCoords[0], ne: allCoords[0])
                for coord in allCoords {
                    bounds.sw.latitude = min(bounds.sw.latitude, coord.latitude)
                    bounds.sw.longitude = min(bounds.sw.longitude, coord.longitude)
                    bounds.ne.latitude = max(bounds.ne.latitude, coord.latitude)
                    bounds.ne.longitude = max(bounds.ne.longitude, coord.longitude)
                }
                print("[MapLibre] Fitting camera to bounds: sw=(\(bounds.sw.latitude),\(bounds.sw.longitude)) ne=(\(bounds.ne.latitude),\(bounds.ne.longitude))")
                let camera = mapView.cameraThatFitsCoordinateBounds(
                    bounds,
                    edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 200, right: 40)
                )
                mapView.setCamera(camera, animated: true)
            } else if !parent.stops.isEmpty {
                // No routes yet — center on first stop
                let stop = parent.stops[0]
                mapView.setCenter(
                    CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude),
                    zoomLevel: 12,
                    animated: true
                )
                print("[MapLibre] No routes yet, centering on first stop: \(stop.latitude), \(stop.longitude)")
            }
        }

        func updateStopAnnotations(on mapView: MLNMapView) {
            guard mapView.style != nil else { return }
            let stops = parent.stops
            let currentIdx = parent.currentStopIndex

            // Only rebuild when stops change or current index changes
            if stops.count == lastStopCount && currentIdx == lastCurrentStopIndex { return }
            lastStopCount = stops.count
            lastCurrentStopIndex = currentIdx

            // Remove existing annotations
            if let existing = mapView.annotations {
                let nonUserAnnotations = existing.filter { !($0 is MLNUserLocation) }
                if !nonUserAnnotations.isEmpty {
                    mapView.removeAnnotations(nonUserAnnotations)
                }
            }

            // Add stop markers as point annotations
            for stop in stops {
                let point = MLNPointAnnotation()
                point.coordinate = CLLocationCoordinate2D(
                    latitude: stop.latitude, longitude: stop.longitude
                )
                point.title = "\(stop.sequenceOrder + 1). \(stop.name)"
                mapView.addAnnotation(point)
            }
        }

        // Custom annotation views for stop markers
        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard !(annotation is MLNUserLocation) else { return nil }

            let reuseId = "stop-marker"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId)

            if annotationView == nil {
                annotationView = MLNAnnotationView(reuseIdentifier: reuseId)
                annotationView?.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
            }

            // Find the stop index from the title
            if let title = annotation.title ?? nil,
               let orderStr = title.split(separator: ".").first,
               let order = Int(orderStr) {

                let isCurrent = (order - 1) == parent.currentStopIndex
                let isVisited = (order - 1) < parent.currentStopIndex

                let container = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))

                let circle = UIView(frame: container.bounds)
                circle.layer.cornerRadius = 18
                if isCurrent {
                    circle.backgroundColor = UIColor(named: "BrandGold") ?? .systemYellow
                    // Add outer ring
                    let ring = UIView(frame: CGRect(x: -4, y: -4, width: 44, height: 44))
                    ring.layer.cornerRadius = 22
                    ring.layer.borderWidth = 3
                    ring.layer.borderColor = (UIColor(named: "BrandGold") ?? .systemYellow).cgColor
                    ring.backgroundColor = .clear
                    container.addSubview(ring)
                } else if isVisited {
                    circle.backgroundColor = .systemGreen
                } else {
                    circle.backgroundColor = (UIColor(named: "BrandGold") ?? .systemYellow).withAlphaComponent(0.7)
                }
                container.addSubview(circle)

                let label = UILabel(frame: container.bounds)
                label.text = "\(order)"
                label.textAlignment = .center
                label.font = .systemFont(ofSize: 13, weight: .bold)
                label.textColor = .white
                container.addSubview(label)

                annotationView?.subviews.forEach { $0.removeFromSuperview() }
                annotationView?.addSubview(container)
            }

            return annotationView
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
            true
        }
    }
}

// MARK: - Offline MBTiles Loading

extension MapLibreNavigationView {
    /// Creates a MapLibre style JSON referencing a local .mbtiles file.
    /// Call this to generate a local style for fully offline map rendering.
    static func localStyleJSON(mbtilesPath: String, isVector: Bool = true) -> String {
        if isVector {
            return """
            {
                "version": 8,
                "name": "Offline",
                "sources": {
                    "offline": {
                        "type": "vector",
                        "tiles": ["mbtiles://\(mbtilesPath)/{z}/{x}/{y}"],
                        "minzoom": 0,
                        "maxzoom": 14
                    }
                },
                "layers": [
                    {
                        "id": "background",
                        "type": "background",
                        "paint": { "background-color": "#f0ede8" }
                    },
                    {
                        "id": "water",
                        "type": "fill",
                        "source": "offline",
                        "source-layer": "water",
                        "paint": { "fill-color": "#a0c8f0" }
                    },
                    {
                        "id": "roads",
                        "type": "line",
                        "source": "offline",
                        "source-layer": "transportation",
                        "paint": { "line-color": "#ffffff", "line-width": 2 }
                    }
                ]
            }
            """
        } else {
            return """
            {
                "version": 8,
                "name": "Offline Raster",
                "sources": {
                    "offline-raster": {
                        "type": "raster",
                        "tiles": ["mbtiles://\(mbtilesPath)/{z}/{x}/{y}"],
                        "tileSize": 256,
                        "minzoom": 0,
                        "maxzoom": 14
                    }
                },
                "layers": [
                    {
                        "id": "raster-tiles",
                        "type": "raster",
                        "source": "offline-raster"
                    }
                ]
            }
            """
        }
    }
}
