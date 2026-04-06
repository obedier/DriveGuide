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

actor APIClient {
    static let shared = APIClient()

    #if DEBUG
    private let baseURL = "http://localhost:8080/v1"
    #else
    private let baseURL = "https://private-tourai-api-801121217326.us-east1.run.app/v1"
    #endif

    private var authToken: String?

    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    // MARK: - Tour Generation

    func generatePreview(location: String, durationMinutes: Int, themes: [String] = []) async throws -> TourPreview {
        let body = GenerateTourRequest(
            location: location,
            durationMinutes: durationMinutes,
            themes: themes.isEmpty ? nil : themes,
            language: nil
        )
        let response: TourResponse = try await post("/tours/preview", body: body, authenticated: false)
        guard let preview = response.preview else {
            throw APIError.noData
        }
        return preview
    }

    func generateTour(location: String, durationMinutes: Int, themes: [String] = []) async throws -> TourResponse {
        let body = GenerateTourRequest(
            location: location,
            durationMinutes: durationMinutes,
            themes: themes.isEmpty ? nil : themes,
            language: nil
        )
        return try await post("/tours/generate", body: body)
    }

    func getTour(id: String) async throws -> Tour {
        let response: [String: Tour] = try await get("/tours/\(id)")
        guard let tour = response["tour"] else { throw APIError.noData }
        return tour
    }

    // MARK: - Audio

    func generateAudio(tourId: String) async throws -> AudioResponse {
        return try await post("/tours/\(tourId)/audio", body: EmptyBody())
    }

    // MARK: - HTTP Methods

    private func get<T: Decodable>(_ path: String, authenticated: Bool = true) async throws -> T {
        let request = try buildRequest(path: path, method: "GET", authenticated: authenticated)
        return try await execute(request)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B, authenticated: Bool = true) async throws -> T {
        var request = try buildRequest(path: path, method: "POST", authenticated: authenticated)
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await execute(request)
    }

    private func buildRequest(path: String, method: String, authenticated: Bool) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = path.contains("generate") || path.contains("audio") ? 90 : 30

        if authenticated, let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
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
            throw APIError.decodingError(error)
        }
    }
}

private struct EmptyBody: Encodable {}
