export type TourTheme = 'history' | 'food' | 'scenic' | 'hidden-gems' | 'architecture' | 'culture' | 'nature' | 'nightlife';
export type TourStatus = 'generating' | 'ready' | 'failed';
export type StopCategory = 'landmark' | 'restaurant' | 'viewpoint' | 'hidden-gem' | 'photo-op' | 'park' | 'museum' | 'neighborhood';
export type SegmentType = 'intro' | 'between_stops' | 'approach' | 'at_stop' | 'departure' | 'outro';
export type SubscriptionTier = 'free' | 'single' | 'weekly' | 'monthly' | 'annual';
export type SubscriptionStatus = 'active' | 'expired' | 'cancelled' | 'grace_period';
export type VoicePreference = 'male' | 'female' | 'neutral';

export interface GeoPoint {
  latitude: number;
  longitude: number;
}

export interface Tour {
  id: string;
  user_id: string | null;
  title: string;
  description: string;
  location_query: string;
  center_lat: number | null;
  center_lng: number | null;
  region_code: string;
  duration_minutes: number;
  themes: TourTheme[];
  language: string;
  status: TourStatus;
  error_code: string | null;
  error_message: string | null;
  route_data: unknown;
  maps_directions_url: string | null;
  total_distance_km: number | null;
  total_duration_minutes: number | null;
  story_arc_summary: string | null;
  cache_key: string | null;
  is_template: boolean;
  stops: TourStop[];
  narration_segments: NarrationSegment[];
  created_at: string;
  updated_at: string;
}

export interface TourStop {
  id: string;
  tour_id: string;
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
  place_data: unknown;
  google_place_id: string | null;
  created_at: string;
}

export interface NarrationSegment {
  id: string;
  tour_id: string;
  from_stop_id: string | null;
  to_stop_id: string | null;
  segment_type: SegmentType;
  sequence_order: number;
  narration_text: string;
  content_hash: string;
  estimated_duration_seconds: number;
  trigger_lat: number | null;
  trigger_lng: number | null;
  trigger_radius_meters: number;
  language: string;
  audio_url?: string;
  created_at: string;
}

export interface TourPreview {
  title: string;
  description: string;
  stop_count: number;
  duration_minutes: number;
  total_distance_km: number | null;
  preview_stops: TourStopPreview[];
  maps_preview_url: string | null;
}

export interface TourStopPreview {
  name: string;
  category: StopCategory;
  teaser: string;
}

export interface AudioSegment {
  segment_id: string;
  audio_url: string;
  duration_seconds: number;
  file_size_bytes: number;
  content_hash: string;
}

export interface UserProfile {
  id: string;
  email: string | null;
  display_name: string | null;
  avatar_url: string | null;
  preferred_language: string;
  preferences: UserPreferences;
  subscription: SubscriptionInfo;
  created_at: string;
}

export interface UserPreferences {
  default_themes: TourTheme[];
  default_duration_minutes: number;
  voice_preference: VoicePreference;
  auto_download_audio: boolean;
}

export interface SubscriptionInfo {
  tier: SubscriptionTier;
  status: SubscriptionStatus;
  single_tours_remaining: number;
  current_period_end: string | null;
}

export interface GenerateTourRequest {
  location: string;
  duration_minutes: number;
  themes?: TourTheme[];
  language?: string;
  start_address?: string;
  end_address?: string;
}
