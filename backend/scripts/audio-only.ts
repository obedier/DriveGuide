// One-off helper: run Kokoro TTS for an already-seeded tour.
// Used when the main pilot run crashed partway through; we do not want to
// re-pay for Gemini if a tour's narration is already persisted.
//
// Resumes by skipping any segment whose MP3 already exists in GCS.
// Uses /synthesize (one segment per call) — simpler than /batch, and Cloud Run
// 5-min timeout no longer bites since each call is ~10-30s.
//
// Usage: TOUR_ID=featured-miami-driving npx tsx backend/scripts/audio-only.ts

import { getDb, closeDb } from '../src/lib/db.js';

const tourId = process.env.TOUR_ID;
if (!tourId) {
  console.error('TOUR_ID env var required.');
  process.exit(1);
}

const KOKORO_URL = process.env.KOKORO_TTS_URL || 'https://kokoro-tts-801121217326.us-east1.run.app';
const BUCKET = 'driveguide-audio-cache';

async function audioExists(contentHash: string): Promise<boolean> {
  // HEAD on public bucket URL — cheap, no auth needed.
  const url = `https://storage.googleapis.com/${BUCKET}/audio/kokoro-${contentHash}.mp3`;
  const res = await fetch(url, { method: 'HEAD' });
  return res.ok;
}

async function synthesizeOne(text: string, contentHash: string, voice: string = 'af_bella'): Promise<{ audioUrl: string; duration: number; cached: boolean }> {
  const res = await fetch(`${KOKORO_URL}/synthesize`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text, content_hash: contentHash, voice, speed: 0.95 }),
    signal: AbortSignal.timeout(120_000), // 2 min per segment
  });
  if (!res.ok) throw new Error(`Kokoro ${res.status}: ${await res.text()}`);
  const data = await res.json() as { audio_url: string; duration_seconds?: number; cached?: boolean };
  return { audioUrl: data.audio_url, duration: data.duration_seconds ?? 0, cached: data.cached ?? false };
}

async function main(): Promise<void> {
  const db = getDb();
  type Row = { id: string; narration_text: string; content_hash: string; language: string; segment_type: string; sequence_order: number };
  const rows = db.prepare(`
    SELECT id, narration_text, content_hash, language, segment_type, sequence_order
    FROM narration_segments WHERE tour_id = ? ORDER BY sequence_order
  `).all(tourId) as Row[];

  console.log(`Synthesizing ${rows.length} segments for ${tourId}`);
  const voice = process.env.KOKORO_VOICE || 'af_bella';

  const samples: Array<{ type: string; url: string }> = [];
  let totalSeconds = 0;
  let done = 0;
  let skipped = 0;

  for (const row of rows) {
    const exists = await audioExists(row.content_hash);
    if (exists) {
      skipped++;
      done++;
      const url = `https://storage.googleapis.com/${BUCKET}/audio/kokoro-${row.content_hash}.mp3`;
      if (samples.length < 5 && (row.segment_type === 'intro' || row.segment_type === 'at_stop' || row.segment_type === 'outro')) {
        samples.push({ type: row.segment_type, url });
      }
      continue;
    }
    const start = Date.now();
    try {
      const res = await synthesizeOne(row.narration_text, row.content_hash, voice);
      totalSeconds += res.duration;
      done++;
      console.log(`  [${done}/${rows.length}] ${row.segment_type} ${row.sequence_order} → ${Math.round(res.duration)}s audio in ${Date.now() - start}ms`);
      if (samples.length < 5 && (row.segment_type === 'intro' || row.segment_type === 'at_stop' || row.segment_type === 'outro')) {
        samples.push({ type: row.segment_type, url: res.audioUrl });
      }
    } catch (err) {
      console.error(`  [${done + 1}/${rows.length}] ${row.segment_type} ${row.sequence_order} FAILED:`, err instanceof Error ? err.message : err);
    }
  }

  console.log(`\nDone. ${done}/${rows.length} segments (${skipped} were already cached). Audio ~${Math.round(totalSeconds)}s.`);
  console.log('Sample URLs:');
  for (const s of samples) console.log(`  [${s.type}] ${s.url}`);
}

main().then(() => closeDb()).catch((e) => { console.error(e); closeDb(); process.exit(1); });
