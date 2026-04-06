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
    const { location, duration_minutes, themes, language } = request.body;

    if (!location || !duration_minutes || duration_minutes < 30 || duration_minutes > 360) {
      return reply.code(400).send({
        error: { code: 'INVALID_INPUT', message: 'Location required, duration must be 30-360 minutes' },
      });
    }

    const tour = await generateTour(
      { location, duration_minutes, themes, language },
      request.user?.userId ?? null,
    );

    return { preview: generatePreview(tour), tour_id: tour.id };
  });

  // POST /tours/full — PUBLIC for MVP — returns the complete tour
  // TODO: Gate behind auth + subscription when Firebase is wired up
  app.post<{ Body: GenerateTourRequest & { tour_id?: string } }>('/tours/full', async (request, reply) => {
    const { tour_id, location, duration_minutes, themes, language } = request.body;

    // If we already have a tour_id from preview, just load it
    if (tour_id) {
      try {
        const tour = loadTour(tour_id);
        return { tour };
      } catch {
        // Tour not found, fall through to generate
      }
    }

    if (!location || !duration_minutes || duration_minutes < 30 || duration_minutes > 360) {
      return reply.code(400).send({
        error: { code: 'INVALID_INPUT', message: 'Location required, duration must be 30-360 minutes' },
      });
    }

    const tour = await generateTour(
      { location, duration_minutes, themes, language },
      null,
    );

    return { tour };
  });

  // POST /tours/generate — Authenticated
  app.post<{ Body: GenerateTourRequest }>('/tours/generate', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    const user = request.user!;
    const { location, duration_minutes, themes, language, start_address, end_address } = request.body;

    if (!location || !duration_minutes || duration_minutes < 30 || duration_minutes > 360) {
      return reply.code(400).send({
        error: { code: 'INVALID_INPUT', message: 'Location required, duration must be 30-360 minutes' },
      });
    }

    // Check entitlement
    const db = getDb();
    const sub = db.prepare('SELECT tier, status, single_tours_remaining FROM subscriptions WHERE user_id = ?')
      .get(user.userId) as { tier: string; status: string; single_tours_remaining: number } | undefined;

    if (!sub || sub.tier === 'free') {
      // Free users get preview only
      const tour = await generateTour(
        { location, duration_minutes, themes, language, start_address, end_address },
        null,
      );
      return { preview: generatePreview(tour) };
    }

    if (sub.tier === 'single' && sub.single_tours_remaining <= 0) {
      return reply.code(402).send({
        error: { code: 'NO_TOURS_REMAINING', message: 'No single tours remaining. Purchase more or subscribe.' },
      });
    }

    const tour = await generateTour(
      { location, duration_minutes, themes, language, start_address, end_address },
      user.userId,
    );

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
}
