import { createHash } from 'crypto';
import { getDb } from '../../lib/db.js';
import { newId } from '../../lib/id.js';
import { geocode, nearbySearch, optimizeRoute } from './maps.js';
import { generateTourContent } from './gemini.js';
import type { Tour, TourStop, NarrationSegment, GenerateTourRequest, TourTheme } from '../../models/types.js';

const GENERATION_TIMEOUT_MS = 90_000;

export async function generateTour(
  request: GenerateTourRequest,
  userId: string | null,
): Promise<Tour> {
  const themes = request.themes ?? ['history', 'hidden-gems', 'scenic'];
  const language = request.language ?? 'en';

  // Check cache
  const cacheKey = buildCacheKey(request.location, request.duration_minutes, themes);
  const cached = findCachedTour(cacheKey);
  if (cached) return cached;

  const tourId = newId();
  const db = getDb();

  // Insert placeholder
  db.prepare(`
    INSERT INTO tours (id, user_id, title, description, location_query, duration_minutes, themes, language, status, cache_key)
    VALUES (?, ?, '', '', ?, ?, ?, ?, 'generating', ?)
  `).run(tourId, userId, request.location, request.duration_minutes, JSON.stringify(themes), language, cacheKey);

  try {
    const tour = await generateWithTimeout(tourId, request, themes, language, userId);
    return tour;
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error';
    db.prepare(`UPDATE tours SET status = 'failed', error_code = 'GENERATION_ERROR', error_message = ? WHERE id = ?`)
      .run(message, tourId);
    throw err;
  }
}

async function generateWithTimeout(
  tourId: string,
  request: GenerateTourRequest,
  themes: TourTheme[],
  language: string,
  userId: string | null,
): Promise<Tour> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), GENERATION_TIMEOUT_MS);

  try {
    // Step 1: Geocode
    const geo = await geocode(request.location);

    // Step 2: Find nearby places
    const places = await nearbySearch(geo.latitude, geo.longitude);

    // Step 3: Generate content with Gemini
    const content = await generateTourContent(
      request.location,
      geo.formatted_address,
      geo.latitude,
      geo.longitude,
      request.duration_minutes,
      themes,
      places,
      language,
    );

    // Step 4: Optimize route
    const stopCoords = content.stops.map((s) => ({ lat: s.latitude, lng: s.longitude }));
    const origin = stopCoords[0];
    const destination = stopCoords[stopCoords.length - 1];
    const waypoints = stopCoords.slice(1, -1);

    let route;
    if (waypoints.length > 0) {
      route = await optimizeRoute(origin, destination, waypoints);
    } else {
      route = {
        legs: [],
        waypoint_order: [],
        total_distance_km: 0,
        total_duration_minutes: request.duration_minutes,
        overview_polyline: '',
        directions_url: `https://www.google.com/maps/dir/?api=1&origin=${origin.lat},${origin.lng}&destination=${destination.lat},${destination.lng}&travelmode=driving`,
      };
    }

    // Reorder stops based on route optimization
    const orderedStops = reorderStops(content.stops, route.waypoint_order);

    // Step 5: Save everything to database
    const db = getDb();
    const saveTour = db.transaction(() => {
      db.prepare(`
        UPDATE tours SET
          title = ?, description = ?, center_lat = ?, center_lng = ?,
          status = 'ready', route_data = ?, maps_directions_url = ?,
          total_distance_km = ?, total_duration_minutes = ?,
          story_arc_summary = ?, is_template = ?, updated_at = datetime('now')
        WHERE id = ?
      `).run(
        content.title, content.description, geo.latitude, geo.longitude,
        JSON.stringify(route), route.directions_url,
        route.total_distance_km, route.total_duration_minutes,
        content.story_arc_summary, userId ? 0 : 1, tourId,
      );

      // Insert stops
      const insertStop = db.prepare(`
        INSERT INTO tour_stops (id, tour_id, sequence_order, name, description, category, latitude, longitude,
          recommended_stay_minutes, is_optional, approach_narration, at_stop_narration, departure_narration)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      const stopIds: string[] = [];
      for (let i = 0; i < orderedStops.length; i++) {
        const s = orderedStops[i];
        const stopId = newId();
        stopIds.push(stopId);
        insertStop.run(
          stopId, tourId, i, s.name, s.description, s.category,
          s.latitude, s.longitude, s.recommended_stay_minutes,
          s.is_optional ? 1 : 0, s.approach_narration, s.at_stop_narration, s.departure_narration,
        );
      }

      // Build and insert narration segments
      const segments = buildNarrationSegments(
        tourId, stopIds, orderedStops, content, language,
      );

      const insertSegment = db.prepare(`
        INSERT INTO narration_segments (id, tour_id, from_stop_id, to_stop_id, segment_type,
          sequence_order, narration_text, content_hash, estimated_duration_seconds,
          trigger_lat, trigger_lng, trigger_radius_meters, language)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      for (const seg of segments) {
        insertSegment.run(
          seg.id, seg.tour_id, seg.from_stop_id, seg.to_stop_id, seg.segment_type,
          seg.sequence_order, seg.narration_text, seg.content_hash,
          seg.estimated_duration_seconds, seg.trigger_lat, seg.trigger_lng,
          seg.trigger_radius_meters, seg.language,
        );
      }

      return { stopIds, segments };
    });

    saveTour();

    // Load and return full tour
    return loadTour(tourId);
  } finally {
    clearTimeout(timeout);
  }
}

