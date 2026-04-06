import { FastifyInstance } from 'fastify';
import { requireAuth } from '../middleware/auth.js';
import { getDb } from '../lib/db.js';
import { newId } from '../lib/id.js';

export async function libraryRoutes(app: FastifyInstance): Promise<void> {
  // GET /library
  app.get<{ Querystring: { page?: string; limit?: string } }>('/library', {
    preHandler: requireAuth,
  }, async (request) => {
    const page = parseInt(request.query.page || '1', 10);
    const limit = Math.min(parseInt(request.query.limit || '20', 10), 50);
    const offset = (page - 1) * limit;
    const userId = request.user!.userId;

    const db = getDb();
    const total = (db.prepare('SELECT COUNT(*) as count FROM saved_tours WHERE user_id = ?').get(userId) as { count: number }).count;
    const rows = db.prepare(`
      SELECT st.*, t.title, t.description, t.location_query, t.duration_minutes, t.total_distance_km, t.status
      FROM saved_tours st JOIN tours t ON st.tour_id = t.id
      WHERE st.user_id = ? ORDER BY st.saved_at DESC LIMIT ? OFFSET ?
    `).all(userId, limit, offset) as Array<Record<string, unknown>>;

    return {
      data: rows.map((r) => ({
        id: r.id,
        tour_id: r.tour_id,
        is_favorite: Boolean(r.is_favorite),
        last_played_at: r.last_played_at,
        progress_percent: r.progress_percent,
        saved_at: r.saved_at,
        tour_title: r.title,
        tour_description: r.description,
        tour_location: r.location_query,
        tour_duration: r.duration_minutes,
        tour_distance: r.total_distance_km,
      })),
      pagination: { total, page, limit, has_more: offset + limit < total },
    };
  });

  // POST /library/:tour_id
  app.post<{ Params: { tour_id: string } }>('/library/:tour_id', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    const userId = request.user!.userId;
    const tourId = request.params.tour_id;
    const db = getDb();

    // Verify tour exists
    const tour = db.prepare('SELECT id FROM tours WHERE id = ?').get(tourId);
    if (!tour) return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Tour not found' } });

    const id = newId();
    db.prepare('INSERT OR IGNORE INTO saved_tours (id, user_id, tour_id) VALUES (?, ?, ?)')
      .run(id, userId, tourId);

    return reply.code(201).send({ saved_tour: { id, tour_id: tourId, is_favorite: false, progress_percent: 0 } });
  });

  // DELETE /library/:tour_id
  app.delete<{ Params: { tour_id: string } }>('/library/:tour_id', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    const db = getDb();
    db.prepare('DELETE FROM saved_tours WHERE user_id = ? AND tour_id = ?')
      .run(request.user!.userId, request.params.tour_id);
    return reply.code(204).send();
  });

  // PATCH /library/:tour_id
  app.patch<{ Params: { tour_id: string }; Body: { is_favorite?: boolean; progress_percent?: number; last_segment_id?: string } }>('/library/:tour_id', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    const db = getDb();
    const { is_favorite, progress_percent, last_segment_id } = request.body;
    const userId = request.user!.userId;
    const tourId = request.params.tour_id;

    const updates: string[] = [];
    const values: unknown[] = [];

    if (is_favorite !== undefined) { updates.push('is_favorite = ?'); values.push(is_favorite ? 1 : 0); }
    if (progress_percent !== undefined) { updates.push('progress_percent = ?'); values.push(progress_percent); }
    if (last_segment_id !== undefined) { updates.push('last_segment_id = ?'); values.push(last_segment_id); }

    if (updates.length === 0) return reply.code(400).send({ error: { code: 'NO_UPDATES', message: 'No fields to update' } });

    values.push(userId, tourId);
    db.prepare(`UPDATE saved_tours SET ${updates.join(', ')}, last_played_at = datetime('now') WHERE user_id = ? AND tour_id = ?`)
      .run(...values);

    return { status: 'updated' };
  });
}
