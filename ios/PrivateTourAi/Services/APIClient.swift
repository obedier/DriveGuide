import Foundation
import FirebaseAuth

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int, String)
    case unauthorized
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .decodingError:
            // Deliberately generic — the DecodingError's localizedDescription
            // ("The data couldn't be read because it isn't in the correct
            // format") is confusing to end users. Full diagnostic is logged
            // in APIClient.post() before the throw.
            return "We had trouble reading the server's response. Please try again."
        case .serverError(let code, let message): return "Server error (\(code)): \(message)"
        case .unauthorized: return "Please sign in to continue"
        case .noData: return "No data received"
        }
    }
}

// Using a final class (not actor) to avoid isolation issues with @MainActor callers
final class APIClient: Sendable {
    static let shared = APIClient()

    private let baseURL = "https://waipoint.o11r.com/v1"

    // Longer timeout for AI-powered endpoints
    private let shortTimeout: TimeInterval = 20
    private let longTimeout: TimeInterval = 300  // 5 min for tour gen + Kokoro audio

    // MARK: - Location Verification

    func verifyLocation(_ location: String) async throws -> VerifiedLocation {
        struct VerifyRequest: Encodable { let location: String }
        // Auto-retry once on failure (handles cold start timeouts)
        do {
            let response: VerifyLocationResponse = try await post(
                "/tours/verify-location",
                body: VerifyRequest(location: location),
                timeout: 20 // increased from 15s for cold starts
            )
            return response.location
        } catch {
            // Retry once after 1 second
            try? await Task.sleep(for: .seconds(1))
            let response: VerifyLocationResponse = try await post(
                "/tours/verify-location",
                body: VerifyRequest(location: location),
                timeout: 20
            )
            return response.location
        }
    }

    // MARK: - Tour Generation

    func generatePreview(location: String, durationMinutes: Int, themes: [String] = [], transportMode: String = "car", speedMph: Double? = nil, customPrompt: String? = nil, startAddress: String? = nil, endAddress: String? = nil) async throws -> (preview: TourPreview, tourId: String?) {
        let body = GenerateTourRequest(
            location: location,
            durationMinutes: durationMinutes,
            themes: themes.isEmpty ? nil : themes,
            language: nil,
            transportMode: transportMode == "car" ? nil : transportMode,
            speedMph: speedMph,
            customPrompt: customPrompt?.isEmpty == true ? nil : customPrompt,
            startAddress: startAddress,
            endAddress: endAddress
        )
        let response: TourResponse = try await post("/tours/preview", body: body, timeout: longTimeout)
        guard let preview = response.preview else {
            throw APIError.noData
        }
        return (preview, response.tourId)
    }

    // Share
    func getSharedTour(shareId: String) async throws -> Tour {
        let response: [String: Tour] = try await get("/tours/shared/\(shareId)")
        guard let tour = response["tour"] else { throw APIError.noData }
        return tour
    }

    func generateTour(location: String, durationMinutes: Int, themes: [String] = [], transportMode: String = "car", speedMph: Double? = nil, customPrompt: String? = nil, startAddress: String? = nil, endAddress: String? = nil) async throws -> TourResponse {
        let body = GenerateTourRequest(
            location: location,
            durationMinutes: durationMinutes,
            themes: themes.isEmpty ? nil : themes,
            language: nil,
            transportMode: transportMode == "car" ? nil : transportMode,
            speedMph: speedMph,
            customPrompt: customPrompt,
            startAddress: startAddress,
            endAddress: endAddress
        )
        return try await post("/tours/generate", body: body, timeout: longTimeout)
    }

    func getFullTour(tourId: String) async throws -> Tour {
        let body = FullTourRequest(tourId: tourId, location: nil, durationMinutes: nil)
        let response: TourResponse = try await post("/tours/full", body: body, timeout: longTimeout)
        guard let tour = response.tour else { throw APIError.noData }
        return tour
    }