function buildNarrationSegments(
  tourId: string,
  stopIds: string[],
  stops: Array<{ latitude: number; longitude: number; approach_narration: string; at_stop_narration: string; departure_narration: string }>,
  content: { intro_narration: string; outro_narration: string; between_stop_narrations: string[] },
  language: string,
): NarrationSegment[] {
  const segments: NarrationSegment[] = [];
  let order = 0;

  // Intro
  segments.push(makeSegment(tourId, null, stopIds[0], 'intro', order++, content.intro_narration, stops[0].latitude, stops[0].longitude, language));

  for (let i = 0; i < stops.length; i++) {
    const stop = stops[i];
    const stopId = stopIds[i];

    // Approach
    segments.push(makeSegment(tourId, i > 0 ? stopIds[i - 1] : null, stopId, 'approach', order++, stop.approach_narration, stop.latitude, stop.longitude, language));

    // At stop
    segments.push(makeSegment(tourId, null, stopId, 'at_stop', order++, stop.at_stop_narration, stop.latitude, stop.longitude, language));

    // Departure
    segments.push(makeSegment(tourId, stopId, i < stops.length - 1 ? stopIds[i + 1] : null, 'departure', order++, stop.departure_narration, stop.latitude, stop.longitude, language));

    // Between stops narration
    if (i < stops.length - 1 && content.between_stop_narrations[i]) {
      const midLat = (stop.latitude + stops[i + 1].latitude) / 2;
      const midLng = (stop.longitude + stops[i + 1].longitude) / 2;
      segments.push(makeSegment(tourId, stopId, stopIds[i + 1], 'between_stops', order++, content.between_stop_narrations[i], midLat, midLng, language));
    }
  }

  // Outro
  const lastStop = stops[stops.length - 1];
  segments.push(makeSegment(tourId, stopIds[stopIds.length - 1], null, 'outro', order++, content.outro_narration, lastStop.latitude, lastStop.longitude, language));

  return segments;
}

function makeSegment(
  tourId: string,
  fromStopId: string | null,
  toStopId: string | null,
  type: NarrationSegment['segment_type'],
  order: number,
  text: string,
  triggerLat: number,
  triggerLng: number,
  language: string,
): NarrationSegment {
  const wordsPerSecond = 2.5;
  const wordCount = text.split(/\s+/).length;
  const duration = Math.ceil(wordCount / wordsPerSecond);

  return {
    id: newId(),
    tour_id: tourId,
    from_stop_id: fromStopId,
    to_stop_id: toStopId,
    segment_type: type,
    sequence_order: order,
    narration_text: text,
    content_hash: hashContent(text, language, 'en-US-Neural2-J'),
    estimated_duration_seconds: duration,
    trigger_lat: triggerLat,
    trigger_lng: triggerLng,
    trigger_radius_meters: 50,
    language,
    created_at: new Date().toISOString(),
  };
}

function hashContent(text: string, language: string, voice: string): string {
  return createHash('sha256')
    .update(`${text}\x00${language}\x00${voice}`)
    .digest('hex');
}

function reorderStops<T>(stops: T[], waypointOrder: number[]): T[] {
  if (waypointOrder.length === 0) return stops;

  const first = stops[0];
  const last = stops[stops.length - 1];
  const middle = stops.slice(1, -1);
  const reordered = waypointOrder.map((i) => middle[i]);
  return [first, ...reordered, last];
}

function buildCacheKey(location: string, duration: number, themes: TourTheme[]): string {
  const normalized = `${location.toLowerCase().trim()}|${duration}|${themes.sort().join(',')}`;
  return createHash('sha256').update(normalized).digest('hex').slice(0, 16);
}

function findCachedTour(cacheKey: string): Tour | null {
  const db = getDb();
  const row = db.prepare(`SELECT id FROM tours WHERE cache_key = ? AND is_template = 1 AND status = 'ready' LIMIT 1`).get(cacheKey) as { id: string } | undefined;
  if (!row) return null;
  return loadTour(row.id);
}

export function loadTour(tourId: string): Tour {
  const db = getDb();
  const tourRow = db.prepare('SELECT * FROM tours WHERE id = ?').get(tourId) as Record<string, unknown>;
  if (!tourRow) throw new Error(`Tour not found: ${tourId}`);

  const stops = db.prepare('SELECT * FROM tour_stops WHERE tour_id = ? ORDER BY sequence_order').all(tourId) as TourStop[];
  const segments = db.prepare('SELECT * FROM narration_segments WHERE tour_id = ? ORDER BY sequence_order').all(tourId) as NarrationSegment[];

  return {
    ...tourRow,
    themes: JSON.parse((tourRow.themes as string) || '[]'),
    route_data: tourRow.route_data ? JSON.parse(tourRow.route_data as string) : null,
    is_template: Boolean(tourRow.is_template),
    stops: stops.map((s) => ({
      ...s,
      is_optional: Boolean(s.is_optional),
      place_data: s.place_data ? JSON.parse(s.place_data as string) : null,
    })),
    narration_segments: segments,
  } as Tour;
}

export function generatePreview(tour: Tour): {
  title: string;
  description: string;
  stop_count: number;
  duration_minutes: number;
  total_distance_km: number | null;
  preview_stops: Array<{ name: string; category: string; teaser: string }>;
} {
  return {
    title: tour.title,
    description: tour.description,
    stop_count: tour.stops.length,
    duration_minutes: tour.duration_minutes,
    total_distance_km: tour.total_distance_km,
    preview_stops: tour.stops.slice(0, 3).map((s) => ({
      name: s.name,
      category: s.category,
      teaser: s.at_stop_narration.slice(0, 150) + '...',
    })),
  };
}
