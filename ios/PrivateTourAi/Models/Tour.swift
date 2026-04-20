import Foundation

struct Tour: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let locationQuery: String
    let centerLat: Double?
    let centerLng: Double?
    let durationMinutes: Int
    let themes: [String]
    let language: String
    let status: String
    let mapsDirectionsUrl: String?
    let totalDistanceKm: Double?
    let totalDurationMinutes: Int?
    let storyArcSummary: String?
    let transportMode: String?
    let speedMph: Double?
    let customPrompt: String?
    let shareId: String?
    let isPublic: Bool
    /// Curated / pre-generated tours (e.g., "Miami's Golden Hour") are flagged
    /// is_featured=1 on the backend. iOS uses this to paint a gold border +
    /// star on community cards so users can tell at a glance they're seeing a
    /// gold-standard showcase tour vs a user-published one.
    let isFeatured: Bool
    let stops: [TourStop]
    let narrationSegments: [NarrationSegment]
    let createdAt: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        locationQuery = try container.decodeIfPresent(String.self, forKey: .locationQuery) ?? ""
        centerLat = try container.decodeIfPresent(Double.self, forKey: .centerLat)
        centerLng = try container.decodeIfPresent(Double.self, forKey: .centerLng)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 60
        themes = try container.decodeIfPresent([String].self, forKey: .themes) ?? []
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "ready"
        mapsDirectionsUrl = try container.decodeIfPresent(String.self, forKey: .mapsDirectionsUrl)
        totalDistanceKm = try container.decodeIfPresent(Double.self, forKey: .totalDistanceKm)
        totalDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .totalDurationMinutes)
        storyArcSummary = try container.decodeIfPresent(String.self, forKey: .storyArcSummary)
        transportMode = try container.decodeIfPresent(String.self, forKey: .transportMode)
        speedMph = try container.decodeIfPresent(Double.self, forKey: .speedMph)
        customPrompt = try container.decodeIfPresent(String.self, forKey: .customPrompt)
        shareId = try container.decodeIfPresent(String.self, forKey: .shareId)
        // SQLite-backed APIs return BOOLs as 0/1 ints; handle both without crashing.
        isPublic = Self.flexibleBool(container, key: .isPublic) ?? false
        isFeatured = Self.flexibleBool(container, key: .isFeatured) ?? false
        stops = try container.decodeIfPresent([TourStop].self, forKey: .stops) ?? []
        narrationSegments = try container.decodeIfPresent([NarrationSegment].self, forKey: .narrationSegments) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, themes, language, status, stops
        case locationQuery = "location_query"
        case centerLat = "center_lat"
        case centerLng = "center_lng"
        case durationMinutes = "duration_minutes"
        case mapsDirectionsUrl = "maps_directions_url"
        case totalDistanceKm = "total_distance_km"
        case totalDurationMinutes = "total_duration_minutes"
        case storyArcSummary = "story_arc_summary"
        case transportMode = "transport_mode"
        case speedMph = "speed_mph"
        case customPrompt = "custom_prompt"
        case shareId = "share_id"
        case isPublic = "is_public"
        case isFeatured = "is_featured"
        case narrationSegments = "narration_segments"
        case createdAt = "created_at"
    }

    /// SQLite-backed responses sometimes return BOOLs as 0/1 integers. Plain
    /// `decodeIfPresent(Bool.self, ...)` throws a typeMismatch on those, which
    /// aborts the whole Tour decode. This helper accepts either encoding and
    /// normalises to Swift `Bool`.
    static func flexibleBool<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, key: Key) -> Bool? {
        if let b = try? container.decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? container.decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        return nil
    }
}

struct TourStop: Codable, Identifiable {
    let id: String
    let sequenceOrder: Int
    let name: String
    let description: String
    let category: String
    let latitude: Double
    let longitude: Double
    let recommendedStayMinutes: Int
    let isOptional: Bool
    let approachNarration: String
    let atStopNarration: String
    let departureNarration: String
    let googlePlaceId: String?
    let photoUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, category, latitude, longitude
        case sequenceOrder = "sequence_order"
        case recommendedStayMinutes = "recommended_stay_minutes"
        case isOptional = "is_optional"
        case approachNarration = "approach_narration"
        case atStopNarration = "at_stop_narration"
        case departureNarration = "departure_narration"
        case googlePlaceId = "google_place_id"
        case photoUrl = "photo_url"
    }

    init(
        id: String, sequenceOrder: Int, name: String, description: String,
        category: String, latitude: Double, longitude: Double,
        recommendedStayMinutes: Int, isOptional: Bool,
        approachNarration: String, atStopNarration: String,
        departureNarration: String, googlePlaceId: String?, photoUrl: String?
    ) {
        self.id = id
        self.sequenceOrder = sequenceOrder
        self.name = name
        self.description = description
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.recommendedStayMinutes = recommendedStayMinutes
        self.isOptional = isOptional
        self.approachNarration = approachNarration
        self.atStopNarration = atStopNarration
        self.departureNarration = departureNarration
        self.googlePlaceId = googlePlaceId
        self.photoUrl = photoUrl
    }

    /// Custom decoder — tolerates the usual SQLite/JSON shape mismatches so
    /// a single off-by-one field (is_optional stored as 0/1 int, a missing
    /// narration string, etc.) doesn't abort the whole tour decode and
    /// surface as "Data error: the data couldn't be read because it isn't
    /// in the correct format." (TF #29 bug 5)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sequenceOrder = (try? c.decodeIfPresent(Int.self, forKey: .sequenceOrder)) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "landmark"
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
        recommendedStayMinutes = (try? c.decodeIfPresent(Int.self, forKey: .recommendedStayMinutes)) ?? 0
        // SQLite stores BOOL as INTEGER — accept both.
        isOptional = Tour.flexibleBool(c, key: .isOptional) ?? false
        approachNarration = try c.decodeIfPresent(String.self, forKey: .approachNarration) ?? ""
        atStopNarration = try c.decodeIfPresent(String.self, forKey: .atStopNarration) ?? ""
        departureNarration = try c.decodeIfPresent(String.self, forKey: .departureNarration) ?? ""
        googlePlaceId = try c.decodeIfPresent(String.self, forKey: .googlePlaceId)
        photoUrl = try c.decodeIfPresent(String.self, forKey: .photoUrl)
    }
}

