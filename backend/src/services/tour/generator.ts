import { createHash } from 'crypto';
import { getDb } from '../../lib/db.js';
import { newId } from '../../lib/id.js';
import { geocode, nearbySearch, optimizeRoute, getPlacePhoto } from './maps.js';
import { computeNauticalRoute } from './nautical.js';
import { generateBoatTour, calculateMaritimeSegments } from './boat-engine.js';
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
  const transportMode = request.transport_mode ?? 'car';
  const cacheKey = buildCacheKey(request.location, request.duration_minutes, themes, transportMode, request.custom_prompt);
  const cached = findCachedTour(cacheKey);
  if (cached) return cached;

  const tourId = newId();
  const db = getDb();

  // Insert placeholder
  db.prepare(`
    INSERT INTO tours (id, user_id, title, description, location_query, duration_minutes, themes, language, status, cache_key, transport_mode, speed_mph, custom_prompt)
    VALUES (?, ?, '', '', ?, ?, ?, ?, 'generating', ?, ?, ?, ?)
  `).run(tourId, userId, request.location, request.duration_minutes, JSON.stringify(themes), language, cacheKey, transportMode, request.speed_mph ?? null, request.custom_prompt ?? null);

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

    const transportMode = request.transport_mode ?? 'car';

    // ── BOAT TOURS: Use dedicated boat engine ──
    if (transportMode === 'boat') {
      return await generateBoatTourFlow(tourId, request, geo, userId);
    }

    // ── ALL OTHER MODES: Standard flow ──

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
      transportMode,
      request.speed_mph ?? null,
      request.custom_prompt ?? null,
      request.start_address ?? null,
      request.end_address ?? null,
    );

    // Step 4: Optimize route
    const stopCoords = content.stops.map((s) => ({ lat: s.latitude, lng: s.longitude }));
    const origin = stopCoords[0];
    const destination = stopCoords[stopCoords.length - 1];
    const waypoints = stopCoords.slice(1, -1);

    let route;
    if (waypoints.length > 0) {
      route = await optimizeRoute(origin, destination, waypoints, transportMode);
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
    const directionsUrl = route.directions_url;
    const totalDistanceKm = route.total_distance_km;
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
        JSON.stringify(route), directionsUrl,
        totalDistanceKm, route.total_duration_minutes,
        content.story_arc_summary, userId ? 0 : 1, tourId,
      );

      // Generate share ID
      const shareId = newId().slice(0, 10);
      db.prepare('UPDATE tours SET share_id = ? WHERE id = ?').run(shareId, tourId);

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

    // Fetch photos in background (don't block tour return)
    fetchPhotosForStops(tourId, orderedStops, places).catch(() => {});

    // Load and return full tour
    return loadTour(tourId);
  } finally {
    clearTimeout(timeout);
  }
}

// ─── Boat Tour Flow (dedicated engine) ───