    func generateFullTour(location: String, durationMinutes: Int, themes: [String] = [], transportMode: String = "car", speedMph: Double? = nil, customPrompt: String? = nil, startAddress: String? = nil, endAddress: String? = nil) async throws -> Tour {
        let body = GenerateTourRequest(
            location: location,
            durationMinutes: durationMinutes,
            themes: themes.isEmpty ? nil : themes,
            language: nil,
            transportMode: transportMode == "car" ? nil : transportMode,
            speedMph: speedMph,
            customPrompt: customPrompt,
            startAddress: startAddress,
            endAddress: endAddress
        )
        let response: TourResponse = try await post("/tours/full", body: body, timeout: longTimeout)
        guard let tour = response.tour else { throw APIError.noData }
        return tour
    }

    func getTour(id: String) async throws -> Tour {
        let response: [String: Tour] = try await get("/tours/\(id)")
        guard let tour = response["tour"] else { throw APIError.noData }
        return tour
    }

    // MARK: - Community

    func publishTour(tour: Tour) async throws {
        struct PublishRequest: Encodable { let tour: Tour }
        struct PublishResponse: Decodable { let status: String }
        let _: PublishResponse = try await authPost("/tours/community/publish", body: PublishRequest(tour: tour))
    }

    func unpublishTour(tourId: String) async throws {
        struct StatusResponse: Decodable { let status: String }
        let _: StatusResponse = try await authPost("/tours/\(tourId)/unpublish", body: EmptyBody())
    }

    /// 2.10: single source of truth for public/private — hits the new
    /// `POST /v1/tours/:id/visibility` endpoint. Reuses the existing
    /// publish/unpublish endpoints under the hood would also work, but this
    /// matches the opt-in flag model on the tour itself.
    func setTourVisibility(tourId: String, isPublic: Bool) async throws {
        struct VisibilityRequest: Encodable { let isPublic: Bool }
        struct VisibilityResponse: Decodable { let id: String; let isPublic: Bool }
        let _: VisibilityResponse = try await authPost(
            "/tours/\(tourId)/visibility",
            body: VisibilityRequest(isPublic: isPublic)
        )
    }

    /// 2.10: browse surface for the public tour library.
    /// sort: "top" | "recent" | "trending"
    struct PublicTourItem: Decodable, Identifiable, Sendable {
        let id: String
        /// Share ID used by `getSharedTour(shareId:)`. Falls back to the tour's
        /// `id` if the backend omits it so the UI can still try a deep-link.
        let shareId: String?
        let title: String
        let description: String
        let durationMinutes: Int
        let stopCount: Int
        let transportMode: String
        let metroArea: String?
        let avgRating: Double
        let ratingCount: Int
        let isFeatured: Bool
        let createdAt: String

        /// Use this instead of `id` for any `/tours/shared/:x` lookup.
        var resolvableShareId: String { shareId ?? id }

        private enum CodingKeys: String, CodingKey {
            case id, title, description
            case shareId = "share_id"
            case durationMinutes = "duration_minutes"
            case stopCount = "stop_count"
            case transportMode = "transport_mode"
            case metroArea = "metro_area"
            case avgRating = "avg_rating"
            case ratingCount = "rating_count"
            case isFeatured = "is_featured"
            case createdAt = "created_at"
        }

