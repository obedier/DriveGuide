import Testing
import CoreLocation
@testable import PrivateTourAi

// MARK: - OSRM Instruction Building Tests

@Suite("OSRM Instruction Building")
struct OSRMInstructionTests {

    @Test("Turn left instruction")
    func turnLeftInstruction() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "turn", maneuverModifier: "left", streetName: "Main Street"
        )
        #expect(instruction == "Turn left onto Main Street")
    }

    @Test("Turn right instruction")
    func turnRightInstruction() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "turn", maneuverModifier: "right", streetName: "Broadway"
        )
        #expect(instruction == "Turn right onto Broadway")
    }

    @Test("Sharp left turn")
    func sharpLeftInstruction() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "turn", maneuverModifier: "sharp left", streetName: "Park Ave"
        )
        #expect(instruction == "Turn sharp left onto Park Ave")
    }

    @Test("Depart instruction with street")
    func departInstruction() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "depart", maneuverModifier: nil, streetName: "Oak Avenue"
        )
        #expect(instruction == "Head onto Oak Avenue")
    }

    @Test("Depart instruction without street")
    func departNoStreet() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "depart", maneuverModifier: nil, streetName: ""
        )
        #expect(instruction == "Head")
    }

    @Test("Arrive instruction")
    func arriveInstruction() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "arrive", maneuverModifier: nil, streetName: ""
        )
        #expect(instruction == "Arrive at destination")
    }

    @Test("Continue with new name")
    func continueNewName() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "new name", maneuverModifier: nil, streetName: "Highway 1"
        )
        #expect(instruction == "Continue onto Highway 1")
    }

    @Test("Fork instruction")
    func forkInstruction() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "fork", maneuverModifier: "slight right", streetName: "I-95"
        )
        #expect(instruction == "Take the slight right fork onto I-95")
    }

    @Test("Roundabout instruction")
    func roundaboutInstruction() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "roundabout", maneuverModifier: nil, streetName: "Circle Drive"
        )
        #expect(instruction == "Enter roundabout onto Circle Drive")
    }

    @Test("Rotary instruction (alias for roundabout)")
    func rotaryInstruction() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "rotary", maneuverModifier: nil, streetName: "Traffic Circle"
        )
        #expect(instruction == "Enter roundabout onto Traffic Circle")
    }

    @Test("Merge instruction")
    func mergeInstruction() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "merge", maneuverModifier: nil, streetName: "Interstate 95"
        )
        #expect(instruction == "Merge onto Interstate 95")
    }

    @Test("End of road instruction")
    func endOfRoad() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "end of road", maneuverModifier: "right", streetName: "Elm Street"
        )
        #expect(instruction == "At end of road, turn right onto Elm Street")
    }

    @Test("Continue instruction")
    func continueInstruction() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "continue", maneuverModifier: "straight", streetName: "Main Road"
        )
        #expect(instruction == "Continue straight onto Main Road")
    }

    @Test("Unknown type with modifier capitalizes first word")
    func unknownTypeWithModifier() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "notification", maneuverModifier: "slight left", streetName: "Road"
        )
        // .capitalized capitalizes each word: "slight left" → "Slight Left"
        #expect(instruction == "Slight Left onto Road")
    }

    @Test("Unknown type without modifier returns empty")
    func unknownTypeNoModifier() {
        let instruction = OSRMRouteParser.buildInstruction(
            maneuverType: "notification", maneuverModifier: nil, streetName: "Road"
        )
        #expect(instruction.isEmpty)
    }

    @Test("Build from OSRMStep struct")
    func buildFromStep() {
        let step = OSRMStep(
            maneuver: OSRMManeuver(type: "turn", modifier: "left", location: [-80.1, 26.1]),
            name: "Main St",
            distance: 500,
            duration: 60,
            geometry: OSRMGeometry(coordinates: [])
        )
        let instruction = OSRMRouteParser.buildInstruction(step)
        #expect(instruction == "Turn left onto Main St")
    }
}

// MARK: - OSRM Profile Selection Tests

@Suite("OSRM Profile Selection")
struct OSRMProfileTests {

    @Test("Car transport mode maps to driving")
    func carProfile() {
        #expect(OSRMRouteParser.osrmProfile(for: "car") == "driving")
    }

    @Test("Default/unknown mode maps to driving")
    func defaultProfile() {
        #expect(OSRMRouteParser.osrmProfile(for: "") == "driving")
        #expect(OSRMRouteParser.osrmProfile(for: "boat") == "driving")
    }

