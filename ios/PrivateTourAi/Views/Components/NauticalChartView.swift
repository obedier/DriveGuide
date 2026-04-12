import SwiftUI
import WebKit

struct NauticalChartView: UIViewRepresentable {
    let stops: [TourStop]
    let currentStopIndex: Int

    private let apiKey = "2fdb12f93fdd4071a394008e331130fe"

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: UIScreen.main.bounds, configuration: config)
        webView.isOpaque = true
        webView.backgroundColor = UIColor(red: 0.15, green: 0.18, blue: 0.25, alpha: 1) // dark navy matching app
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        loadChart(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if currentStopIndex >= 0, currentStopIndex < stops.count {
            let stop = stops[currentStopIndex]
            webView.evaluateJavaScript("""
                if (window.map) {
                    map.flyTo({center: [\(stop.longitude), \(stop.latitude)], zoom: 14, pitch: 45, duration: 1500});
                    // Highlight current marker
                    if (window.markers) {
                        window.markers.forEach(function(m, i) {
                            m.getElement().style.opacity = i === \(currentStopIndex) ? '1' : '0.6';
                            m.getElement().style.transform = i === \(currentStopIndex) ? 'scale(1.3)' : 'scale(1)';
                        });
                    }
                }
            """)
        }
    }

    private func loadChart(_ webView: WKWebView) {
        let centerLat = stops.map(\.latitude).reduce(0, +) / Double(max(stops.count, 1))
        let centerLng = stops.map(\.longitude).reduce(0, +) / Double(max(stops.count, 1))

        let markersJS = stops.enumerated().map { (i, stop) in
            let color = i == 0 || i == stops.count - 1 ? "#22C55E" : "#FF5151"
            return """
            (function() {
                var el = document.createElement('div');
                el.style.cssText = 'width:32px;height:32px;border-radius:50%;background:\(color);color:white;display:flex;align-items:center;justify-content:center;font-weight:bold;font-size:14px;border:2px solid white;box-shadow:0 2px 6px rgba(0,0,0,0.3);';
                el.textContent = '\(i + 1)';
                var marker = new maplibregl.Marker({element: el})
                    .setLngLat([\(stop.longitude), \(stop.latitude)])
                    .setPopup(new maplibregl.Popup({offset: 20}).setHTML('<b>\(stop.name.replacingOccurrences(of: "'", with: "\\'"))</b>'))
                    .addTo(map);
                window.markers.push(marker);
            })();
            """
        }.joined(separator: "\n")

        // Build waypoints array for VectorCharts routing API
        let waypointsJSON = stops.map { "[\($0.latitude), \($0.longitude)]" }.joined(separator: ",")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <script src="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js"></script>
        <link href="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css" rel="stylesheet">
        <style>
            body { margin: 0; padding: 0; }
            #map { width: 100%; height: 100vh; }
        </style>
        </head>
        <body>
        <div id="map"></div>
        <script>
        window.markers = [];

        const map = new maplibregl.Map({
            container: 'map',
            style: 'https://api.vectorcharts.com/api/v1/styles/base.json?token=\(apiKey)&theme=day&depthUnits=feet',
            center: [\(centerLng), \(centerLat)],
            zoom: 13,
            pitch: 30
        });

        map.addControl(new maplibregl.NavigationControl(), 'top-right');

        map.on('load', function() {
            // Add markers
            \(markersJS)

            // Fetch waterway route from VectorCharts routing API
            fetch('https://api.vectorcharts.com/api/v1/routing/route?token=\(apiKey)', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({waypoints: [\(waypointsJSON)]})
            })
            .then(r => r.json())
            .then(data => {
                if (data.success && data.route && data.route.length > 0) {
                    // Draw the actual waterway route
                    var coords = data.route.map(function(p) { return [p[1], p[0]]; }); // [lng, lat]
                    map.addSource('route', {
                        type: 'geojson',
                        data: {
                            type: 'Feature',
                            properties: {},
                            geometry: { type: 'LineString', coordinates: coords }
                        }
                    });
                    map.addLayer({
                        id: 'route-bg',
                        type: 'line',
                        source: 'route',
                        paint: { 'line-color': '#ffffff', 'line-width': 6, 'line-opacity': 0.6 }
                    });
                    map.addLayer({
                        id: 'route',
                        type: 'line',
                        source: 'route',
                        layout: { 'line-join': 'round', 'line-cap': 'round' },
                        paint: { 'line-color': '#FF5151', 'line-width': 3 }
                    });
                }
                // If routing fails, just show markers without route line
            })
            .catch(function() {
                // Routing unavailable — show markers only, no confusing lines
            });
        });

        window.map = map;
        </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: URL(string: "https://api.vectorcharts.com"))
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[NauticalChart] ✅ WebView finished loading")
            // Check for JS errors
            webView.evaluateJavaScript("window.map ? 'map-ok' : 'map-nil'") { result, error in
                if let error { print("[NauticalChart] JS error: \(error)") }
                else { print("[NauticalChart] Map state: \(result ?? "unknown")") }
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[NauticalChart] ❌ Navigation failed: \(error)")
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[NauticalChart] ❌ Provisional navigation failed: \(error)")
        }
    }
}
