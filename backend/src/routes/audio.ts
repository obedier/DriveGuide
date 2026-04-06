import { FastifyInstance } from 'fastify';
import { generateTourAudio, synthesizeOrCache } from '../services/audio/tts.js';
import { getDb } from '../lib/db.js';

export async function audioRoutes(app: FastifyInstance): Promise<void> {
  // POST /tours/:id/audio — generate audio for a tour in the DB
  app.post<{ Params: { id: string }; Body: { language?: string; voice_preference?: string } }>('/tours/:id/audio', async (request, reply) => {
    const db = getDb();
    const tour = db.prepare('SELECT id, status FROM tours WHERE id = ?')
      .get(request.params.id) as { id: string; status: string } | undefined;

    if (!tour) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Tour not found on this server. Use POST /audio/generate instead.' } });
    }

    if (tour.status !== 'ready') {
      return reply.code(400).send({ error: { code: 'TOUR_NOT_READY', message: 'Tour is not ready for audio generation' } });
    }

    const result = await generateTourAudio(tour.id, request.body?.language, request.body?.voice_preference === 'premium' ? 'premium' : 'standard');

    return {
      tour_id: tour.id,
      segments: result.segments,
      total_duration_seconds: result.total_duration_seconds,
      total_size_bytes: result.total_size_bytes,
    };
  });

  // POST /audio/generate — generate audio from inline narration segments (for saved/offline tours)
  app.post<{ Body: { segments: Array<{ id: string; narration_text: string; content_hash: string; language?: string }>; voice_preference?: string } }>('/audio/generate', async (request, reply) => {
    const { segments, voice_preference } = request.body;

    if (!segments || segments.length === 0) {
      return reply.code(400).send({ error: { code: 'INVALID_INPUT', message: 'segments array is required' } });
    }

    const results = [];
    let totalDuration = 0;
    let totalSize = 0;

    for (const seg of segments) {
      const lang = seg.language ?? 'en';
      const voiceName = voice_preference === 'premium' ? 'en-US-Journey-D' : 'en-US-Neural2-J';
      const audio = await synthesizeOrCache(seg.narration_text, seg.content_hash, lang, voiceName);
      results.push({
        segment_id: seg.id,
        audio_url: audio.public_url,
        duration_seconds: audio.duration_seconds,
        file_size_bytes: audio.file_size_bytes,
        content_hash: audio.content_hash,
      });
      totalDuration += audio.duration_seconds;
      totalSize += audio.file_size_bytes;
    }

    return {
      segments: results,
      total_duration_seconds: totalDuration,
      total_size_bytes: totalSize,
    };
  });
}