    @Test("Walk transport mode maps to foot")
    func walkProfile() {
        #expect(OSRMRouteParser.osrmProfile(for: "walk") == "foot")
    }

    @Test("Bike transport mode maps to bike")
    func bikeProfile() {
        #expect(OSRMRouteParser.osrmProfile(for: "bike") == "bike")
    }
}

// MARK: - OSRM Response Parsing Tests

@Suite("OSRM Response Parsing")
struct OSRMResponseParsingTests {

    private static let validRouteJSON = """
    {
        "routes": [{
            "geometry": {
                "coordinates": [[-80.1, 26.1], [-80.2, 26.2], [-80.3, 26.3]]
            },
            "legs": [{
                "steps": [{
                    "maneuver": {"type": "depart", "modifier": null, "location": [-80.1, 26.1]},
                    "name": "Start Road",
                    "distance": 500,
                    "duration": 60,
                    "geometry": {"coordinates": [[-80.1, 26.1], [-80.2, 26.2]]}
                }, {
                    "maneuver": {"type": "turn", "modifier": "left", "location": [-80.2, 26.2]},
                    "name": "Main Street",
                    "distance": 300,
                    "duration": 45,
                    "geometry": {"coordinates": [[-80.2, 26.2], [-80.3, 26.3]]}
                }, {
                    "maneuver": {"type": "arrive", "modifier": null, "location": [-80.3, 26.3]},
                    "name": "",
                    "distance": 0,
                    "duration": 0,
                    "geometry": {"coordinates": [[-80.3, 26.3]]}
                }]
            }],
            "distance": 800,
            "duration": 105
        }]
    }
    """

    @Test("Parse valid OSRM route response")
    func parseValidResponse() throws {
        let data = Self.validRouteJSON.data(using: .utf8)!
        let leg = try OSRMRouteParser.parseResponse(data: data)

        #expect(leg != nil)
        #expect(leg!.coordinates.count == 3)
        #expect(leg!.totalDistance == 800)
        #expect(leg!.totalDuration == 105)

        // Verify coordinate order (OSRM gives [lng, lat], we convert to CLLocationCoordinate2D)
        #expect(leg!.coordinates[0].latitude == 26.1)
        #expect(leg!.coordinates[0].longitude == -80.1)
        #expect(leg!.coordinates[2].latitude == 26.3)
        #expect(leg!.coordinates[2].longitude == -80.3)
    }

    @Test("Parsed steps have correct instructions")
    func parsedStepInstructions() throws {
        let data = Self.validRouteJSON.data(using: .utf8)!
        let leg = try OSRMRouteParser.parseResponse(data: data)!

        // "depart" → "Head onto Start Road", "turn left" → "Turn left onto Main Street", "arrive" → "Arrive at destination"
        #expect(leg.steps.count == 3)
        #expect(leg.steps[0].instruction == "Head onto Start Road")
        #expect(leg.steps[1].instruction == "Turn left onto Main Street")
        #expect(leg.steps[2].instruction == "Arrive at destination")
    }

    @Test("Parsed steps have correct distances")
    func parsedStepDistances() throws {
        let data = Self.validRouteJSON.data(using: .utf8)!
        let leg = try OSRMRouteParser.parseResponse(data: data)!

        #expect(leg.steps[0].distance == 500)
        #expect(leg.steps[1].distance == 300)
    }

    @Test("Parsed steps have correct maneuver locations")
    func parsedStepManeuverLocations() throws {
        let data = Self.validRouteJSON.data(using: .utf8)!
        let leg = try OSRMRouteParser.parseResponse(data: data)!

        #expect(leg.steps[0].maneuverLocation.latitude == 26.1)
        #expect(leg.steps[0].maneuverLocation.longitude == -80.1)
        #expect(leg.steps[1].maneuverLocation.latitude == 26.2)
        #expect(leg.steps[1].maneuverLocation.longitude == -80.2)
    }

    @Test("Parse empty routes returns nil")
    func parseEmptyRoutes() throws {
        let data = "{ \"routes\": [] }".data(using: .utf8)!
        let leg = try OSRMRouteParser.parseResponse(data: data)
        #expect(leg == nil)
    }

