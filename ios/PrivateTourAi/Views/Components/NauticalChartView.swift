import SwiftUI
import WebKit

struct NauticalChartView: UIViewRepresentable {
    let stops: [TourStop]
    let currentStopIndex: Int

    private let apiKey = "2fdb12f93fdd4071a394008e331130fe"

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        loadChart(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Pan to current stop when it changes
        if currentStopIndex >= 0, currentStopIndex < stops.count {
            let stop = stops[currentStopIndex]
            webView.evaluateJavaScript("""
                if (window.map) {
                    map.flyTo({center: [\(stop.longitude), \(stop.latitude)], zoom: 14, pitch: 45, duration: 1500});
                }
            """)
        }
    }

    private func loadChart(_ webView: WKWebView) {
        let centerLat = stops.map(\.latitude).reduce(0, +) / Double(max(stops.count, 1))
        let centerLng = stops.map(\.longitude).reduce(0, +) / Double(max(stops.count, 1))

        let markersJS = stops.enumerated().map { (i, stop) in
            """
            new maplibregl.Marker({color: '\(i == currentStopIndex ? "#FF5151" : "#FFFFFF")'})
                .setLngLat([\(stop.longitude), \(stop.latitude)])
                .setPopup(new maplibregl.Popup().setHTML('<b>\(i + 1). \(stop.name.replacingOccurrences(of: "'", with: "\\'"))</b>'))
                .addTo(map);
            """
        }.joined(separator: "\n")

        // Route line between stops
        let routeCoords = stops.map { "[\($0.longitude), \($0.latitude)]" }.joined(separator: ",")

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
        const map = new maplibregl.Map({
            container: 'map',
            style: 'https://api.vectorcharts.com/api/v1/styles/base.json?token=\(apiKey)&theme=day&depthUnits=feet',
            center: [\(centerLng), \(centerLat)],
            zoom: 13,
            pitch: 30
        });

        map.addControl(new maplibregl.NavigationControl(), 'top-right');

        map.on('load', function() {
            // Route line
            map.addSource('route', {
                'type': 'geojson',
                'data': {
                    'type': 'Feature',
                    'properties': {},
                    'geometry': {
                        'type': 'LineString',
                        'coordinates': [\(routeCoords)]
                    }
                }
            });
            map.addLayer({
                'id': 'route',
                'type': 'line',
                'source': 'route',
                'layout': { 'line-join': 'round', 'line-cap': 'round' },
                'paint': { 'line-color': '#FF5151', 'line-width': 4, 'line-dasharray': [2, 1] }
            });

            // Markers
            \(markersJS)
        });

        window.map = map;
        </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: URL(string: "https://api.vectorcharts.com"))
    }
}
