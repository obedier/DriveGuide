import { TextToSpeechClient } from '@google-cloud/text-to-speech';
import { Storage } from '@google-cloud/storage';
import { LRUCache } from 'lru-cache';
import { getDb } from '../../lib/db.js';
import { newId } from '../../lib/id.js';
import { env } from '../../config/env.js';

const ttsClient = new TextToSpeechClient();
const storage = new Storage({ projectId: env.gcpProjectId });
const bucket = storage.bucket(env.audioCacheBucket);

// In-memory LRU: content_hash -> gcs_path
const audioPathCache = new LRUCache<string, string>({ max: 5000, ttl: 1000 * 60 * 60 });

interface AudioResult {
  gcs_path: string;
  signed_url: string;
  duration_seconds: number;
  file_size_bytes: number;
  content_hash: string;
}

export async function synthesizeOrCache(
  text: string,
  contentHash: string,
  language: string = 'en-US',
  voiceName: string = 'en-US-Neural2-J',
): Promise<AudioResult> {
  // Check in-memory cache
  const cachedPath = audioPathCache.get(contentHash);
  if (cachedPath) {
    const url = await getSignedUrl(cachedPath);
    const db = getDb();
    const row = db.prepare('SELECT duration_seconds, file_size_bytes FROM audio_files WHERE content_hash = ? AND language = ?')
      .get(contentHash, language) as { duration_seconds: number; file_size_bytes: number } | undefined;

    db.prepare('UPDATE audio_files SET last_accessed_at = datetime(\'now\'), usage_count = usage_count + 1 WHERE content_hash = ? AND language = ?')
      .run(contentHash, language);

    return {
      gcs_path: cachedPath,
      signed_url: url,
      duration_seconds: row?.duration_seconds ?? 0,
      file_size_bytes: row?.file_size_bytes ?? 0,
      content_hash: contentHash,
    };
  }

  // Check database
  const db = getDb();
  const dbRow = db.prepare('SELECT gcs_path, duration_seconds, file_size_bytes FROM audio_files WHERE content_hash = ? AND language = ?')
    .get(contentHash, language) as { gcs_path: string; duration_seconds: number; file_size_bytes: number } | undefined;

  if (dbRow) {
    audioPathCache.set(contentHash, dbRow.gcs_path);
    const url = await getSignedUrl(dbRow.gcs_path);
    db.prepare('UPDATE audio_files SET last_accessed_at = datetime(\'now\'), usage_count = usage_count + 1 WHERE content_hash = ? AND language = ?')
      .run(contentHash, language);
    return { ...dbRow, signed_url: url, content_hash: contentHash };
  }

  // Check GCS directly (belt and suspenders)
  const gcsPath = `audio/${contentHash}.mp3`;
  const [exists] = await bucket.file(gcsPath).exists();
  if (exists) {
    const url = await getSignedUrl(gcsPath);
    audioPathCache.set(contentHash, gcsPath);
    // Re-insert DB row
    db.prepare(`
      INSERT OR IGNORE INTO audio_files (id, content_hash, language, voice_name, gcs_path, format)
      VALUES (?, ?, ?, ?, ?, 'mp3')
    `).run(newId(), contentHash, language, voiceName, gcsPath);
    return { gcs_path: gcsPath, signed_url: url, duration_seconds: 0, file_size_bytes: 0, content_hash: contentHash };
  }

  // Generate new audio
  const [response] = await ttsClient.synthesizeSpeech({
    input: { text },
    voice: { languageCode: language, name: voiceName },
    audioConfig: { audioEncoding: 'MP3', speakingRate: 0.95, pitch: 0 },
  });

  const audioContent = response.audioContent as Buffer;
  const fileSize = audioContent.length;
  const estimatedDuration = Math.ceil(text.split(/\s+/).length / 2.5);

  // Upload to GCS
  await bucket.file(gcsPath).save(audioContent, {
    metadata: { contentType: 'audio/mpeg', cacheControl: 'public, max-age=31536000' },
  });

  // Save to database
  db.prepare(`
    INSERT INTO audio_files (id, content_hash, language, voice_name, gcs_path, duration_seconds, file_size_bytes, format)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'mp3')
  `).run(newId(), contentHash, language, voiceName, gcsPath, estimatedDuration, fileSize);

  audioPathCache.set(contentHash, gcsPath);
  const url = await getSignedUrl(gcsPath);

  return {
    gcs_path: gcsPath,
    signed_url: url,
    duration_seconds: estimatedDuration,
    file_size_bytes: fileSize,
    content_hash: contentHash,
  };
}

async function getSignedUrl(gcsPath: string): Promise<string> {
  const [url] = await bucket.file(gcsPath).getSignedUrl({
    action: 'read',
    expires: Date.now() + 24 * 60 * 60 * 1000, // 24 hours
  });
  return url;
}

export async function generateTourAudio(
  tourId: string,
  language?: string,
): Promise<{ segments: Array<{ segment_id: string; audio_url: string; duration_seconds: number; file_size_bytes: number; content_hash: string }>; total_duration_seconds: number; total_size_bytes: number }> {
  const db = getDb();
  const segmentRows = db.prepare('SELECT * FROM narration_segments WHERE tour_id = ? ORDER BY sequence_order')
    .all(tourId) as Array<{ id: string; narration_text: string; content_hash: string; language: string }>;

  const results = [];
  let totalDuration = 0;
  let totalSize = 0;

  for (const seg of segmentRows) {
    const lang = language ?? seg.language;
    const audio = await synthesizeOrCache(seg.narration_text, seg.content_hash, lang);
    results.push({
      segment_id: seg.id,
      audio_url: audio.signed_url,
      duration_seconds: audio.duration_seconds,
      file_size_bytes: audio.file_size_bytes,
      content_hash: audio.content_hash,
    });
    totalDuration += audio.duration_seconds;
    totalSize += audio.file_size_bytes;
  }

  return { segments: results, total_duration_seconds: totalDuration, total_size_bytes: totalSize };
}
