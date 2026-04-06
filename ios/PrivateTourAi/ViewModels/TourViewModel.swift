import Foundation
import SwiftUI
import CoreLocation

@MainActor
class TourViewModel: ObservableObject {
    // Tour state
    @Published var currentPreview: TourPreview?
    @Published var currentTour: Tour?
    @Published var lastPreviewTourId: String?
    @Published var showTourDetail = false

    // Saved tours
    @Published var savedTours: [Tour] = []

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
    @Published var transportMode: String = "car"
    @Published var speedMph: Double? = nil
    @Published var customPrompt: String = ""
    @Published var showAdvancedSettings = false

    let durations = [30, 60, 90, 120, 180, 240, 360]
    let availableThemes = ["history", "food", "scenic", "hidden-gems", "architecture", "culture", "nature", "nightlife"]
    let transportModes = ["car", "walk", "bike", "boat", "plane"]

    private let locationManager = LocationHelper()
    private let storage = TourStorage.shared

    init() {
        savedTours = storage.loadAll()
    }

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
        // Dismiss keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        await generatePreview()
    }

    func generatePreview() async {
        let location = verifiedLocation?.formattedAddress ?? searchText
        guard !location.isEmpty else { return }

        isGenerating = true
        error = nil

        let locationName = searchText
        let progressMessages = [
            "Researching \(locationName)...",
            "Scanning local landmarks and hidden gems...",
            "Checking what's open and worth visiting...",
            "Talking to our AI guide about the best routes...",
            "Selecting stops that tell a great story...",
            "Building the perfect narrative arc...",
            "Optimizing the driving route...",
            "Crafting narration for each stop...",
            "Adding insider tips and local secrets...",
            "Polishing your personalized tour...",
        ]

        let progressTask = Task {
            for (i, msg) in progressMessages.enumerated() {
                if Task.isCancelled { break }
                generationProgress = msg
                let delay = i < 2 ? 2.0 : (i < 5 ? 4.0 : 6.0)
                try? await Task.sleep(for: .seconds(delay))
            }
        }

        do {
            let result = try await APIClient.shared.generatePreview(
                location: location,
                durationMinutes: selectedDuration,
                themes: Array(selectedThemes),
                transportMode: transportMode,
                speedMph: speedMph,
                customPrompt: customPrompt.isEmpty ? nil : customPrompt
            )
            progressTask.cancel()
            generationProgress = "Your tour is ready!"
            currentPreview = result.preview
            lastPreviewTourId = result.tourId

            // Auto-save full tour to library immediately
            if let tourId = result.tourId {
                Task {
                    if let tour = try? await APIClient.shared.getFullTour(tourId: tourId) {
                        storage.save(tour)
                        savedTours = storage.loadAll()
                    }
                }
            }
            try? await Task.sleep(for: .seconds(0.5))
        } catch {
            progressTask.cancel()
            self.error = friendlyError(error)
        }

        isGenerating = false
        generationProgress = ""
    }

    // MARK: - Unlock Full Tour

    func unlockFullTour() async {
        isGenerating = true
        error = nil
        generationProgress = "Loading your complete tour..."

        do {
            let tour: Tour
            if let tourId = lastPreviewTourId {
                generationProgress = "Fetching all stops and narration..."
                tour = try await APIClient.shared.getFullTour(tourId: tourId)
            } else {
                let location = verifiedLocation?.formattedAddress ?? searchText
                generationProgress = "Generating your full tour..."
                tour = try await APIClient.shared.generateFullTour(
                    location: location,
                    durationMinutes: selectedDuration,
                    themes: Array(selectedThemes)
                )
            }

            // Save to local storage
            storage.save(tour)
            savedTours = storage.loadAll()

            currentTour = tour
            currentPreview = nil
            showTourDetail = true
            generationProgress = ""
        } catch {
            self.error = friendlyError(error)
        }

        isGenerating = false
        generationProgress = ""
    }

    // MARK: - Saved Tours

    // Library uses its own sheet — this just sets the tour
    func openSavedTour(_ tour: Tour) {
        currentTour = tour
        currentPreview = nil
    }

    func deleteSavedTour(_ tour: Tour) {
        storage.delete(tour.id)
        savedTours = storage.loadAll()
        if currentTour?.id == tour.id {
            currentTour = nil
            showTourDetail = false
        }
    }

    // MARK: - Start Tour (open in Google Maps)

    func startTour() {
        guard let tour = currentTour,
              let urlStr = tour.mapsDirectionsUrl,
              let url = URL(string: urlStr) else {
            error = "No tour route available"
            return
        }

        // Try Google Maps app first, fall back to Apple Maps / browser
        let googleMapsURL = URL(string: "comgooglemaps://?\(url.query ?? "")")
        if let gmUrl = googleMapsURL, UIApplication.shared.canOpenURL(gmUrl) {
            UIApplication.shared.open(gmUrl)
        } else {
            UIApplication.shared.open(url)
        }
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

    // MARK: - Share

    func shareTour() -> URL? {
        guard let shareId = currentTour?.shareId else { return nil }
        return URL(string: "https://privatetourai.app/tour/\(shareId)")
    }

    func clearTour() {
        currentPreview = nil
        currentTour = nil
        lastPreviewTourId = nil
        verifiedLocation = nil
        isLocationConfirmed = false
        showTourDetail = false
        error = nil
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

// MARK: - Local Tour Storage (persists tours as JSON files)

class TourStorage {
    static let shared = TourStorage()

    private let directory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("SavedTours", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func save(_ tour: Tour) {
        let url = directory.appendingPathComponent("\(tour.id).json")
        if let data = try? JSONEncoder().encode(tour) {
            try? data.write(to: url)
        }
    }

    func loadAll() -> [Tour] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return dateA > dateB
            }
            .compactMap { url -> Tour? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Tour.self, from: data)
            }
    }

    func delete(_ tourId: String) {
        let url = directory.appendingPathComponent("\(tourId).json")
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Location Helper

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
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, error in
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