    @Test("Parse invalid JSON throws")
    func parseInvalidJSON() {
        let data = "not json".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try OSRMRouteParser.parseResponse(data: data)
        }
    }

    @Test("Steps with empty instructions are filtered out")
    func emptyInstructionsFiltered() throws {
        let json = """
        {
            "routes": [{
                "geometry": {"coordinates": [[-80.1, 26.1]]},
                "legs": [{
                    "steps": [{
                        "maneuver": {"type": "notification", "modifier": null, "location": [-80.1, 26.1]},
                        "name": "",
                        "distance": 0,
                        "duration": 0,
                        "geometry": {"coordinates": [[-80.1, 26.1]]}
                    }]
                }],
                "distance": 0,
                "duration": 0
            }]
        }
        """.data(using: .utf8)!

        let leg = try OSRMRouteParser.parseResponse(data: json)!
        #expect(leg.steps.isEmpty)
    }

    @Test("Malformed coordinates with fewer than 2 elements are skipped")
    func malformedCoordinatesSkipped() throws {
        let json = """
        {
            "routes": [{
                "geometry": {"coordinates": [[-80.1], [-80.2, 26.2], []]},
                "legs": [{"steps": []}],
                "distance": 100,
                "duration": 10
            }]
        }
        """.data(using: .utf8)!

        let leg = try OSRMRouteParser.parseResponse(data: json)!
        // Only the valid [lng, lat] pair should survive
        #expect(leg.coordinates.count == 1)
        #expect(leg.coordinates[0].latitude == 26.2)
    }

    @Test("Steps with malformed maneuver locations are skipped")
    func malformedManeuverLocationSkipped() throws {
        let json = """
        {
            "routes": [{
                "geometry": {"coordinates": [[-80.1, 26.1]]},
                "legs": [{
                    "steps": [{
                        "maneuver": {"type": "turn", "modifier": "left", "location": [-80.1]},
                        "name": "Bad Street",
                        "distance": 100,
                        "duration": 10,
                        "geometry": {"coordinates": [[-80.1, 26.1]]}
                    }]
                }],
                "distance": 100,
                "duration": 10
            }]
        }
        """.data(using: .utf8)!

        let leg = try OSRMRouteParser.parseResponse(data: json)!
        #expect(leg.steps.isEmpty) // Step skipped due to malformed location
    }
}

// MARK: - Navigation State Management Tests

@Suite("Navigation State Management")
@MainActor
struct NavigationStateTests {

    @Test("Initial state is not navigating")
    func initialState() {
        let service = FerrostarNavigationService()
        #expect(!service.isNavigating)
        #expect(!service.arrivedAtStop)
        #expect(service.currentStepInstruction.isEmpty)
        #expect(service.routeCoordinates.isEmpty)
        #expect(service.distanceToNextStop == 0)
        #expect(service.etaToNextStop == 0)
        #expect(service.userLocation == nil)
    }

    @Test("Stop navigation resets state")
    func stopNavigation() {
        let service = FerrostarNavigationService()
        service.isNavigating = true
        service.currentStepInstruction = "Turn left"
        service.stopNavigation()
        #expect(!service.isNavigating)
        #expect(service.currentStepInstruction.isEmpty)
    }

    @Test("Routing base URL default is OSRM public server")
    func defaultRoutingURL() {
        let service = FerrostarNavigationService()
        #expect(service.routingBaseURL == "https://router.project-osrm.org")
    }

    @Test("Routing base URL is configurable for local Valhalla")
    func configurableRoutingURL() {
        let service = FerrostarNavigationService()
        service.routingBaseURL = "http://localhost:5000"
        #expect(service.routingBaseURL == "http://localhost:5000")
    }
}

// MARK: - FeatureFlags Tests

@Suite("Feature Flags")
struct FeatureFlagTests {

    @Test("Apple engine returns false for ferrostar flag")
    func appleEngineNotFerrostar() {
        UserDefaults.standard.set("apple", forKey: "navigationEngine")
        #expect(!FeatureFlags.useFerrostarNavigation)
    }

    @Test("Ferrostar flag reads correctly when set")
    func ferrostarFlag() {
        UserDefaults.standard.set("ferrostar", forKey: "navigationEngine")
        #expect(FeatureFlags.useFerrostarNavigation)
        UserDefaults.standard.removeObject(forKey: "navigationEngine")
    }

    @Test("Apple flag returns false for ferrostar check")
    func appleNotFerrostar() {
        UserDefaults.standard.set("apple", forKey: "navigationEngine")
        #expect(!FeatureFlags.useFerrostarNavigation)
        UserDefaults.standard.removeObject(forKey: "navigationEngine")
    }
}

// MARK: - Route Model Types Tests

@Suite("Route Model Types")
struct RouteModelTests {

