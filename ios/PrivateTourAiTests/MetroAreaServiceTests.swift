import Testing
import CoreLocation
@testable import PrivateTourAi

@Suite("Metro Area Service")
@MainActor
struct MetroAreaServiceTests {

    @Test("Bundled JSON loads at least 60 metros")
    func jsonLoads() {
        let service = MetroAreaService()
        let miami = CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
        let near = service.nearestMetros(to: miami, inCountry: "US", count: 100)
        #expect(near.count >= 60, "Expected at least 60 US metros in bundled data")
    }

    @Test("Nearest to Miami surfaces Miami first")
    func nearestToMiami() {
        let service = MetroAreaService()
        let miami = CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
        let top3 = service.nearestMetros(to: miami, inCountry: "US", count: 3)
        #expect(top3.count == 3)
        #expect(top3[0].metro.name == "Miami")
        #expect(top3[0].distanceMiles < 10, "Miami should be ~0 mi from Miami")
    }

    @Test("Nearest to Weston FL includes Miami / Fort Lauderdale / West Palm Beach")
    func nearestToWeston() {
        let service = MetroAreaService()
        let weston = CLLocationCoordinate2D(latitude: 26.1003, longitude: -80.3995)
        let top3 = service.nearestMetros(to: weston, inCountry: "US", count: 3)
        #expect(top3.count == 3)
        let names = Set(top3.map { $0.metro.name })
        // Fort Lauderdale should be closest since Weston is a suburb
        #expect(names.contains("Fort Lauderdale") || names.contains("Miami"))
    }

    @Test("Nearest to Seattle includes Seattle + Portland")
    func nearestToSeattle() {
        let service = MetroAreaService()
        let seattle = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        let top3 = service.nearestMetros(to: seattle, inCountry: "US", count: 3)
        #expect(top3[0].metro.name == "Seattle")
        let names = Set(top3.map { $0.metro.name })
        #expect(names.contains("Portland"))
    }

    @Test("Distance computation is roughly correct (Miami to New York ~1090 mi)")
    func distanceIsReasonable() {
        let service = MetroAreaService()
        let miami = CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
        let all = service.nearestMetros(to: miami, inCountry: "US", count: 100)
        guard let ny = all.first(where: { $0.metro.name == "New York" }) else {
            Issue.record("New York not in results")
            return
        }
        #expect(ny.distanceMiles > 900 && ny.distanceMiles < 1300, "Miami → NY should be ~1090 mi, got \(ny.distanceMiles)")
    }

    @Test("All metros have non-empty image URLs")
    func allHaveImages() {
        let service = MetroAreaService()
        let anywhere = CLLocationCoordinate2D(latitude: 40.0, longitude: -100.0)
        let all = service.nearestMetros(to: anywhere, inCountry: "US", count: 100)
        for item in all {
            #expect(!item.metro.image.isEmpty, "\(item.metro.name) missing image URL")
            #expect(item.metro.imageURL != nil, "\(item.metro.name) image is not a valid URL")
        }
    }

    @Test("MetroArea id is unique per metro")
    func idsUnique() {
        let service = MetroAreaService()
        let anywhere = CLLocationCoordinate2D(latitude: 40.0, longitude: -100.0)
        let all = service.nearestMetros(to: anywhere, inCountry: "US", count: 100)
        let ids = all.map { $0.metro.id }
        #expect(Set(ids).count == ids.count, "Duplicate metro ids found")
    }
}
