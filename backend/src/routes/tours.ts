import { FastifyInstance } from 'fastify';
import { generateTour, loadTour, generatePreview } from '../services/tour/generator.js';
import { geocode, nearbySearch } from '../services/tour/maps.js';
import { requireAuth, optionalAuth } from '../middleware/auth.js';
import { getDb } from '../lib/db.js';
import type { GenerateTourRequest } from '../models/types.js';

export async function tourRoutes(app: FastifyInstance): Promise<void> {
  // POST /tours/verify-location — PUBLIC — geocode and return coordinates for map confirmation
  app.post<{ Body: { location: string } }>('/tours/verify-location', async (request, reply) => {
    const { location } = request.body;
    if (!location) {
      return reply.code(400).send({ error: { code: 'INVALID_INPUT', message: 'Location is required' } });
    }

    try {
      const geo = await geocode(location);
      // Also grab a few POIs to show what's in the area
      const places = await nearbySearch(geo.latitude, geo.longitude, 3000, ['tourist_attraction', 'point_of_interest']);
      return {
        verified: true,
        location: {
          latitude: geo.latitude,
          longitude: geo.longitude,
          formatted_address: geo.formatted_address,
        },
        nearby_highlights: places.slice(0, 5).map((p) => ({
          name: p.name,
          latitude: p.latitude,
          longitude: p.longitude,
        })),
      };
    } catch {
      return reply.code(404).send({
        error: { code: 'LOCATION_NOT_FOUND', message: `Could not find "${location}". Try a more specific address or city name.` },
      });
    }
  });

  // POST /tours/preview — PUBLIC — returns preview (3 stops, teaser narration)
  app.post<{ Body: GenerateTourRequest }>('/tours/preview', {
    preHandler: optionalAuth,
  }, async (request, reply) => {
    const body = request.body;

    if (!body.location || !body.duration_minutes || body.duration_minutes < 30 || body.duration_minutes > 360) {
      return reply.code(400).send({
        error: { code: 'INVALID_INPUT', message: 'Location required, duration must be 30-360 minutes' },
      });
    }

    // Pass ALL fields through — transport_mode, speed_mph, custom_prompt, start/end address
    const tour = await generateTour(body, request.user?.userId ?? null);

    return { preview: generatePreview(tour), tour_id: tour.id };
  });

  // POST /tours/full — PUBLIC for MVP — returns the complete tour
  app.post<{ Body: GenerateTourRequest & { tour_id?: string } }>('/tours/full', async (request, reply) => {
    const body = request.body;

    // If we already have a tour_id from preview, just load it
    if (body.tour_id) {
      try {
        const tour = loadTour(body.tour_id);
        return { tour };
      } catch {
        // Tour not found, fall through to generate
      }
    }

    if (!body.location || !body.duration_minutes || body.duration_minutes < 30 || body.duration_minutes > 360) {
      return reply.code(400).send({
        error: { code: 'INVALID_INPUT', message: 'Location required, duration must be 30-360 minutes' },
      });
    }

    // Pass ALL fields through
    const tour = await generateTour(body, null);

    return { tour };
  });

  // POST /tours/generate — Authenticated
  app.post<{ Body: GenerateTourRequest }>('/tours/generate', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    const user = request.user!;
    const body = request.body;

    if (!body.location || !body.duration_minutes || body.duration_minutes < 30 || body.duration_minutes > 360) {
      return reply.code(400).send({
        error: { code: 'INVALID_INPUT', message: 'Location required, duration must be 30-360 minutes' },
      });
    }

    // Check entitlement
    const db = getDb();
    const sub = db.prepare('SELECT tier, status, single_tours_remaining FROM subscriptions WHERE user_id = ?')
      .get(user.userId) as { tier: string; status: string; single_tours_remaining: number } | undefined;

    if (!sub || sub.tier === 'free') {
      const tour = await generateTour(body, null);
      return { preview: generatePreview(tour) };
    }

    if (sub.tier === 'single' && sub.single_tours_remaining <= 0) {
      return reply.code(402).send({
        error: { code: 'NO_TOURS_REMAINING', message: 'No single tours remaining. Purchase more or subscribe.' },
      });
    }

    const tour = await generateTour(body, user.userId);

    // Deduct single tour if applicable
    if (sub.tier === 'single') {
      db.prepare('UPDATE subscriptions SET single_tours_remaining = single_tours_remaining - 1 WHERE user_id = ?')
        .run(user.userId);
    }

    return { tour };
  });

  // GET /tours/:id
  app.get<{ Params: { id: string } }>('/tours/:id', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    const tour = loadTour(request.params.id);

    // IDOR protection
    if (tour.user_id && tour.user_id !== request.user!.userId && !tour.is_template) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Tour not found' } });
    }

    return { tour };
  });

  // DELETE /tours/:id
  app.delete<{ Params: { id: string } }>('/tours/:id', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    const db = getDb();
    const tour = db.prepare('SELECT user_id FROM tours WHERE id = ?').get(request.params.id) as { user_id: string } | undefined;

    if (!tour || tour.user_id !== request.user!.userId) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Tour not found' } });
    }

    db.prepare('DELETE FROM tours WHERE id = ?').run(request.params.id);
    return reply.code(204).send();
  });

  // POST /user/tours/sync — upload a local tour if it doesn't exist on server
  app.post<{ Body: Record<string, unknown> }>('/user/tours/sync', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    const db = getDb();
    const userId = request.user!.userId;
    const tour = request.body;
    const tourId = tour.id as string | undefined;

    if (!tourId) {
      return reply.code(400).send({ error: { code: 'INVALID_INPUT', message: 'Tour ID required' } });
    }

    // Check if already exists
    const existing = db.prepare('SELECT id, user_id FROM tours WHERE id = ?').get(tourId) as { id: string; user_id: string } | undefined;
    if (existing) {
      // If owned by someone else, refuse
      if (existing.user_id && existing.user_id !== userId) {
        return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Tour owned by another user' } });
      }
      // Already owned by this user → nothing to do
      return { status: 'already_synced' };
    }

    // Insert the tour with all fields. Using the generator's saveTour-like pattern.
    const { newId: genId } = await import('../lib/id.js');
    const stops = Array.isArray(tour.stops) ? tour.stops : [];
    const firstStop = stops[0] as Record<string, unknown> | undefined;
    const centerLat = (tour as any).center_lat ?? firstStop?.latitude ?? null;
    const centerLng = (tour as any).center_lng ?? firstStop?.longitude ?? null;

    db.prepare(`
      INSERT INTO tours (
        id, user_id, title, description, location_query, center_lat, center_lng,
        duration_minutes, themes, language, status, transport_mode,
        total_distance_km, story_arc_summary, share_id, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'ready', ?, ?, ?, ?, datetime('now'))
    `).run(
      tourId,
      userId,
      String(tour.title || 'Untitled Tour'),
      String(tour.description || ''),
      String((tour as any).location_query || ''),
      centerLat,
      centerLng,
      Number((tour as any).duration_minutes) || 60,
      JSON.stringify((tour as any).themes || []),
      String((tour as any).language || 'en'),
      String((tour as any).transport_mode || 'car'),
      (tour as any).total_distance_km ?? null,
      (tour as any).story_arc_summary ?? null,
      (tour as any).share_id ?? null,
    );

    // Insert stops
    const insertStop = db.prepare(`
      INSERT INTO tour_stops (
        id, tour_id, sequence_order, name, description, category,
        latitude, longitude, recommended_stay_minutes, is_optional,
        approach_narration, at_stop_narration, departure_narration,
        google_place_id, photo_url
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    for (const s of stops as Array<Record<string, unknown>>) {
      insertStop.run(
        s.id ?? genId(),
        tourId,
        s.sequence_order ?? 0,
        String(s.name || ''),
        String(s.description || ''),
        String(s.category || 'landmark'),
        Number(s.latitude) || 0,
        Number(s.longitude) || 0,
        Number(s.recommended_stay_minutes) || 10,
        s.is_optional ? 1 : 0,
        String(s.approach_narration || ''),
        String(s.at_stop_narration || ''),
        String(s.departure_narration || ''),
        s.google_place_id ?? null,
        s.photo_url ?? null,
      );
    }

    return { status: 'synced' };
  });

  // GET /user/tours — list current user's saved + archived tours (server-synced library)
  app.get('/user/tours', { preHandler: requireAuth }, async (request) => {
    const db = getDb();
    const userId = request.user!.userId;
    const rows = db.prepare(`
      SELECT id, is_archived FROM tours
      WHERE user_id = ? AND status = 'ready'
      ORDER BY created_at DESC
    `).all(userId) as Array<{ id: string; is_archived: number }>;

    const tours: unknown[] = [];
    const archived: unknown[] = [];
    for (const row of rows) {
      try {
        const tour = loadTour(row.id);
        if (row.is_archived) archived.push(tour);
        else tours.push(tour);
      } catch { /* skip bad rows */ }
    }
    return { tours, archived };
  });

  // POST /user/tours/:id/archive — archive a tour
  app.post<{ Params: { id: string } }>('/user/tours/:id/archive', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    const db = getDb();
    const tour = db.prepare('SELECT user_id FROM tours WHERE id = ?').get(request.params.id) as { user_id: string } | undefined;
    if (!tour || tour.user_id !== request.user!.userId) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Tour not found' } });
    }
    db.prepare('UPDATE tours SET is_archived = 1 WHERE id = ?').run(request.params.id);
    return { status: 'archived' };
  });

  // POST /user/tours/:id/unarchive — restore from archive
  app.post<{ Params: { id: string } }>('/user/tours/:id/unarchive', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    const db = getDb();
    const tour = db.prepare('SELECT user_id FROM tours WHERE id = ?').get(request.params.id) as { user_id: string } | undefined;
    if (!tour || tour.user_id !== request.user!.userId) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Tour not found' } });
    }
    db.prepare('UPDATE tours SET is_archived = 0 WHERE id = ?').run(request.params.id);
    return { status: 'unarchived' };
  });

  // GET /tours/shared/:shareId — PUBLIC — get a tour by share link
  app.get<{ Params: { shareId: string } }>('/tours/shared/:shareId', async (request, reply) => {
    const db = getDb();
    const row = db.prepare('SELECT id FROM tours WHERE share_id = ?').get(request.params.shareId) as { id: string } | undefined;
    if (!row) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Shared tour not found' } });
    }
    const tour = loadTour(row.id);
    return { tour };
  });

  // POST /tours/community/publish — publish full tour data to community
  app.post<{ Body: {
    tour: {
      id: string; title: string; description: string; location_query: string;
      center_lat?: number; center_lng?: number; duration_minutes: number;
      themes?: string[]; language?: string; transport_mode?: string;
      speed_mph?: number; custom_prompt?: string; maps_directions_url?: string;
      total_distance_km?: number; total_duration_minutes?: number;
      story_arc_summary?: string; share_id?: string;
      stops: Array<{
        id: string; sequence_order: number; name: string; description: string;
        category: string; latitude: number; longitude: number;
        recommended_stay_minutes: number; is_optional: boolean;
        approach_narration: string; at_stop_narration: string; departure_narration: string;
        google_place_id?: string; photo_url?: string;
      }>;
      narration_segments: Array<{
        id: string; segment_type: string; sequence_order: number;
        narration_text: string; content_hash: string;
        estimated_duration_seconds: number; trigger_lat?: number;
        trigger_lng?: number; trigger_radius_meters: number; language: string;
        from_stop_id?: string; to_stop_id?: string;
      }>;
    };
  } }>('/tours/community/publish', {
    preHandler: requireAuth,
  }, async (request) => {
    const db = getDb();
    const userId = request.user!.userId;
    const t = request.body.tour;
    const { nanoid } = await import('nanoid');
    const shareId = t.share_id || nanoid(10);

    // Upsert tour
    const existing = db.prepare('SELECT id FROM tours WHERE id = ?').get(t.id) as { id: string } | undefined;
    if (existing) {
      db.prepare('UPDATE tours SET is_public = 1, share_id = ?, updated_at = datetime(\'now\') WHERE id = ?').run(shareId, t.id);
    } else {
      db.prepare(`INSERT INTO tours (id, user_id, title, description, location_query, center_lat, center_lng,
        duration_minutes, themes, language, status, transport_mode, speed_mph, custom_prompt,
        maps_directions_url, total_distance_km, total_duration_minutes, story_arc_summary,
        share_id, is_public) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'ready', ?, ?, ?, ?, ?, ?, ?, ?, 1)`)
        .run(t.id, userId, t.title, t.description, t.location_query,
          t.center_lat ?? null, t.center_lng ?? null, t.duration_minutes,
          JSON.stringify(t.themes || []), t.language || 'en',
          t.transport_mode || 'car', t.speed_mph ?? null, t.custom_prompt ?? null,
          t.maps_directions_url ?? null, t.total_distance_km ?? null,
          t.total_duration_minutes ?? null, t.story_arc_summary ?? null, shareId);

      // Insert stops
      const stopStmt = db.prepare(`INSERT OR REPLACE INTO tour_stops (id, tour_id, sequence_order, name, description,
        category, latitude, longitude, recommended_stay_minutes, is_optional,
        approach_narration, at_stop_narration, departure_narration, google_place_id, photo_url)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
      for (const s of t.stops) {
        stopStmt.run(s.id, t.id, s.sequence_order, s.name, s.description, s.category,
          s.latitude, s.longitude, s.recommended_stay_minutes, s.is_optional ? 1 : 0,
          s.approach_narration, s.at_stop_narration, s.departure_narration,
          s.google_place_id ?? null, s.photo_url ?? null);
      }

      // Insert narration segments
      const segStmt = db.prepare(`INSERT OR REPLACE INTO narration_segments (id, tour_id, segment_type, sequence_order,
        narration_text, content_hash, estimated_duration_seconds, trigger_lat, trigger_lng,
        trigger_radius_meters, language, from_stop_id, to_stop_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
      for (const n of t.narration_segments) {
        segStmt.run(n.id, t.id, n.segment_type, n.sequence_order, n.narration_text,
          n.content_hash, n.estimated_duration_seconds, n.trigger_lat ?? null,
          n.trigger_lng ?? null, n.trigger_radius_meters, n.language,
          n.from_stop_id ?? null, n.to_stop_id ?? null);
      }
    }

    return { status: 'published', share_id: shareId };
  });

  // POST /tours/:id/publish — publish existing server tour to community (legacy)
  app.post<{ Params: { id: string } }>('/tours/:id/publish', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    const db = getDb();
    const tour = db.prepare('SELECT id, user_id, share_id FROM tours WHERE id = ?').get(request.params.id) as { id: string; user_id: string; share_id: string | null } | undefined;
    if (!tour || tour.user_id !== request.user!.userId) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Tour not found' } });
    }
    if (!tour.share_id) {
      const { nanoid } = await import('nanoid');
      const shareId = nanoid(10);
      db.prepare('UPDATE tours SET share_id = ? WHERE id = ?').run(shareId, tour.id);
    }
    db.prepare('UPDATE tours SET is_public = 1, updated_at = datetime(\'now\') WHERE id = ?').run(tour.id);
    return { status: 'published' };
  });

  // POST /tours/:id/unpublish — remove tour from community
  app.post<{ Params: { id: string } }>('/tours/:id/unpublish', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    const db = getDb();
    const tour = db.prepare('SELECT id, user_id FROM tours WHERE id = ?').get(request.params.id) as { id: string; user_id: string } | undefined;
    if (!tour || tour.user_id !== request.user!.userId) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Tour not found' } });
    }
    db.prepare('UPDATE tours SET is_public = 0, updated_at = datetime(\'now\') WHERE id = ?').run(tour.id);
    return { status: 'unpublished' };
  });

  // GET /tours/community — PUBLIC — list community tours, optionally filtered by location
  app.get<{ Querystring: { lat?: string; lng?: string; radius_km?: string; page?: string; limit?: string } }>('/tours/community', async (request) => {
    const db = getDb();
    const page = parseInt(request.query.page || '1', 10);
    const limit = Math.min(parseInt(request.query.limit || '20', 10), 50);
    const offset = (page - 1) * limit;

    const lat = request.query.lat ? parseFloat(request.query.lat) : null;
    const lng = request.query.lng ? parseFloat(request.query.lng) : null;
    const radiusKm = parseFloat(request.query.radius_km || '100');

    let rows: Array<Record<string, unknown>>;
    let total: number;

    if (lat !== null && lng !== null) {
      // Simple bounding box filter (approximate, good enough for discovery)
      const latDelta = radiusKm / 111.0;
      const lngDelta = radiusKm / (111.0 * Math.cos((lat * Math.PI) / 180));

      total = (db.prepare(`
        SELECT COUNT(*) as count FROM tours
        WHERE is_public = 1 AND status = 'ready'
        AND center_lat BETWEEN ? AND ? AND center_lng BETWEEN ? AND ?
      `).get(lat - latDelta, lat + latDelta, lng - lngDelta, lng + lngDelta) as { count: number }).count;

      rows = db.prepare(`
        SELECT id, title, description, location_query, duration_minutes, transport_mode,
               center_lat, center_lng, total_distance_km, share_id,
               community_rating, community_rating_count, created_at
        FROM tours
        WHERE is_public = 1 AND status = 'ready'
        AND center_lat BETWEEN ? AND ? AND center_lng BETWEEN ? AND ?
        ORDER BY community_rating_count DESC, created_at DESC
        LIMIT ? OFFSET ?
      `).all(lat - latDelta, lat + latDelta, lng - lngDelta, lng + lngDelta, limit, offset) as Array<Record<string, unknown>>;
    } else {
      total = (db.prepare(`SELECT COUNT(*) as count FROM tours WHERE is_public = 1 AND status = 'ready'`).get() as { count: number }).count;
      rows = db.prepare(`
        SELECT id, title, description, location_query, duration_minutes, transport_mode,
               center_lat, center_lng, total_distance_km, share_id,
               community_rating, community_rating_count, created_at
        FROM tours
        WHERE is_public = 1 AND status = 'ready'
        ORDER BY community_rating_count DESC, created_at DESC
        LIMIT ? OFFSET ?
      `).all(limit, offset) as Array<Record<string, unknown>>;
    }

    return {
      tours: rows.map((r) => ({
        id: r.id,
        title: r.title,
        description: r.description,
        location: r.location_query,
        duration_minutes: r.duration_minutes,
        transport_mode: r.transport_mode || 'car',
        center_lat: r.center_lat,
        center_lng: r.center_lng,
        distance_km: r.total_distance_km,
        share_id: r.share_id,
        rating: r.community_rating,
        rating_count: r.community_rating_count,
        created_at: r.created_at,
      })),
      pagination: { total, page, limit, has_more: offset + limit < total },
    };
  });

  // POST /tours/:id/rate — rate a community tour
  app.post<{ Params: { id: string }; Body: { rating: number; review?: string } }>('/tours/:id/rate', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    const db = getDb();
    const { rating, review } = request.body;
    const tourId = request.params.id;
    const userId = request.user!.userId;

    if (!rating || rating < 1 || rating > 5) {
      return reply.code(400).send({ error: { code: 'INVALID_INPUT', message: 'Rating must be 1-5' } });
    }

    const tour = db.prepare('SELECT id, is_public FROM tours WHERE id = ?').get(tourId) as { id: string; is_public: number } | undefined;
    if (!tour) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Tour not found' } });
    }

    const { newId: genId } = await import('../lib/id.js');

    // Upsert rating
    db.prepare(`INSERT INTO community_ratings (id, tour_id, user_id, rating, review)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(tour_id, user_id) DO UPDATE SET rating = ?, review = ?, created_at = datetime('now')`)
      .run(genId(), tourId, userId, rating, review ?? null, rating, review ?? null);

    // Recalculate aggregate
    const agg = db.prepare('SELECT AVG(rating) as avg_rating, COUNT(*) as count FROM community_ratings WHERE tour_id = ?')
      .get(tourId) as { avg_rating: number; count: number };

    db.prepare('UPDATE tours SET community_rating = ?, community_rating_count = ? WHERE id = ?')
      .run(Math.round(agg.avg_rating * 10) / 10, agg.count, tourId);

    return { status: 'rated', rating: Math.round(agg.avg_rating * 10) / 10, rating_count: agg.count };
  });

  // GET /tours/:id/ratings — get ratings for a tour
  app.get<{ Params: { id: string } }>('/tours/:id/ratings', async (request) => {
    const db = getDb();
    const rows = db.prepare(`SELECT r.rating, r.review, r.created_at, u.display_name
      FROM community_ratings r LEFT JOIN users u ON r.user_id = u.id
      WHERE r.tour_id = ? ORDER BY r.created_at DESC LIMIT 50`)
      .all(request.params.id) as Array<Record<string, unknown>>;

    return {
      ratings: rows.map((r) => ({
        rating: r.rating,
        review: r.review,
        author: r.display_name || 'Explorer',
        created_at: r.created_at,
      })),
    };
  });
}
