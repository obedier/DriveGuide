import { FastifyInstance } from 'fastify';
import { generateTourAudio } from '../services/audio/tts.js';
import { requireAuth } from '../middleware/auth.js';
import { getDb } from '../lib/db.js';

export async function audioRoutes(app: FastifyInstance): Promise<void> {
  // POST /tours/:id/audio
  app.post<{ Params: { id: string }; Body: { language?: string; voice_preference?: string } }>('/tours/:id/audio', {
    preHandler: requireAuth,
  }, async (request, reply) => {
    const db = getDb();
    const tour = db.prepare('SELECT id, user_id, status FROM tours WHERE id = ?')
      .get(request.params.id) as { id: string; user_id: string; status: string } | undefined;

    if (!tour || (tour.user_id && tour.user_id !== request.user!.userId)) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Tour not found' } });
    }

    if (tour.status !== 'ready') {
      return reply.code(400).send({ error: { code: 'TOUR_NOT_READY', message: 'Tour is not ready for audio generation' } });
    }

    const result = await generateTourAudio(tour.id, request.body?.language);

    return {
      tour_id: tour.id,
      segments: result.segments,
      total_duration_seconds: result.total_duration_seconds,
      total_size_bytes: result.total_size_bytes,
    };
  });
}
