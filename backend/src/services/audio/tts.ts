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
  public_url: string;
  duration_seconds: number;
  file_size_bytes: number;
  content_hash: string;
}

export async function synthesizeOrCache(
  text: string,
  contentHash: string,
  language: string = 'en',
  voiceName: string = 'en-US-Neural2-J',
): Promise<AudioResult> {
  // Normalize short language codes to BCP-47 for TTS API
  const ttsLanguage = normalizeLangCode(language);
  // Check in-memory cache
  const cachedPath = audioPathCache.get(contentHash);
  if (cachedPath) {
    const url = getPublicUrl(cachedPath);
    const db = getDb();
    const row = db.prepare('SELECT duration_seconds, file_size_bytes FROM audio_files WHERE content_hash = ? AND language = ?')
      .get(contentHash, language) as { duration_seconds: number; file_size_bytes: number } | undefined;

    db.prepare('UPDATE audio_files SET last_accessed_at = datetime(\'now\'), usage_count = usage_count + 1 WHERE content_hash = ? AND language = ?')
      .run(contentHash, language);

    return {
      gcs_path: cachedPath,
      public_url: url,
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
    const url = getPublicUrl(dbRow.gcs_path);
    db.prepare('UPDATE audio_files SET last_accessed_at = datetime(\'now\'), usage_count = usage_count + 1 WHERE content_hash = ? AND language = ?')
      .run(contentHash, language);
    return { ...dbRow, public_url: url, content_hash: contentHash };
  }

  // Check GCS directly (belt and suspenders)
  const gcsPath = `audio/${contentHash}.mp3`;
  const [exists] = await bucket.file(gcsPath).exists();
  if (exists) {
    const url = getPublicUrl(gcsPath);
    audioPathCache.set(contentHash, gcsPath);
    // Re-insert DB row
    db.prepare(`
      INSERT OR IGNORE INTO audio_files (id, content_hash, language, voice_name, gcs_path, format)
      VALUES (?, ?, ?, ?, ?, 'mp3')
    `).run(newId(), contentHash, language, voiceName, gcsPath);
    return { gcs_path: gcsPath, public_url: url, duration_seconds: 0, file_size_bytes: 0, content_hash: contentHash };
  }

  // Strip symbols that TTS would annunciate
  const cleanText = sanitizeForSpeech(text);

  // Generate new audio — use SSML for Neural2 voices, plain text for Journey
  const isJourneyVoice = voiceName.includes('Journey');
  const input = isJourneyVoice
    ? { text: cleanText }  // Journey voices work best with plain text
    : { ssml: textToNaturalSsml(cleanText) };  // Neural2 benefits from SSML pauses

  const [response] = await ttsClient.synthesizeSpeech({
    input,
    voice: { languageCode: ttsLanguage, name: voiceName },
    audioConfig: {
      audioEncoding: 'MP3',
      speakingRate: 0.92,
    },
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
  const url = getPublicUrl(gcsPath);

  return {
    gcs_path: gcsPath,
    public_url: url,
    duration_seconds: estimatedDuration,
    file_size_bytes: fileSize,
    content_hash: contentHash,
  };
}

function getPublicUrl(gcsPath: string): string {
  return `https://storage.googleapis.com/${env.audioCacheBucket}/${gcsPath}`;
}

// Premium voice names (Journey voices — most natural for narration)
const PREMIUM_VOICES: Record<string, string> = {
  'en-US': 'en-US-Journey-D',
  'es-US': 'es-US-Journey-D',
  'fr-FR': 'fr-FR-Journey-D',
  'de-DE': 'de-DE-Journey-D',
  'pt-BR': 'pt-BR-Journey-D',
  'it-IT': 'it-IT-Journey-D',
};

const STANDARD_VOICES: Record<string, string> = {
  'en-US': 'en-US-Neural2-J',
  'es-US': 'es-US-Neural2-B',
  'fr-FR': 'fr-FR-Neural2-B',
  'de-DE': 'de-DE-Neural2-B',
  'pt-BR': 'pt-BR-Neural2-B',
  'it-IT': 'it-IT-Neural2-C',
};

export async function generateTourAudio(
  tourId: string,
  language?: string,
  voiceQuality: string = 'standard',
): Promise<{ segments: Array<{ segment_id: string; audio_url: string; duration_seconds: number; file_size_bytes: number; content_hash: string }>; total_duration_seconds: number; total_size_bytes: number; voice_quality: string }> {
  const db = getDb();
  const segmentRows = db.prepare('SELECT * FROM narration_segments WHERE tour_id = ? ORDER BY sequence_order')
    .all(tourId) as Array<{ id: string; narration_text: string; content_hash: string; language: string }>;

  const results = [];
  let totalDuration = 0;
  let totalSize = 0;

  for (const seg of segmentRows) {
    const lang = language ?? seg.language;
    const ttsLang = normalizeLangCode(lang);
    const voiceName = voiceQuality === 'premium'
      ? (PREMIUM_VOICES[ttsLang] ?? STANDARD_VOICES[ttsLang] ?? 'en-US-Neural2-J')
      : (STANDARD_VOICES[ttsLang] ?? 'en-US-Neural2-J');
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

  return { segments: results, total_duration_seconds: totalDuration, total_size_bytes: totalSize, voice_quality: voiceQuality };
}

/**
 * Convert plain text to SSML with natural speech patterns:
 * - Expand abbreviations to prevent glitchy pronunciation
 * - Add pauses after sentences for breathing room
 * - Add subtle emphasis on proper nouns (capitalized words mid-sentence)
 */
/**
 * Strip markdown and symbols that TTS engines would annunciate literally.
 * Converts *emphasis* to plain text, removes #, [], (), etc.
 */
function sanitizeForSpeech(text: string): string {
  return text
    // Markdown bold/italic: **word** or *word* → word (with emphasis via SSML later)
    .replace(/\*{1,3}([^*]+)\*{1,3}/g, '$1')
    // Markdown headers: ## Title → Title
    .replace(/^#{1,6}\s*/gm, '')
    // Markdown links: [text](url) → text
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    // HTML tags
    .replace(/<[^>]+>/g, '')
    // Backticks
    .replace(/`([^`]+)`/g, '$1')
    // Underscores used as emphasis: _word_ → word
    .replace(/_([^_]+)_/g, '$1')
    // Hashtags: #Miami → Miami
    .replace(/#(\w)/g, '$1')
    // Bullet points
    .replace(/^\s*[-•]\s*/gm, '')
    // Remaining special chars that would be spoken
    .replace(/[~^{}|\\]/g, '')
    // Multiple spaces
    .replace(/\s{2,}/g, ' ')
    .trim();
}

function textToNaturalSsml(text: string): string {
  let processed = text
    // Expand common abbreviations
    .replace(/\bSt\.\s/g, 'Street ')
    .replace(/\bAve\.\s/g, 'Avenue ')
    .replace(/\bBlvd\.\s/g, 'Boulevard ')
    .replace(/\bDr\.\s/g, 'Drive ')
    .replace(/\bRd\.\s/g, 'Road ')
    .replace(/\bHwy\.\s/g, 'Highway ')
    .replace(/\bMt\.\s/g, 'Mount ')
    .replace(/\bFt\.\s/g, 'Fort ')
    .replace(/\bPl\.\s/g, 'Place ')
    .replace(/\bCt\.\s/g, 'Court ')
    .replace(/\bLn\.\s/g, 'Lane ')
    .replace(/\bSq\.\s/g, 'Square ')
    .replace(/\bN\.\s/g, 'North ')
    .replace(/\bS\.\s/g, 'South ')
    .replace(/\bE\.\s/g, 'East ')
    .replace(/\bW\.\s/g, 'West ')
    .replace(/\bNE\b/g, 'Northeast')
    .replace(/\bNW\b/g, 'Northwest')
    .replace(/\bSE\b/g, 'Southeast')
    .replace(/\bSW\b/g, 'Southwest')
    // Escape XML special chars
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    // Add natural pauses after sentences (period, exclamation, question mark)
    .replace(/([.!?])\s+/g, '$1<break time="400ms"/> ')
    // Add shorter pause after commas for breathing
    .replace(/,\s+/g, ',<break time="200ms"/> ')
    // Add pause before em-dashes
    .replace(/\s*—\s*/g, '<break time="300ms"/> ')
    // Add pause around ellipses
    .replace(/\.\.\./g, '<break time="500ms"/>');

  return `<speak>${processed}</speak>`;
}

function normalizeLangCode(lang: string): string {
  const map: Record<string, string> = {
    en: 'en-US', es: 'es-US', fr: 'fr-FR', de: 'de-DE',
    pt: 'pt-BR', ja: 'ja-JP', ko: 'ko-KR', zh: 'cmn-CN',
    hi: 'hi-IN', ar: 'ar-XA', it: 'it-IT',
  };
  return map[lang] ?? lang;
}
