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
    @Published var archivedTours: [Tour] = []

    // Community tours
    @Published var communityTours: [APIClient.CommunityTourItem] = []
    @Published var isLoadingCommunity = false

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
    @Published var useAsStartLocation = false
    @Published var useAsEndLocation = false
    @Published var showAdvancedSettings = false

    let durations = [30, 60, 90, 120, 180, 240, 360]
    let availableThemes = ["history", "food", "scenic", "hidden-gems", "architecture", "culture", "nature", "nightlife"]
    let transportModes = ["car", "walk", "bike", "boat", "plane"]

    private let locationManager = LocationHelper()
    private let storage = TourStorage.shared

    init() {
        loadSampleToursIfNeeded()
        savedTours = storage.loadAll()
        archivedTours = storage.loadArchived()
        // Sync with cloud on launch (async, falls back to local if offline)
        Task { await syncWithCloud() }
    }

    // MARK: - Cloud Sync

    /// Two-way sync: pull cloud tours down + push local-only tours up.
    /// Runs silently — on failure, local cache is still shown.
    func syncWithCloud() async {
        do {
            // 1. Fetch from cloud
            let response = try await APIClient.shared.getUserTours()
            let cloudIds = Set((response.tours + response.archived).map { $0.id })

            // 2. Save cloud tours locally
            for tour in response.tours + response.archived {
                storage.save(tour)
            }
            let archivedIds = Set(response.archived.map { $0.id })
            storage.syncArchivedIds(archivedIds)

            // 3. Upload any local tours that aren't on cloud yet
            let localIds = Set(storage.loadAll().map { $0.id } + storage.loadArchived().map { $0.id })
            let toUpload = localIds.subtracting(cloudIds)
            var uploadedCount = 0
            for tourId in toUpload {
                let allLocal = storage.loadAll() + storage.loadArchived()
                if let localTour = allLocal.first(where: { $0.id == tourId }) {
                    do {
                        try await APIClient.shared.syncTourToCloud(localTour)
                        uploadedCount += 1
                    } catch {
                        // Non-fatal; tour stays local
                    }
                }
            }

            // 4. Reload local state
            savedTours = storage.loadAll()
            archivedTours = storage.loadArchived()
            print("[TourVM] Cloud sync: \(response.tours.count) down, \(uploadedCount) up")
        } catch {
            print("[TourVM] Cloud sync failed (offline?): \(error.localizedDescription)")
        }
    }

    /// The most recent saved tour within the last 48 hours, used to power the
    /// "Continue your last tour" chip on Home. Returns nil when the user is
    /// already in an active flow (preview or tour loaded) so the chip doesn't
    /// compete with the active card, or when no tour is recent enough.
    var recentTour: Tour? {
        guard currentTour == nil, currentPreview == nil else { return nil }
        guard let latest = savedTours.first else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: latest.createdAt)
            ?? ISO8601DateFormatter().date(from: latest.createdAt)

        guard let createdAt = date else {
            // Unparseable timestamp — still surface it so users aren't stranded
            return latest
        }
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        return createdAt > cutoff ? latest : nil
    }

    private func loadSampleToursIfNeeded() {
        let marker = storage.directory.appendingPathComponent(".samples-loaded")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }

        if let url = Bundle.main.url(forResource: "sample-boat-tour", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let tour = try? JSONDecoder().decode(Tour.self, from: data) {
            storage.save(tour)
        }
        FileManager.default.createFile(atPath: marker.path, contents: nil)
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
            // When toggled on, get current location address for start/end
            var startAddr: String? = nil
            var endAddr: String? = nil
            if useAsStartLocation || useAsEndLocation {
                let currentAddress: String? = await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
                    locationManager.requestLocation { result in
                        switch result {
                        case .success(let addr): cont.resume(returning: addr)
                        case .failure: cont.resume(returning: nil)
                        }
                    }
                }
                if useAsStartLocation { startAddr = currentAddress ?? "current location" }
                if useAsEndLocation { endAddr = currentAddress ?? "current location" }
            }
            let result = try await APIClient.shared.generatePreview(
                location: location,
                durationMinutes: selectedDuration,
                themes: Array(selectedThemes),
                transportMode: transportMode,
                speedMph: speedMph,
                customPrompt: customPrompt.isEmpty ? nil : customPrompt,
                startAddress: startAddr,
                endAddress: endAddr
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

    // MARK: - Shared Tour (deep link)

    /// Set to a non-nil tour when an incoming shared link should land users
    /// directly in Passenger Mode (bigger type, manual controls, no map).
    /// Observed by ContentView to drive the presentation.
    @Published var pendingPassengerTour: Tour?

    func openSharedTour(shareId: String, passengerMode: Bool = false) {
        Task {
            isGenerating = true
            generationProgress = "Loading shared tour..."
            do {
                let tour = try await APIClient.shared.getSharedTour(shareId: shareId)
                storage.save(tour)
                savedTours = storage.loadAll()
                currentTour = tour
                if passengerMode {
                    pendingPassengerTour = tour
                    showTourDetail = false
                } else {
                    showTourDetail = true
                }
                generationProgress = ""
            } catch {
                self.error = "Could not load shared tour"
            }
            isGenerating = false
        }
    }

    func deleteSavedTour(_ tour: Tour) {
        storage.delete(tour.id)
        savedTours = storage.loadAll()
        if currentTour?.id == tour.id {
            currentTour = nil
            showTourDetail = false
        }
        Task { try? await APIClient.shared.deleteUserTour(tourId: tour.id) }
    }

    func archiveTour(_ tour: Tour) {
        storage.archive(tour.id)
        savedTours = storage.loadAll()
        archivedTours = storage.loadArchived()
        Task { try? await APIClient.shared.archiveUserTour(tourId: tour.id) }
    }

    func unarchiveTour(_ tour: Tour) {
        storage.unarchive(tour.id)
        savedTours = storage.loadAll()
        archivedTours = storage.loadArchived()
        Task { try? await APIClient.shared.unarchiveUserTour(tourId: tour.id) }
    }

    func deleteArchivedTour(_ tour: Tour) {
        storage.delete(tour.id)
        archivedTours = storage.loadArchived()
        Task { try? await APIClient.shared.deleteUserTour(tourId: tour.id) }
    }

    func deleteAllArchived() {
        let toursToDelete = archivedTours
        for tour in toursToDelete {
            storage.delete(tour.id)
        }
        archivedTours = []
        Task {
            for tour in toursToDelete {
                try? await APIClient.shared.deleteUserTour(tourId: tour.id)
            }
        }
    }

    // MARK: - Ratings

    func rateTour(_ tour: Tour, rating: Int) {
        storage.setRating(tourId: tour.id, rating: rating)
        savedTours = storage.loadAll()
        // TODO: Upload rating to backend for community
    }

    func getRating(for tourId: String) -> Int? {
        storage.getRating(tourId: tourId)
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
        return URL(string: "https://waipoint.o11r.com/tour/\(shareId)")
    }

    func shareTourById(_ tour: Tour) -> URL? {
        guard let shareId = tour.shareId else { return nil }
        return URL(string: "https://waipoint.o11r.com/tour/\(shareId)")
    }

    @Published var communityMessage: String?

    func shareToCommunity(_ tour: Tour) {
        Task {
            do {
                try await APIClient.shared.publishTour(tour: tour)
                communityMessage = "Tour published to community!"
                await loadCommunityTours()
            } catch {
                communityMessage = "Failed to publish: \(error.localizedDescription)"
            }
        }
    }

    func loadCommunityTours() async {
        isLoadingCommunity = true
        defer { isLoadingCommunity = false }
        do {
            let response = try await APIClient.shared.getCommunityTours()
            communityTours = response.tours
        } catch {
            print("[Community] Failed to load: \(error)")
        }
    }

    // 2.10: Public library (sorted browse surface backed by the new
    // `/v1/tours/public` endpoint). Kept separate from the legacy
    // `communityTours` array so the existing UI keeps working while the
    // new sorted list rolls in.
    @Published var publicTours: [APIClient.PublicTourItem] = []
    @Published var publicSort: String = "top"  // "top" | "recent" | "trending"
    @Published var isLoadingPublic = false

    func loadPublicTours(sort: String? = nil, metro: String? = nil) async {
        if let sort { publicSort = sort }
        isLoadingPublic = true
        defer { isLoadingPublic = false }
        do {
            let response = try await APIClient.shared.getPublicTours(sort: publicSort, metro: metro)
            publicTours = response.tours
        } catch {
            print("[PublicLibrary] Failed to load: \(error)")
        }
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

    let directory: URL = {
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

    private var archivedIDs: Set<String> {
        get {
            let url = directory.appendingPathComponent(".archived.json")
            guard let data = try? Data(contentsOf: url),
                  let ids = try? JSONDecoder().decode(Set<String>.self, from: data) else { return [] }
            return ids
        }
        set {
            let url = directory.appendingPathComponent(".archived.json")
            try? JSONEncoder().encode(newValue).write(to: url)
        }
    }

    private var ratings: [String: Int] {
        get {
            let url = directory.appendingPathComponent(".ratings.json")
            guard let data = try? Data(contentsOf: url),
                  let dict = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
            return dict
        }
        set {
            let url = directory.appendingPathComponent(".ratings.json")
            try? JSONEncoder().encode(newValue).write(to: url)
        }
    }

    private func allTours() -> [Tour] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else { return [] }
        return files
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
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

    func loadAll() -> [Tour] {
        let archived = archivedIDs
        return allTours().filter { !archived.contains($0.id) }
    }

    func loadArchived() -> [Tour] {
        let archived = archivedIDs
        return allTours().filter { archived.contains($0.id) }
    }

    func archive(_ tourId: String) {
        var ids = archivedIDs
        ids.insert(tourId)
        archivedIDs = ids
    }

    func unarchive(_ tourId: String) {
        var ids = archivedIDs
        ids.remove(tourId)
        archivedIDs = ids
    }

    /// Replace the archived-IDs set from cloud (authoritative).
    func syncArchivedIds(_ ids: Set<String>) {
        archivedIDs = ids
    }

    func delete(_ tourId: String) {
        let url = directory.appendingPathComponent("\(tourId).json")
        try? FileManager.default.removeItem(at: url)
        var ids = archivedIDs; ids.remove(tourId); archivedIDs = ids
    }

    func setRating(tourId: String, rating: Int) {
        var r = ratings; r[tourId] = rating; ratings = r
    }

    func getRating(tourId: String) -> Int? {
        ratings[tourId]
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
