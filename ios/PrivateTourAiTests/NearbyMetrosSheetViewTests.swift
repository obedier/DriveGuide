import Testing
import SwiftUI
import ViewInspector
@testable import PrivateTourAi

/// ViewInspector-powered tests that verify `NearbyMetrosSheet` renders the
/// correct SwiftUI primitives for each `MetroLookupState` branch.
/// The sheet is fed a stubbed `MetroAreaService` whose state we drive directly,
/// so we exercise the view layer without real CoreLocation calls.

@Suite("Nearby Metros Sheet — view rendering")
@MainActor
struct NearbyMetrosSheetViewTests {

    private func makeService(state: MetroLookupState) -> MetroAreaService {
        // Use a stub that leaves the service in .idle; then force the state.
        let stub = StubLocationProvider(location: nil)
        let service = MetroAreaService(locationProvider: stub)
        service.overrideStateForTesting(state)
        return service
    }

    @Test("Loading state renders a ProgressView with 'Finding nearby cities…' copy")
    func loadingStateRenders() throws {
        let service = makeService(state: .loading)
        let sheet = NearbyMetrosSheet(service: service)
            .environmentObject(TourViewModel())

        let text = try sheet.inspect().find(text: "Finding nearby cities…")
        _ = try text.string()
        _ = try sheet.inspect().find(ViewType.ProgressView.self)
    }

    @Test("PermissionDenied state renders Open Settings button")
    func permissionDeniedRendersSettings() throws {
        let service = makeService(state: .permissionDenied)
        let sheet = NearbyMetrosSheet(service: service)
            .environmentObject(TourViewModel())

        let settings = try sheet.inspect().find(button: "Open Settings")
        #expect(try settings.labelView().text().string() == "Open Settings")
    }

    @Test("Loaded state renders one row per metro with distance label")
    func loadedStateRendersRows() throws {
        let miami = MetroAreaService.MetroWithDistance(
            metro: MetroArea(name: "Miami", state: "FL", country: "US", lat: 25.76, lng: -80.19),
            distanceMiles: 0
        )
        let ftl = MetroAreaService.MetroWithDistance(
            metro: MetroArea(name: "Fort Lauderdale", state: "FL", country: "US", lat: 26.12, lng: -80.13),
            distanceMiles: 23
        )
        let service = makeService(state: .loaded(metros: [miami, ftl], fallback: false))
        let sheet = NearbyMetrosSheet(service: service)
            .environmentObject(TourViewModel())

        _ = try sheet.inspect().find(text: "Miami")
        _ = try sheet.inspect().find(text: "Fort Lauderdale")
        _ = try sheet.inspect().find(text: "23 mi")
    }

    @Test("LocationUnavailable state renders Retry button")
    func locationUnavailableRendersRetry() throws {
        let service = makeService(state: .locationUnavailable)
        let sheet = NearbyMetrosSheet(service: service)
            .environmentObject(TourViewModel())

        _ = try sheet.inspect().find(button: "Retry")
        _ = try sheet.inspect().find(text: "Can't find your location right now")
    }

    @Test("Fallback flag surfaces the 'Currently US cities only' banner")
    func fallbackBanner() throws {
        let ny = MetroAreaService.MetroWithDistance(
            metro: MetroArea(name: "New York", state: "NY", country: "US", lat: 40.71, lng: -74.01),
            distanceMiles: 3800
        )
        let service = makeService(state: .loaded(metros: [ny], fallback: true))
        let sheet = NearbyMetrosSheet(service: service)
            .environmentObject(TourViewModel())

        _ = try sheet.inspect().find(text: "Currently US cities only")
    }
}
