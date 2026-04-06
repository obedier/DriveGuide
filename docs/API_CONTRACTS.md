# API Contracts — Private TourAi

Base URL: `https://api.privatetourai.com/v1`

All endpoints require `Authorization: Bearer <firebase_id_token>` unless marked **PUBLIC**.

All responses include `X-Min-App-Version: <semver>` header. The iOS app checks this on launch and shows a force-upgrade prompt if the installed version is below the minimum. This is critical for subscription enforcement and API contract changes.

## Types

```typescript
// === Request/Response Types ===

// Tour Generation
interface GenerateTourRequest {
  location: string;              // city, neighborhood, address, or "start→end"
  duration_minutes: number;      // 30–360
  themes?: TourTheme[];          // optional preferences
  language?: string;             // ISO 639-1, default "en"
  start_address?: string;        // optional specific start
  end_address?: string;          // optional specific end (or "loop" to return to start)
}

type TourTheme = 'history' | 'food' | 'scenic' | 'hidden-gems' | 'architecture' | 'culture' | 'nature' | 'nightlife';

interface GenerateTourResponse {
  tour: Tour;
}

interface Tour {
  id: string;
  title: string;
  description: string;
  location_query: string;
  center_point: GeoPoint;
  duration_minutes: number;
  total_distance_km: number;
  themes: TourTheme[];
  language: string;
  status: TourStatus;
  story_arc_summary: string;
  maps_directions_url: string;
  stops: TourStop[];
  narration_segments: NarrationSegment[];
  created_at: string;           // ISO 8601
}

type TourStatus = 'generating' | 'ready' | 'failed';

interface TourStop {
  id: string;
  sequence_order: number;
  name: string;
  description: string;
  category: StopCategory;
  latitude: number;
  longitude: number;
  recommended_stay_minutes: number;
  is_optional: boolean;
  approach_narration: string;
  at_stop_narration: string;
  departure_narration: string;
  google_place_id?: string;
  place_data?: PlaceData;
}

type StopCategory = 'landmark' | 'restaurant' | 'viewpoint' | 'hidden-gem' | 'photo-op' | 'park' | 'museum' | 'neighborhood';

interface PlaceData {
  name: string;
  rating?: number;
  price_level?: number;        // 0-4
  opening_hours?: string[];
  photos?: string[];           // photo reference URLs
  website?: string;
  phone?: string;
}

interface NarrationSegment {
  id: string;
  segment_type: SegmentType;
  sequence_order: number;
  narration_text: string;
  estimated_duration_seconds: number;
  trigger_point: GeoPoint;
  trigger_radius_meters: number;
  from_stop_id?: string;
  to_stop_id?: string;
  audio_url?: string;          // populated after audio generation
}

type SegmentType = 'intro' | 'between_stops' | 'approach' | 'at_stop' | 'departure' | 'outro';

interface GeoPoint {
  latitude: number;
  longitude: number;
}

// Audio
interface GenerateAudioRequest {
  tour_id: string;
  language?: string;           // override tour language
  voice_preference?: VoicePreference;
}

type VoicePreference = 'male' | 'female' | 'neutral';

interface GenerateAudioResponse {
  tour_id: string;
  segments: AudioSegment[];
  total_duration_seconds: number;
  total_size_bytes: number;
  download_url: string;        // ZIP of all audio files
}

interface AudioSegment {
  segment_id: string;
  audio_url: string;           // signed GCS URL
  duration_seconds: number;
  file_size_bytes: number;
  content_hash: string;
}

// Tour Library
interface SavedTour {
  id: string;
  tour: Tour;
  is_favorite: boolean;
  last_played_at?: string;
  progress_percent: number;
  saved_at: string;
}

// Tour Edit
interface EditTourRequest {
  remove_stop_ids?: string[];
  add_stops?: AddStopRequest[];
  reorder_stops?: { stop_id: string; new_order: number }[];
  regenerate_narration?: boolean;
}

interface AddStopRequest {
  name: string;
  latitude: number;
  longitude: number;
  insert_after_order: number;  // where to insert in sequence
}

// User
interface UserProfile {
  id: string;
  email: string;
  display_name: string;
  avatar_url?: string;
  preferred_language: string;
  preferences: UserPreferences;
  subscription: SubscriptionInfo;
  created_at: string;
}

interface UserPreferences {
  default_themes: TourTheme[];
  default_duration_minutes: number;
  voice_preference: VoicePreference;
  auto_download_audio: boolean;
}

interface SubscriptionInfo {
  tier: SubscriptionTier;
  status: SubscriptionStatus;
  single_tours_remaining: number;
  current_period_end?: string;
}

type SubscriptionTier = 'free' | 'single' | 'weekly' | 'monthly' | 'annual';
type SubscriptionStatus = 'active' | 'expired' | 'cancelled' | 'grace_period';

// Tour Preview (for unauthenticated users)
interface TourPreview {
  title: string;
  description: string;
  stop_count: number;
  duration_minutes: number;
  total_distance_km: number;
  preview_stops: TourStopPreview[];  // first 2-3 stops only
  maps_preview_url: string;          // static map image
}

interface TourStopPreview {
  name: string;
  category: StopCategory;
  teaser: string;                    // short narration teaser
}

// Pagination
interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    total: number;
    page: number;
    limit: number;
    has_more: boolean;
  };
}

// Errors
interface ErrorResponse {
  error: {
    code: string;
    message: string;
    details?: Record<string, unknown>;
  };
}
```