        /// Custom decoder — SQLite returns BOOL as 0/1 INTEGER and
        /// occasionally drops optional columns, so synthesized Decodable
        /// would bubble up as "Data error: the data couldn't be read
        /// because it isn't in the correct format." (TF #29 bug 5)
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            shareId = try c.decodeIfPresent(String.self, forKey: .shareId)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
            durationMinutes = (try? c.decodeIfPresent(Int.self, forKey: .durationMinutes)) ?? 0
            stopCount = (try? c.decodeIfPresent(Int.self, forKey: .stopCount)) ?? 0
            transportMode = try c.decodeIfPresent(String.self, forKey: .transportMode) ?? "car"
            metroArea = try c.decodeIfPresent(String.self, forKey: .metroArea)
            avgRating = (try? c.decodeIfPresent(Double.self, forKey: .avgRating)) ?? 0
            ratingCount = (try? c.decodeIfPresent(Int.self, forKey: .ratingCount)) ?? 0
            if let b = try? c.decodeIfPresent(Bool.self, forKey: .isFeatured) {
                isFeatured = b
            } else if let i = try? c.decodeIfPresent(Int.self, forKey: .isFeatured) {
                isFeatured = i != 0
            } else {
                isFeatured = false
            }
            createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        }
    }

    struct PublicToursResponse: Decodable { let tours: [PublicTourItem]; let total: Int }

    func getPublicTours(sort: String = "top", metro: String? = nil, limit: Int = 20, offset: Int = 0)
        async throws -> PublicToursResponse {
        var path = "/tours/public?sort=\(sort)&limit=\(limit)&offset=\(offset)"
        if let metro, !metro.isEmpty {
            let encoded = metro.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? metro
            path += "&metro=\(encoded)"
        }
        return try await get(path)
    }

    struct CommunityTourItem: Decodable, Identifiable {
        let id: String
        let title: String
        let description: String
        let location: String
        let duration_minutes: Int
        let transport_mode: String
        let center_lat: Double?
        let center_lng: Double?
        let distance_km: Double?
        let share_id: String?
        let rating: Double?
        let rating_count: Int?
        let created_at: String?
        /// Curated / pre-generated showcase tours get a gold treatment on
        /// the community card. Decoded flexibly because SQLite returns 0/1 ints.
        let is_featured: Bool

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            description = try c.decode(String.self, forKey: .description)
            location = (try? c.decode(String.self, forKey: .location)) ?? ""
            duration_minutes = (try? c.decode(Int.self, forKey: .duration_minutes)) ?? 60
            transport_mode = (try? c.decode(String.self, forKey: .transport_mode)) ?? "car"
            center_lat = try? c.decodeIfPresent(Double.self, forKey: .center_lat)
            center_lng = try? c.decodeIfPresent(Double.self, forKey: .center_lng)
            distance_km = try? c.decodeIfPresent(Double.self, forKey: .distance_km)
            share_id = try? c.decodeIfPresent(String.self, forKey: .share_id)
            rating = try? c.decodeIfPresent(Double.self, forKey: .rating)
            rating_count = try? c.decodeIfPresent(Int.self, forKey: .rating_count)
            created_at = try? c.decodeIfPresent(String.self, forKey: .created_at)
            if let b = try? c.decodeIfPresent(Bool.self, forKey: .is_featured) {
                is_featured = b
            } else if let i = try? c.decodeIfPresent(Int.self, forKey: .is_featured) {
                is_featured = i != 0
            } else {
                is_featured = false
            }
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, description, location
            case duration_minutes, transport_mode
            case center_lat, center_lng, distance_km
            case share_id, rating, rating_count, created_at, is_featured
        }
    }

    struct CommunityResponse: Decodable {
        let tours: [CommunityTourItem]
        let pagination: Pagination
        struct Pagination: Decodable {
            let total: Int
            let page: Int
            let limit: Int
            let has_more: Bool
        }
    }

    func getCommunityTours(lat: Double? = nil, lng: Double? = nil, radiusKm: Double = 100) async throws -> CommunityResponse {
        var path = "/tours/community?"
        if let lat, let lng {
            path += "lat=\(lat)&lng=\(lng)&radius_km=\(radiusKm)&"
        }
        path += "limit=50"
        return try await get(path)
    }

    // MARK: - User Tours (cloud-synced library)

    struct UserToursResponse: Decodable {
        let tours: [Tour]
        let archived: [Tour]
    }

    /// Fetches the current user's saved + archived tours from the cloud.
    func getUserTours() async throws -> UserToursResponse {
        return try await authGet("/user/tours")
    }

    /// Uploads a local tour to the cloud if it doesn't already exist for this user.
    func syncTourToCloud(_ tour: Tour) async throws {
        struct Response: Decodable { let status: String }
        // Encode the tour with snake_case keys matching the server's schema
        let data = try JSONEncoder().encode(tour)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        var request = try await authenticatedRequest(path: "/user/tours/sync", method: "POST", timeout: longTimeout)
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let _: Response = try await execute(request)
    }

    /// Archives a tour server-side.
    func archiveUserTour(tourId: String) async throws {
        struct Response: Decodable { let status: String }
        let _: Response = try await authPost("/user/tours/\(tourId)/archive", body: EmptyBody())
    }

    /// Unarchives a tour server-side.
    func unarchiveUserTour(tourId: String) async throws {
        struct Response: Decodable { let status: String }
        let _: Response = try await authPost("/user/tours/\(tourId)/unarchive", body: EmptyBody())
    }

    /// Deletes a tour server-side.
    func deleteUserTour(tourId: String) async throws {
        let request = try await authenticatedRequest(path: "/tours/\(tourId)", method: "DELETE", timeout: shortTimeout)
        let _ = try await URLSession.shared.data(for: request)
    }

    private struct EmptyBody: Encodable {}

    // MARK: - Account

    func deleteAccount() async throws {
        struct DeleteResponse: Decodable { let status: String }
        let request = try await authenticatedRequest(path: "/account", method: "DELETE", timeout: shortTimeout)
        let _: DeleteResponse = try await execute(request)
    }

    // MARK: - Ratings

    func rateTour(tourId: String, rating: Int, review: String? = nil) async throws {
        struct RateRequest: Encodable { let rating: Int; let review: String? }
        struct RateResponse: Decodable { let status: String }
        let _: RateResponse = try await authPost("/tours/\(tourId)/rate", body: RateRequest(rating: rating, review: review))
    }

    struct RatingItem: Decodable {
        let rating: Int
        let review: String?
        let author: String
        let created_at: String
    }

    func getTourRatings(tourId: String) async throws -> [RatingItem] {
        struct Response: Decodable { let ratings: [RatingItem] }
        let response: Response = try await get("/tours/\(tourId)/ratings")
        return response.ratings
    }

    // MARK: - Bridge Narration (2.16 — "drive-to" intro for far-from-first-stop)

    struct BridgeNarrationResponse: Decodable, Sendable {
        let narrationText: String
        let audioUrl: String
        let contentHash: String
        let durationSeconds: Int
        let distanceKm: Double
        let etaMinutes: Int

        enum CodingKeys: String, CodingKey {
            case narrationText = "narration_text"
            case audioUrl = "audio_url"
            case contentHash = "content_hash"
            case durationSeconds = "duration_seconds"
            case distanceKm = "distance_km"
            case etaMinutes = "eta_minutes"
        }
    }

    /// Fetch an on-the-fly drive-to narration when the user is far from the
    /// first stop. Gemini-authored + Google-TTS-synthesized on the server.
    /// `kind` controls opener vs follow-up prompting; `previousOpeners` lets
    /// the server steer Gemini away from repeating phrasing across multiple
    /// bridges during the same trip.
    func getBridgeNarration(
        tourId: String,
        userLat: Double,
        userLng: Double,
        etaMinutes: Int?,
        kind: String = "opener",
        previousOpeners: [String] = []
    ) async throws -> BridgeNarrationResponse {
        struct Body: Encodable {
            let user_lat: Double
            let user_lng: Double
            let eta_minutes: Int?
            let kind: String
            let previous_openers: [String]
        }
        return try await post(
            "/tours/\(tourId)/bridge",
            body: Body(user_lat: userLat, user_lng: userLng, eta_minutes: etaMinutes,
                       kind: kind, previous_openers: previousOpeners),
            timeout: 60  // includes Gemini + TTS round-trip
        )
    }

    // MARK: - Per-Segment Audio (for progressive buffering)

    func generateSegmentAudio(text: String, contentHash: String, voiceEngine: String = "google", voicePreference: String = "premium") async throws -> String {
        if voiceEngine == "kokoro" {
            // Call Kokoro service directly for single segment
            struct KokoroRequest: Encodable { let text: String; let content_hash: String; let voice: String; let speed: Double }
            struct KokoroResponse: Decodable { let audio_url: String }
            let kokoroUrl = "https://kokoro-tts-801121217326.us-east1.run.app"
            guard let url = URL(string: "\(kokoroUrl)/synthesize") else { throw APIError.invalidURL }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = longTimeout
            request.httpBody = try JSONEncoder().encode(KokoroRequest(text: text, content_hash: contentHash, voice: "af_heart", speed: 0.95))
            let response: KokoroResponse = try await execute(request)
            return response.audio_url
        } else {
            // Use Google TTS via backend
            struct TTSRequest: Encodable { let segments: [Seg]; let voice_preference: String; let voice_engine: String
                struct Seg: Encodable { let id: String; let narration_text: String; let content_hash: String; let language: String }
            }
            let req = TTSRequest(segments: [.init(id: "s", narration_text: text, content_hash: contentHash, language: "en")], voice_preference: voicePreference, voice_engine: "google")
            let response: AudioResponse = try await post("/audio/generate", body: req, timeout: longTimeout)
            return response.segments.first?.audioUrl ?? ""
        }
    }

    // MARK: - Audio

    func generateAudio(tourId: String, voicePreference: String = "premium", voiceEngine: String = "google") async throws -> AudioResponse {
        struct AudioRequest: Encodable { let voice_preference: String; let voice_engine: String }
        return try await post("/tours/\(tourId)/audio", body: AudioRequest(voice_preference: voicePreference, voice_engine: voiceEngine), timeout: longTimeout)
    }

    func generateAudioInline(segments: [NarrationSegment], voicePreference: String = "premium", voiceEngine: String = "google") async throws -> AudioResponse {
        struct InlineRequest: Encodable {
            let segments: [SegmentInput]
            let voice_preference: String
            let voice_engine: String
        }
        struct SegmentInput: Encodable {
            let id: String
            let narration_text: String
            let content_hash: String
            let language: String
        }

        let input = InlineRequest(segments: segments.map { seg in
            SegmentInput(id: seg.id, narration_text: seg.narrationText, content_hash: seg.contentHash, language: seg.language)
        }, voice_preference: voicePreference, voice_engine: voiceEngine)
        return try await post("/audio/generate", body: input, timeout: longTimeout)
    }

    // MARK: - HTTP Methods

    private func get<T: Decodable>(_ path: String, timeout: TimeInterval? = nil) async throws -> T {
        let request = try buildRequest(path: path, method: "GET", timeout: timeout ?? shortTimeout)
        return try await execute(request)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B, timeout: TimeInterval? = nil) async throws -> T {
        var request = try buildRequest(path: path, method: "POST", timeout: timeout ?? shortTimeout)
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await execute(request)
    }

    private func buildRequest(path: String, method: String, timeout: TimeInterval) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        return request
    }

    private func authenticatedRequest(path: String, method: String, timeout: TimeInterval) async throws -> URLRequest {
        var request = try buildRequest(path: path, method: method, timeout: timeout)
        if let user = Auth.auth().currentUser {
            let token = try await user.getIDToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func authGet<T: Decodable>(_ path: String, timeout: TimeInterval? = nil) async throws -> T {
        let request = try await authenticatedRequest(path: path, method: "GET", timeout: timeout ?? shortTimeout)
        return try await execute(request)
    }

    private func authPost<T: Decodable, B: Encodable>(_ path: String, body: B, timeout: TimeInterval? = nil) async throws -> T {
        var request = try await authenticatedRequest(path: path, method: "POST", timeout: timeout ?? shortTimeout)
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await execute(request)
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .timedOut {
                throw APIError.networkError(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Request timed out. Please try again."]))
            }
            throw APIError.networkError(urlError)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, message)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            // Log the raw response for debugging
            let raw = String(data: data, encoding: .utf8) ?? "(binary)"
            print("[APIClient] Decode error for \(request.url?.path ?? "?"): \(error)")
            print("[APIClient] Raw response: \(raw.prefix(500))")
            throw APIError.decodingError(error)
        }
    }
}

private struct EmptyBody: Encodable {}
