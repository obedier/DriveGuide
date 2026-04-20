// Copies featured tours from LOCAL SQLite into PROD via the admin-only
// `POST /v1/tours/featured/seed` endpoint (gated by FEATURED_SEED_SECRET).
// Audio lives on the shared GCS bucket so no file copy is needed.
//
// Usage:
//   FEATURED_SEED_SECRET=<secret> npx tsx backend/scripts/publish-featured-to-prod.ts

import { getDb, closeDb } from '../src/lib/db.js';

const PROD_API_BASE = process.env.PROD_API_BASE ?? 'https://waipoint.o11r.com/v1';
const SECRET = process.env.FEATURED_SEED_SECRET;

if (!SECRET) {
  console.error('FEATURED_SEED_SECRET is required. Set the same value on prod via `gcloud run services update --update-env-vars`.');
  process.exit(1);
}

interface TourRow {
  id: string; user_id: string; title: string; description: string;
  location_query: string; center_lat: number | null; center_lng: number | null;
  duration_minutes: number; themes: string | null; language: string;
  transport_mode: string | null; story_arc_summary: string | null;
  total_distance_km: number | null; total_duration_minutes: number | null;
  share_id: string | null; metro_area: string | null;
}

interface StopRow {
  id: string; sequence_order: number; name: string; description: string;
  category: string; latitude: number; longitude: number;
  recommended_stay_minutes: number; is_optional: number;
  approach_narration: string; at_stop_narration: string; departure_narration: string;
  google_place_id: string | null; photo_url: string | null;
}

interface SegRow {
  id: string; segment_type: string; sequence_order: number; narration_text: string;
  content_hash: string; estimated_duration_seconds: number; trigger_lat: number | null;
  trigger_lng: number | null; trigger_radius_meters: number; language: string;
  from_stop_id: string | null; to_stop_id: string | null;
}

async function seed(tour: TourRow, stops: StopRow[], segs: SegRow[]): Promise<void> {
  const body = {
    tour: {
      id: tour.id, title: tour.title, description: tour.description,
      location_query: tour.location_query,
      center_lat: tour.center_lat, center_lng: tour.center_lng,
      duration_minutes: tour.duration_minutes,
      themes: tour.themes ? JSON.parse(tour.themes) : [],
      language: tour.language,
      transport_mode: tour.transport_mode,
      total_distance_km: tour.total_distance_km,
      total_duration_minutes: tour.total_duration_minutes,
      story_arc_summary: tour.story_arc_summary,
      share_id: tour.share_id,
      metro_area: tour.metro_area,
      stops: stops.map((s) => ({
        id: s.id, sequence_order: s.sequence_order, name: s.name,
        description: s.description, category: s.category,
        latitude: s.latitude, longitude: s.longitude,
        recommended_stay_minutes: s.recommended_stay_minutes,
        is_optional: Boolean(s.is_optional),
        approach_narration: s.approach_narration,
        at_stop_narration: s.at_stop_narration,
        departure_narration: s.departure_narration,
        google_place_id: s.google_place_id,
        photo_url: s.photo_url,
      })),
      narration_segments: segs.map((g) => ({
        id: g.id, segment_type: g.segment_type, sequence_order: g.sequence_order,
        narration_text: g.narration_text, content_hash: g.content_hash,
        estimated_duration_seconds: g.estimated_duration_seconds,
        trigger_lat: g.trigger_lat, trigger_lng: g.trigger_lng,
        trigger_radius_meters: g.trigger_radius_meters,
        language: g.language,
        from_stop_id: g.from_stop_id, to_stop_id: g.to_stop_id,
      })),
    },
  };

  const res = await fetch(`${PROD_API_BASE}/tours/featured/seed`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-admin-secret': SECRET!,
    },
    body: JSON.stringify(body),
  });
  const respText = await res.text();
  if (!res.ok) {
    throw new Error(`seed ${tour.id} failed ${res.status}: ${respText}`);
  }
  console.log(`  ✅ ${tour.id}: ${tour.title} — ${respText}`);
}

async function main(): Promise<void> {
  const db = getDb();
  const tours = db.prepare(`SELECT * FROM tours WHERE id LIKE 'featured-%' AND is_public = 1`).all() as TourRow[];
  if (!tours.length) {
    console.log('No featured tours found locally.');
    return;
  }
  console.log(`Seeding ${tours.length} featured tours to ${PROD_API_BASE}...`);
  for (const tour of tours) {
    const stops = db.prepare(`SELECT * FROM tour_stops WHERE tour_id = ? ORDER BY sequence_order`).all(tour.id) as StopRow[];
    const segs = db.prepare(`SELECT * FROM narration_segments WHERE tour_id = ? ORDER BY sequence_order`).all(tour.id) as SegRow[];
    try {
      await seed(tour, stops, segs);
    } catch (err) {
      console.error(`  ❌ ${tour.id}: ${(err as Error).message}`);
    }
  }
}

main()
  .then(() => closeDb())
  .catch((err) => { console.error(err); closeDb(); process.exit(1); });
