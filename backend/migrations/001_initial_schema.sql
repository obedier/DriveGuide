-- Private TourAi — Initial Schema

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  firebase_uid TEXT UNIQUE NOT NULL,
  email TEXT,
  display_name TEXT,
  avatar_url TEXT,
  preferred_language TEXT NOT NULL DEFAULT 'en',
  preferences TEXT NOT NULL DEFAULT '{}',  -- JSON
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE tours (
  id TEXT PRIMARY KEY,
  user_id TEXT REFERENCES users(id),
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  location_query TEXT NOT NULL,
  center_lat REAL,
  center_lng REAL,
  region_code TEXT DEFAULT 'south-florida',
  duration_minutes INTEGER NOT NULL,
  themes TEXT NOT NULL DEFAULT '[]',  -- JSON array
  language TEXT NOT NULL DEFAULT 'en',
  status TEXT NOT NULL DEFAULT 'generating',  -- generating | ready | failed
  error_code TEXT,
  error_message TEXT,
  route_data TEXT,  -- JSON
  maps_directions_url TEXT,
  total_distance_km REAL,
  total_duration_minutes INTEGER,
  story_arc_summary TEXT,
  cache_key TEXT,
  is_template INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE tour_stops (
  id TEXT PRIMARY KEY,
  tour_id TEXT NOT NULL REFERENCES tours(id) ON DELETE CASCADE,
  sequence_order INTEGER NOT NULL,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT 'landmark',
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  recommended_stay_minutes INTEGER NOT NULL DEFAULT 5,
  is_optional INTEGER NOT NULL DEFAULT 0,
  approach_narration TEXT NOT NULL DEFAULT '',
  at_stop_narration TEXT NOT NULL DEFAULT '',
  departure_narration TEXT NOT NULL DEFAULT '',
  place_data TEXT,  -- JSON
  google_place_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE narration_segments (
  id TEXT PRIMARY KEY,
  tour_id TEXT NOT NULL REFERENCES tours(id) ON DELETE CASCADE,
  from_stop_id TEXT REFERENCES tour_stops(id),
  to_stop_id TEXT REFERENCES tour_stops(id),
  segment_type TEXT NOT NULL,  -- intro | between_stops | approach | at_stop | departure | outro
  sequence_order INTEGER NOT NULL,
  narration_text TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  estimated_duration_seconds INTEGER NOT NULL DEFAULT 30,
  trigger_lat REAL,
  trigger_lng REAL,
  trigger_radius_meters REAL NOT NULL DEFAULT 50,
  language TEXT NOT NULL DEFAULT 'en',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE audio_files (
  id TEXT PRIMARY KEY,
  content_hash TEXT NOT NULL,
  language TEXT NOT NULL,
  voice_name TEXT NOT NULL,
  gcs_path TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL DEFAULT 0,
  file_size_bytes INTEGER NOT NULL DEFAULT 0,
  format TEXT NOT NULL DEFAULT 'mp3',
  usage_count INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_accessed_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE saved_tours (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tour_id TEXT NOT NULL REFERENCES tours(id) ON DELETE CASCADE,
  is_favorite INTEGER NOT NULL DEFAULT 0,
  last_played_at TEXT,
  progress_percent INTEGER NOT NULL DEFAULT 0,
  last_segment_id TEXT REFERENCES narration_segments(id),
  saved_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE tour_downloads (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tour_id TEXT NOT NULL REFERENCES tours(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending',  -- pending | downloading | complete | expired
  total_size_bytes INTEGER NOT NULL DEFAULT 0,
  downloaded_bytes INTEGER NOT NULL DEFAULT 0,
  downloaded_at TEXT,
  expires_at TEXT
);

CREATE TABLE subscriptions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  revenuecat_id TEXT,
  tier TEXT NOT NULL DEFAULT 'free',  -- free | single | weekly | monthly | annual
  status TEXT NOT NULL DEFAULT 'active',  -- active | expired | cancelled | grace_period
  single_tours_remaining INTEGER NOT NULL DEFAULT 0,
  current_period_start TEXT,
  current_period_end TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE purchases (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  revenuecat_transaction_id TEXT,
  product_id TEXT NOT NULL,
  purchase_type TEXT NOT NULL,
  amount_cents INTEGER NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'USD',
  purchased_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Indexes
CREATE INDEX idx_tours_center ON tours(center_lat, center_lng);
CREATE UNIQUE INDEX idx_tours_cache_key ON tours(cache_key) WHERE is_template = 1;
CREATE INDEX idx_tours_user_id ON tours(user_id);
CREATE INDEX idx_tour_stops_tour_order ON tour_stops(tour_id, sequence_order);
CREATE INDEX idx_tour_stops_geo ON tour_stops(latitude, longitude);
CREATE INDEX idx_narration_segments_tour_order ON narration_segments(tour_id, sequence_order);
CREATE INDEX idx_narration_segments_trigger ON narration_segments(trigger_lat, trigger_lng);
CREATE UNIQUE INDEX idx_audio_files_hash_lang ON audio_files(content_hash, language);
CREATE INDEX idx_saved_tours_user ON saved_tours(user_id, saved_at DESC);
CREATE INDEX idx_subscriptions_user ON subscriptions(user_id);
