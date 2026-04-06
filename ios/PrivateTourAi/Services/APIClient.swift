import Foundation

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
        case .decodingError(let error): return "Data error: \(error.localizedDescription)"
        case .serverError(let code, let message): return "Server error (\(code)): \(message)"
        case .unauthorized: return "Please sign in to continue"
        case .noData: return "No data received"
        }
    }
}

// Using a final class (not actor) to avoid isolation issues with @MainActor callers
final class APIClient: Sendable {
    static let shared = APIClient()

    private let baseURL = "https://private-tourai-api-i32snp7xla-ue.a.run.app/v1"

    // Longer timeout for AI-powered endpoints
    private let shortTimeout: TimeInterval = 15
    private let longTimeout: TimeInterval = 120

    // MARK: - Location Verification

    func verifyLocation(_ location: String) async throws -> VerifiedLocation {
        struct VerifyRequest: Encodable { let location: String }
        let response: VerifyLocationResponse = try await post(
            "/tours/verify-location",
            body: VerifyRequest(location: location),
            timeout: shortTimeout
        )
        return response.location
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

    // MARK: - Audio

    func generateAudio(tourId: String) async throws -> AudioResponse {
        return try await post("/tours/\(tourId)/audio", body: EmptyBody(), timeout: longTimeout)
    }

    func generateAudioInline(segments: [NarrationSegment]) async throws -> AudioResponse {
        struct InlineRequest: Encodable {
            let segments: [SegmentInput]
        }
        struct SegmentInput: Encodable {
            let id: String
            let narration_text: String
            let content_hash: String
            let language: String
        }

        let input = InlineRequest(segments: segments.map { seg in
            SegmentInput(id: seg.id, narration_text: seg.narrationText, content_hash: seg.contentHash, language: seg.language)
        })
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