async function generateBoatTourFlow(
  tourId: string,
  request: GenerateTourRequest,
  geo: { latitude: number; longitude: number; formatted_address: string },
  userId: string | null,
): Promise<Tour> {
  const db = getDb();
  const language = request.language ?? 'en';

  const content = await generateBoatTour(
    request.location,
    geo.formatted_address,
    geo.latitude,
    geo.longitude,
    request.duration_minutes,
    request.start_address ?? null,
    request.end_address ?? null,
    request.custom_prompt ?? null,
  );

  // Calculate maritime distances between stops
  const maritimeSegments = calculateMaritimeSegments(content.stops);
  const totalDistanceNm = maritimeSegments.reduce((sum, s) => sum + s.distance_nm, 0);
  const totalTravelMinutes = maritimeSegments.reduce((sum, s) => sum + s.estimated_minutes, 0);

  // Build nautical route
  const nautical = await computeNauticalRoute(content.stops);

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
      JSON.stringify({ maritime_segments: maritimeSegments, nautical }),
      nautical.chart_url,
      totalDistanceNm * 1.852, // store as km internally
      totalTravelMinutes,
      content.story_arc_summary, userId ? 0 : 1, tourId,
    );

    const shareId = newId().slice(0, 10);
    db.prepare('UPDATE tours SET share_id = ? WHERE id = ?').run(shareId, tourId);

    const insertStop = db.prepare(`
      INSERT INTO tour_stops (id, tour_id, sequence_order, name, description, category, latitude, longitude,
        recommended_stay_minutes, is_optional, approach_narration, at_stop_narration, departure_narration)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    const stopIds: string[] = [];
    for (let i = 0; i < content.stops.length; i++) {
      const s = content.stops[i];
      const stopId = newId();
      stopIds.push(stopId);
      insertStop.run(
        stopId, tourId, i, s.name, s.description, s.category,
        s.latitude, s.longitude, s.recommended_stay_minutes,
        0, s.approach_narration, s.at_stop_narration, s.departure_narration,
      );
    }

    // Build narration segments
    const segments = buildNarrationSegments(
      tourId, stopIds, content.stops, content, language,
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
  });

  saveTour();

  // Fetch photos for boat stops in background
  const places = await nearbySearch(geo.latitude, geo.longitude, 8000);
  fetchPhotosForStops(tourId, content.stops, places).catch(() => {});

  return loadTour(tourId);
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

async function fetchPhotosForStops(
  tourId: string,
  _stops: Array<{ name: string; latitude: number; longitude: number }>,
  nearbyPlaces: Array<{ place_id: string; name: string; latitude: number; longitude: number }>,
): Promise<void> {
  const db = getDb();
  const dbStops = db.prepare('SELECT id, name, latitude, longitude FROM tour_stops WHERE tour_id = ? ORDER BY sequence_order').all(tourId) as Array<{ id: string; name: string; latitude: number; longitude: number }>;

  for (const dbStop of dbStops) {
    // Find matching nearby place by proximity
    const match = nearbyPlaces.find((p) => {
      const dist = haversineKm(dbStop.latitude, dbStop.longitude, p.latitude, p.longitude);
      return dist < 0.5; // within 500m
    });

    if (match) {
      const photoUrl = await getPlacePhoto(match.place_id);
      if (photoUrl) {
        db.prepare('UPDATE tour_stops SET photo_url = ? WHERE id = ?').run(photoUrl, dbStop.id);
      }
    }
  }
}

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function buildCacheKey(location: string, duration: number, themes: TourTheme[], transport: string = 'car', customPrompt: string | null = null): string {
  const normalized = `${location.toLowerCase().trim()}|${duration}|${themes.sort().join(',')}|${transport}|${customPrompt ?? ''}`;
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
  // Surface a ready-to-play audio_url on every narration segment that has
  // already been synthesized (audio_files row present). We do NOT synthesize
  // URLs for segments without an audio_files row — iOS treats an empty URL as
  // "generate on demand" and synthesizes via /audio/generate. If we emitted
  // a URL for un-synthesized audio, iOS would try to download it, 404, and
  // fall through to a broken state.
  const bucket = process.env.GCS_AUDIO_CACHE_BUCKET || 'driveguide-audio-cache';
  const segmentRows = db.prepare(`
    SELECT ns.*, af.gcs_path AS _audio_gcs_path
    FROM narration_segments ns
    LEFT JOIN audio_files af ON af.content_hash = ns.content_hash AND af.language = ns.language
    WHERE ns.tour_id = ?
    ORDER BY ns.sequence_order
  `).all(tourId) as Array<NarrationSegment & { _audio_gcs_path?: string | null }>;
  const segments = segmentRows.map((row) => {
    const { _audio_gcs_path, ...seg } = row;
    if (_audio_gcs_path) {
      return { ...seg, audio_url: `https://storage.googleapis.com/${bucket}/${_audio_gcs_path}` };
    }
    return seg;
  });

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
