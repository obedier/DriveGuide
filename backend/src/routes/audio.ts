import { FastifyInstance } from 'fastify';
import { generateTourAudio, synthesizeOrCache } from '../services/audio/tts.js';
import { synthesizeWithKokoro, isKokoroAvailable } from '../services/audio/kokoro.js';
import { getDb } from '../lib/db.js';

export async function audioRoutes(app: FastifyInstance): Promise<void> {
  // POST /tours/:id/audio — generate audio for a tour in the DB
  app.post<{ Params: { id: string }; Body: { language?: string; voice_preference?: string; voice_engine?: string } }>('/tours/:id/audio', async (request, reply) => {
    const db = getDb();
    const tour = db.prepare('SELECT id, status FROM tours WHERE id = ?')
      .get(request.params.id) as { id: string; status: string } | undefined;

    if (!tour) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Tour not found on this server. Use POST /audio/generate instead.' } });
    }

    if (tour.status !== 'ready') {
      return reply.code(400).send({ error: { code: 'TOUR_NOT_READY', message: 'Tour is not ready for audio generation' } });
    }

    const voiceEngine = request.body?.voice_engine;

    // Use Kokoro if requested and available
    if (voiceEngine === 'kokoro') {
      try {
        const segmentRows = db.prepare('SELECT id, narration_text, content_hash, language FROM narration_segments WHERE tour_id = ? ORDER BY sequence_order')
          .all(tour.id) as Array<{ id: string; narration_text: string; content_hash: string; language: string }>;

        const result = await synthesizeWithKokoro(segmentRows);
        return { tour_id: tour.id, ...result };
      } catch (err) {
        app.log.warn(`Kokoro TTS failed, falling back to Google: ${err}`);
        // Fall through to Google TTS
      }
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
  app.post<{ Body: { segments: Array<{ id: string; narration_text: string; content_hash: string; language?: string }>; voice_preference?: string; voice_engine?: string } }>('/audio/generate', async (request, reply) => {
    const { segments, voice_preference, voice_engine } = request.body;

    if (!segments || segments.length === 0) {
      return reply.code(400).send({ error: { code: 'INVALID_INPUT', message: 'segments array is required' } });
    }

    // Use Kokoro if requested
    if (voice_engine === 'kokoro') {
      try {
        const result = await synthesizeWithKokoro(
          segments.map((s) => ({ id: s.id, narration_text: s.narration_text, content_hash: s.content_hash, language: s.language ?? 'en' })),
        );
        return result;
      } catch (err) {
        app.log.warn(`Kokoro TTS failed, falling back to Google: ${err}`);
        // Fall through to Google TTS
      }
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

  // GET /audio/engines — list available voice engines
  app.get('/audio/engines', async () => {
    const kokoroUp = await isKokoroAvailable();
    return {
      engines: [
        { id: 'google', name: 'Google Cloud TTS', available: true, qualities: ['standard', 'premium'] },
        { id: 'kokoro', name: 'Kokoro 82M', available: kokoroUp, voices: ['af_heart', 'af_bella', 'am_adam', 'am_michael', 'bf_emma', 'bm_george'] },
      ],
    };
  });
}
