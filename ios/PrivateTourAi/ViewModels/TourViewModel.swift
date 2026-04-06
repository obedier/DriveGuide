import Foundation
import SwiftUI
import CoreLocation

@MainActor
class TourViewModel: ObservableObject {
    // Tour state
    @Published var currentPreview: TourPreview?
    @Published var currentTour: Tour?

    // Location verification state
    @Published var verifiedLocation: VerifiedLocation?
    @Published var isVerifying = false
    @Published var isLocationConfirmed = false

    // Generation state
    @Published var isGenerating = false
    @Published var generationProgress: String = ""
    @Published var error: String?

    // Input state
    @Published var searchText = ""
    @Published var selectedDuration: Int = 60
    @Published var selectedThemes: Set<String> = []

    let durations = [30, 60, 90, 120, 180, 240, 360]
    let availableThemes = ["history", "food", "scenic", "hidden-gems", "architecture", "culture", "nature", "nightlife"]

    private let locationManager = LocationHelper()

    // MARK: - Step 1: Verify Location

    func verifyLocation() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            error = "Please enter a location"
            return
        }

        isVerifying = true
        error = nil
        verifiedLocation = nil
        isLocationConfirmed = false
        currentPreview = nil
        currentTour = nil

        do {
            let loc = try await APIClient.shared.verifyLocation(query)
            verifiedLocation = loc
        } catch {
            self.error = friendlyError(error)
        }

        isVerifying = false
    }

    // MARK: - Step 2: Confirm and Generate

    func confirmAndGenerate() async {
        guard verifiedLocation != nil else { return }
        isLocationConfirmed = true
        await generatePreview()
    }

    func generatePreview() async {
        let location = verifiedLocation?.formattedAddress ?? searchText
        guard !location.isEmpty else { return }

        isGenerating = true
        error = nil
        generationProgress = "Researching the area..."

        do {
            generationProgress = "Finding the best stops..."
            let preview = try await APIClient.shared.generatePreview(
                location: location,
                durationMinutes: selectedDuration,
                themes: Array(selectedThemes)
            )

            generationProgress = "Tour ready!"
            currentPreview = preview
        } catch {
            self.error = friendlyError(error)
        }

        isGenerating = false
        generationProgress = ""
    }

    // MARK: - Current Location

    func useCurrentLocation() {
        locationManager.requestLocation { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let name):
                    self.searchText = name
                    await self.verifyLocation()
                case .failure(let err):
                    self.error = "Could not get your location: \(err.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Helpers

    func clearTour() {
        currentPreview = nil
        currentTour = nil
        verifiedLocation = nil
        isLocationConfirmed = false
        error = nil
    }

    func openInGoogleMaps() {
        guard let url = currentTour?.mapsDirectionsUrl,
              let mapsUrl = URL(string: url) else { return }
        UIApplication.shared.open(mapsUrl)
    }

    private func friendlyError(_ error: Error) -> String {
        if let apiErr = error as? APIError {
            return apiErr.localizedDescription
        }
        let msg = error.localizedDescription
        if msg.contains("timed out") {
            return "Request timed out. The server might be busy — please try again."
        }
        return msg
    }
}

// MARK: - Location Helper (handles CLLocationManager delegate on main thread)

class LocationHelper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((Result<String, Error>) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation(completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion
        manager.requestWhenInUseAuthorization()

        // If we already have a location, use it immediately
        if let loc = manager.location, loc.timestamp.timeIntervalSinceNow > -60 {
            reverseGeocode(loc)
            return
        }

        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        reverseGeocode(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?(.failure(error))
        completion = nil
    }

    private func reverseGeocode(_ location: CLLocation) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let error {
                self?.completion?(.failure(error))
            } else if let pm = placemarks?.first {
                let name = [pm.subLocality, pm.locality, pm.administrativeArea]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                self?.completion?(.success(name.isEmpty ? "\(location.coordinate.latitude),\(location.coordinate.longitude)" : name))
            } else {
                self?.completion?(.success("\(location.coordinate.latitude),\(location.coordinate.longitude)"))
            }
            self?.completion = nil
        }
    }
}
