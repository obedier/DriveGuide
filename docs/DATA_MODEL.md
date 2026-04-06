# Data Model — Private TourAi

## Entity Relationship Diagram

```mermaid
erDiagram
    USERS ||--o{ TOURS : creates
    USERS ||--o{ SAVED_TOURS : saves
    USERS ||--o{ PURCHASES : makes
    USERS ||--|| SUBSCRIPTIONS : has
    TOURS ||--|{ TOUR_STOPS : contains
    TOURS ||--|{ NARRATION_SEGMENTS : has
    TOUR_STOPS ||--o{ AUDIO_FILES : has
    NARRATION_SEGMENTS ||--o{ AUDIO_FILES : references
    TOURS ||--o{ TOUR_DOWNLOADS : has

    USERS {
        uuid id PK
        string firebase_uid UK
        string email
        string display_name
        string avatar_url
        string preferred_language "default: en"
        text preferences "tour prefs"
        timestamp created_at
        timestamp updated_at
    }

    TOURS {
        uuid id PK
        uuid user_id FK
        string title
        string description
        string location_query "original user input"
        float center_lat
        float center_lng
        string region_code "e.g., south-florida"
        integer duration_minutes
        text themes "JSON array - history, food, scenic, hidden-gems"
        string language "en, es, etc."
        string status "generating, ready, failed"
        string error_code "nullable - failure reason code"
        string error_message "nullable - human-readable failure detail"
        text route_data "JSON - Google Maps route response"
        string maps_directions_url "Google Maps multi-stop URL"
        float total_distance_km
        integer total_duration_minutes
        string story_arc_summary
        string cache_key "location+duration+themes hash"
        boolean is_template "reusable cached tour"
        timestamp created_at
        timestamp updated_at
    }

    TOUR_STOPS {
        uuid id PK
        uuid tour_id FK
        integer sequence_order
        string name
        string description
        string category "landmark, restaurant, viewpoint, hidden-gem, photo-op"
        float latitude
        float longitude
        integer recommended_stay_minutes
        boolean is_optional "pause/explore stops"
        string approach_narration "text for approaching this stop"
        string at_stop_narration "text while at this stop"
        string departure_narration "text when leaving"
        text place_data "Google Places enrichment"
        string google_place_id
        timestamp created_at
    }

    NARRATION_SEGMENTS {
        uuid id PK
        uuid tour_id FK
        uuid from_stop_id FK "nullable - null for tour intro"
        uuid to_stop_id FK "nullable - null for tour outro"
        string segment_type "intro, between_stops, approach, at_stop, departure, outro"
        integer sequence_order
        string narration_text
        string content_hash "SHA-256 of text for cache lookup"
        integer estimated_duration_seconds
        float trigger_lat
        float trigger_lng
        float trigger_radius_meters "geofence radius"
        string language
        timestamp created_at
    }

    AUDIO_FILES {
        uuid id PK
        string content_hash UK "SHA-256 of text + NUL + lang + NUL + voice"
        string language
        string voice_name "Google TTS voice"
        string gcs_path "bucket path"
        integer duration_seconds
        integer file_size_bytes
        string format "mp3"
        integer usage_count "how many tours reference this"
        timestamp created_at
        timestamp last_accessed_at
    }

    SAVED_TOURS {
        uuid id PK
        uuid user_id FK
        uuid tour_id FK
        boolean is_favorite
        timestamp last_played_at
        integer progress_percent
        uuid last_segment_id FK "resume point"
        timestamp saved_at
    }

    TOUR_DOWNLOADS {
        uuid id PK
        uuid user_id FK
        uuid tour_id FK
        string status "pending, downloading, complete, expired"
        integer total_size_bytes
        integer downloaded_bytes
        timestamp downloaded_at
        timestamp expires_at
    }

    SUBSCRIPTIONS {
        uuid id PK
        uuid user_id FK
        string revenuecat_id "RevenueCat customer ID"
        string tier "free, single, weekly, monthly, annual"
        string status "active, expired, cancelled, grace_period"
        integer single_tours_remaining "for single-tour purchases"
        timestamp current_period_start
        timestamp current_period_end
        timestamp created_at
        timestamp updated_at
    }

    PURCHASES {
        uuid id PK
        uuid user_id FK
        string revenuecat_transaction_id
        string product_id "app store product"
        string purchase_type "single_tour, weekly, monthly, annual"
        integer amount_cents "stored as cents, e.g. 499 = $4.99"
        string currency
        timestamp purchased_at
    }
}
```

## Indexes

```sql
-- Geo lookups (Haversine distance computed at query time; index on lat/lng for range scans)
CREATE INDEX idx_tours_center ON tours(center_lat, center_lng);
CREATE INDEX idx_tour_stops_geo ON tour_stops(latitude, longitude);
CREATE INDEX idx_narration_segments_trigger ON narration_segments(trigger_lat, trigger_lng);

-- Cache lookups
CREATE UNIQUE INDEX idx_tours_cache_key ON tours(cache_key) WHERE is_template = 1;
CREATE UNIQUE INDEX idx_audio_files_hash_lang ON audio_files(content_hash, language);

-- User queries
CREATE INDEX idx_tours_user_id ON tours(user_id);
CREATE INDEX idx_saved_tours_user ON saved_tours(user_id, saved_at DESC);
CREATE INDEX idx_subscriptions_user ON subscriptions(user_id);

-- Tour structure
CREATE INDEX idx_tour_stops_tour_order ON tour_stops(tour_id, sequence_order);
CREATE INDEX idx_narration_segments_tour_order ON narration_segments(tour_id, sequence_order);
```

## Modeling Notes

1. **Lat/Lng with Haversine**: All coordinates stored as plain float columns. Spatial queries use Haversine distance formula at query time — sufficient for South Florida v1 scope. Upgrade path to PostGIS when needed.

2. **Content-hashed audio cache**: `audio_files.content_hash` = SHA-256 of `narration_text + \x00 + language + \x00 + voice_name` (NUL-delimited to prevent collision). Same narration → same audio file. Massive TTS cost savings. Single `audio_files` table serves both cache lookup (hot path via in-memory LRU) and metadata storage.

3. **Tour templates**: Tours with `is_template=true` are reusable base tours. User-specific tours may reference a template and store only the delta (reordered stops, removed stops).

4. **Narration segments**: Decoupled from stops to support between-stop narration ("As you drive down Collins Avenue, notice the Art Deco buildings on your left..."). Each segment has a GPS trigger point and radius.

5. **Subscription via RevenueCat**: The `subscriptions` table mirrors RevenueCat state. RevenueCat is the source of truth; our table is a cache for fast entitlement checks.

6. **Downloads table**: Tracks offline tour downloads. `expires_at` allows us to require re-download after subscription lapses.

7. **SQLite type conventions**: `string[]` and `jsonb` types do not exist in SQLite. All arrays and objects are stored as `TEXT` columns containing JSON. Validated at the application layer. `REAL` is avoided for monetary amounts — use `INTEGER` cents instead. `boolean` maps to `INTEGER` (0/1).

8. **Offline audio storage**: The iOS app downloads actual audio bytes to local storage (FileManager), NOT cached signed URLs. Signed GCS URLs are only used for the initial download. Offline tour data stores local file paths.