struct NarrationSegment: Codable, Identifiable {
    let id: String
    let segmentType: String
    let sequenceOrder: Int
    let narrationText: String
    let contentHash: String
    let estimatedDurationSeconds: Int
    let triggerLat: Double?
    let triggerLng: Double?
    let triggerRadiusMeters: Double
    let language: String
    let fromStopId: String?
    let toStopId: String?
    var audioUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, language
        case segmentType = "segment_type"
        case sequenceOrder = "sequence_order"
        case narrationText = "narration_text"
        case contentHash = "content_hash"
        case estimatedDurationSeconds = "estimated_duration_seconds"
        case triggerLat = "trigger_lat"
        case triggerLng = "trigger_lng"
        case fromStopId = "from_stop_id"
        case toStopId = "to_stop_id"
        case triggerRadiusMeters = "trigger_radius_meters"
        case audioUrl = "audio_url"
    }
}

struct TourPreview: Codable {
    let title: String
    let description: String
    let stopCount: Int
    let durationMinutes: Int
    let totalDistanceKm: Double?
    let previewStops: [TourStopPreview]

    enum CodingKeys: String, CodingKey {
        case title, description
        case stopCount = "stop_count"
        case durationMinutes = "duration_minutes"
        case totalDistanceKm = "total_distance_km"
        case previewStops = "preview_stops"
    }
}

struct TourStopPreview: Codable, Identifiable {
    var id: String { name }
    let name: String
    let category: String
    let teaser: String
}

struct GenerateTourRequest: Codable {
    let location: String
    let durationMinutes: Int
    let themes: [String]?
    let language: String?
    let transportMode: String?
    let speedMph: Double?
    let customPrompt: String?
    let startAddress: String?
    let endAddress: String?

    enum CodingKeys: String, CodingKey {
        case location, themes, language
        case durationMinutes = "duration_minutes"
        case transportMode = "transport_mode"
        case speedMph = "speed_mph"
        case customPrompt = "custom_prompt"
        case startAddress = "start_address"
        case endAddress = "end_address"
    }
}

// Location verification
struct VerifyLocationResponse: Codable {
    let verified: Bool
    let location: VerifiedLocation
    let nearbyHighlights: [NearbyHighlight]?

    enum CodingKeys: String, CodingKey {
        case verified, location
        case nearbyHighlights = "nearby_highlights"
    }
}

struct VerifiedLocation: Codable {
    let latitude: Double
    let longitude: Double
    let formattedAddress: String

    enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case formattedAddress = "formatted_address"
    }
}

struct NearbyHighlight: Codable, Identifiable {
    var id: String { name }
    let name: String
    let latitude: Double
    let longitude: Double
}

// API Response wrappers
struct TourResponse: Codable {
    let tour: Tour?
    let preview: TourPreview?
    let tourId: String?

    enum CodingKeys: String, CodingKey {
        case tour, preview
        case tourId = "tour_id"
    }
}

struct FullTourRequest: Codable {
    let tourId: String?
    let location: String?
    let durationMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case location
        case tourId = "tour_id"
        case durationMinutes = "duration_minutes"
    }
}

struct AudioResponse: Codable {
    let tourId: String?
    let segments: [AudioSegment]
    let totalDurationSeconds: Int
    let totalSizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case segments
        case tourId = "tour_id"
        case totalDurationSeconds = "total_duration_seconds"
        case totalSizeBytes = "total_size_bytes"
    }
}

struct AudioSegment: Codable, Identifiable {
    var id: String { segmentId }
    let segmentId: String
    let audioUrl: String
    let durationSeconds: Int
    let fileSizeBytes: Int
    let contentHash: String

    enum CodingKeys: String, CodingKey {
        case segmentId = "segment_id"
        case audioUrl = "audio_url"
        case durationSeconds = "duration_seconds"
        case fileSizeBytes = "file_size_bytes"
        case contentHash = "content_hash"
    }
}