    @Test("RouteLeg stores coordinates and metrics")
    func routeLegData() {
        let coords = [
            CLLocationCoordinate2D(latitude: 26.1, longitude: -80.1),
            CLLocationCoordinate2D(latitude: 26.2, longitude: -80.2),
            CLLocationCoordinate2D(latitude: 26.3, longitude: -80.3)
        ]
        let steps = [
            RouteStepInfo(
                instruction: "Head onto Main St",
                distance: 500, duration: 60,
                maneuverLocation: coords[0],
                maneuverType: "depart", maneuverModifier: nil
            )
        ]
        let leg = RouteLeg(coordinates: coords, steps: steps, totalDistance: 1000, totalDuration: 120)

        #expect(leg.coordinates.count == 3)
        #expect(leg.steps.count == 1)
        #expect(leg.totalDistance == 1000)
        #expect(leg.totalDuration == 120)
    }

    @Test("RouteStepInfo stores all fields")
    func routeStepFields() {
        let step = RouteStepInfo(
            instruction: "Turn left onto Main Street",
            distance: 500, duration: 60,
            maneuverLocation: CLLocationCoordinate2D(latitude: 26.15, longitude: -80.15),
            maneuverType: "turn", maneuverModifier: "left"
        )
        #expect(step.instruction == "Turn left onto Main Street")
        #expect(step.distance == 500)
        #expect(step.duration == 60)
        #expect(step.maneuverType == "turn")
        #expect(step.maneuverModifier == "left")
        #expect(step.maneuverLocation.latitude == 26.15)
    }
}

// MARK: - MapLibre Offline Style JSON Tests

@Suite("MapLibre Offline Style")
struct OfflineStyleTests {

    @Test("Vector style JSON is valid and contains required fields")
    func vectorStyleJSON() {
        let json = MapLibreNavigationView.localStyleJSON(mbtilesPath: "/data/tiles.mbtiles", isVector: true)
        #expect(json.contains("\"version\": 8"))
        #expect(json.contains("\"type\": \"vector\""))
        #expect(json.contains("mbtiles:///data/tiles.mbtiles"))
        #expect(json.contains("\"water\""))
        #expect(json.contains("\"roads\""))
        #expect(json.contains("\"background\""))
    }

    @Test("Raster style JSON is valid and contains required fields")
    func rasterStyleJSON() {
        let json = MapLibreNavigationView.localStyleJSON(mbtilesPath: "/data/raster.mbtiles", isVector: false)
        #expect(json.contains("\"version\": 8"))
        #expect(json.contains("\"type\": \"raster\""))
        #expect(json.contains("mbtiles:///data/raster.mbtiles"))
        #expect(json.contains("\"tileSize\": 256"))
        #expect(json.contains("\"raster-tiles\""))
    }

    @Test("Default style URL points to OpenFreeMap")
    func defaultStyleURL() {
        let url = MapLibreNavigationView.defaultStyleURL
        #expect(url.absoluteString.contains("openfreemap"))
    }
}

// MARK: - OSRM Model Decodable Tests

@Suite("OSRM Model Decoding")
struct OSRMModelDecodingTests {

    @Test("OSRMManeuver decodes correctly")
    func decodeManeuver() throws {
        let json = """
        {"type": "turn", "modifier": "left", "location": [-80.1, 26.1]}
        """.data(using: .utf8)!
        let maneuver = try JSONDecoder().decode(OSRMManeuver.self, from: json)
        #expect(maneuver.type == "turn")
        #expect(maneuver.modifier == "left")
        #expect(maneuver.location == [-80.1, 26.1])
    }

    @Test("OSRMManeuver decodes null modifier")
    func decodeNullModifier() throws {
        let json = """
        {"type": "depart", "modifier": null, "location": [0, 0]}
        """.data(using: .utf8)!
        let maneuver = try JSONDecoder().decode(OSRMManeuver.self, from: json)
        #expect(maneuver.modifier == nil)
    }

    @Test("OSRMGeometry decodes coordinates")
    func decodeGeometry() throws {
        let json = """
        {"coordinates": [[-80.1, 26.1], [-80.2, 26.2]]}
        """.data(using: .utf8)!
        let geo = try JSONDecoder().decode(OSRMGeometry.self, from: json)
        #expect(geo.coordinates.count == 2)
        #expect(geo.coordinates[0] == [-80.1, 26.1])
    }

    @Test("Full OSRMResponse decodes")
    func decodeFullResponse() throws {
        let json = """
        {
            "routes": [{
                "geometry": {"coordinates": [[-80.1, 26.1]]},
                "legs": [{"steps": []}],
                "distance": 1000,
                "duration": 120
            }]
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(OSRMResponse.self, from: json)
        #expect(response.routes.count == 1)
        #expect(response.routes[0].distance == 1000)
        #expect(response.routes[0].duration == 120)
    }
}