## Endpoints

### Tours

#### `POST /tours/generate` — Generate a new tour
- **Auth**: Required (or returns preview for unauthenticated)
- **Entitlement**: Free users get `TourPreview`, paid users get full `Tour`
- **Request**: `GenerateTourRequest`
- **Response**: `GenerateTourResponse` (200) or `{ preview: TourPreview }` (200, free tier)
- **Errors**:
  - `400` — Invalid location or duration out of range
  - `402` — No tours remaining (single-tour purchasers)
  - `429` — Rate limit exceeded (max 5 generations/hour)
  - `503` — Tour generation temporarily unavailable

#### `POST /tours/preview` — **PUBLIC** Generate a tour preview (no auth)
- **Auth**: None
- **Rate Limiting**: Max 3 previews/hour per IP + global cap of 500 previews/hour across all IPs. Prefer serving cached template tours for popular South Florida areas over fresh Gemini calls.
- **Request**: `GenerateTourRequest`
- **Response**: `{ preview: TourPreview }` (200)
- **Errors**:
  - `400` — Invalid location or duration
  - `429` — Rate limit exceeded (per-IP or global cap)

#### `GET /tours/:id` — Get a specific tour
- **Auth**: Required
- **Response**: `{ tour: Tour }` (200)
- **Errors**: `404` — Tour not found or not owned by user

#### `PATCH /tours/:id` — Edit a tour (add/remove/reorder stops)
- **Auth**: Required
- **Entitlement**: Paid users only
- **Request**: `EditTourRequest`
- **Response**: `{ tour: Tour }` (200)
- **Errors**: `404`, `400` — Invalid edit

#### `DELETE /tours/:id` — Delete a tour
- **Auth**: Required
- **Response**: `204`

#### `POST /tours/:id/regenerate` — Regenerate narration for an edited tour
- **Auth**: Required
- **Entitlement**: Paid users only
- **Response**: `{ tour: Tour }` (200)
- **Errors**: `404`, `402`

### Audio

#### `POST /tours/:id/audio` — Generate audio for a tour
- **Auth**: Required
- **Entitlement**: Paid users only
- **Request**: `GenerateAudioRequest`
- **Response**: `GenerateAudioResponse` (200)
- **Errors**: `404`, `402`, `503` — TTS unavailable

#### `GET /tours/:id/audio/download` — Download audio package for offline
- **Auth**: Required
- **Entitlement**: Paid users only
- **Response**: `302` redirect to signed GCS URL (ZIP file)
- **Errors**: `404` — Audio not generated yet

### Tour Library

#### `GET /library` — List saved tours
- **Auth**: Required
- **Query**: `?page=1&limit=20&sort=saved_at`
- **Response**: `PaginatedResponse<SavedTour>` (200)

#### `POST /library/:tour_id` — Save a tour to library
- **Auth**: Required
- **Response**: `{ saved_tour: SavedTour }` (201)

#### `DELETE /library/:tour_id` — Remove from library
- **Auth**: Required
- **Response**: `204`

#### `PATCH /library/:tour_id` — Update saved tour (favorite, progress)
- **Auth**: Required
- **Request**: `{ is_favorite?: boolean; progress_percent?: number; last_segment_id?: string }`
- **Response**: `{ saved_tour: SavedTour }` (200)

### User

#### `GET /user/profile` — Get current user profile
- **Auth**: Required
- **Response**: `{ profile: UserProfile }` (200)

#### `PATCH /user/profile` — Update profile
- **Auth**: Required
- **Request**: `Partial<Pick<UserProfile, 'display_name' | 'preferred_language' | 'preferences'>>`
- **Response**: `{ profile: UserProfile }` (200)

#### `DELETE /user/account` — Delete account and all data
- **Auth**: Required
- **Response**: `204`

### Subscription

#### `GET /subscription` — Get current subscription status
- **Auth**: Required
- **Response**: `{ subscription: SubscriptionInfo }` (200)

#### `POST /subscription/verify` — Verify App Store receipt (called by iOS app)
- **Auth**: Required
- **Request**: `{ receipt_data: string; product_id: string }`
- **Response**: `{ subscription: SubscriptionInfo }` (200)

#### `POST /webhooks/revenuecat` — RevenueCat webhook (server-to-server)
- **Auth**: RevenueCat webhook signature
- **Request**: RevenueCat webhook payload
- **Response**: `200`

### Health

#### `GET /health` — **PUBLIC** Health check
- **Response**: `{ status: "ok", version: string }` (200)
