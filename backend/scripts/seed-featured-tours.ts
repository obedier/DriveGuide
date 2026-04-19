// Featured-tours seed — pilot: ONE metro (Miami), TWO tours.
//
// Produces the 2-hour driving tour "Causeway to Coconut Grove" and the 4-hour
// walking tour "South Beach Deco + Wynwood" defined in
// ios/docs/featured-tours-research.md (entry #5, line 247).
//
// Writes:
//   - SQLite rows (tours + tour_stops + narration_segments)
//     with is_public = 1, is_featured = 1, owner = waipoint-featured-system
//   - TTS audio cached in the Kokoro GCS bucket
//
// Emits a per-tour cost report on stdout so we can extrapolate full rollout.
//
// Usage:
//   SEED_METRO=miami npx tsx backend/scripts/seed-featured-tours.ts
//
// Env:
//   DRY_RUN=1  — generate narration + content but do not write to DB or call TTS.
//   SKIP_TTS=1 — generate + seed DB but skip Kokoro TTS calls.
//   SKIP_PHOTOS=1 — do not fetch Google Places photos.

import { createHash } from 'crypto';
import { runMigrations } from '../src/lib/migrate.js';
import { getDb, closeDb } from '../src/lib/db.js';
import { newId } from '../src/lib/id.js';
import { resolvePlacePhotoByName } from '../src/services/tour/maps.js';
import {
  generateFeaturedTourContent,
  type CuratedStop,
  type FeaturedTourRequest,
} from '../src/services/tour/featured.js';
import { synthesizeWithKokoro } from '../src/services/audio/kokoro.js';

const FEATURED_OWNER = 'waipoint-featured-system';
const METRO_MIAMI = 'Miami';

// ─── Curated Miami tours (from ios/docs/featured-tours-research.md line 247) ──

const miamiDrivingStops: CuratedStop[] = [
  {
    name: 'South Pointe Park',
    neighborhood: 'South Beach',
    latitude: 25.7684, longitude: -80.1340,
    category: 'park', recommended_stay_minutes: 10,
    hook: 'Southernmost tip of Miami Beach where cruise ships thread the Government Cut channel — the lighthouse pavilion and limestone jetty get the gold-hour cruise-ship photos.',
  },
  {
    name: 'Versace Mansion',
    neighborhood: 'Ocean Drive',
    latitude: 25.7816, longitude: -80.1318,
    category: 'landmark', recommended_stay_minutes: 5,
    hook: 'The 1930 Mediterranean revival where Gianni Versace lived and was shot on the front steps in 1997 — now a boutique hotel with a 24-karat-gold-mosaic pool.',
  },
  {
    name: 'MacArthur Causeway cruise-ship corridor',
    neighborhood: 'Causeway',
    latitude: 25.7787, longitude: -80.1616,
    category: 'viewpoint', recommended_stay_minutes: 5,
    hook: 'The span over Government Cut — Star Island and Hibiscus Island mansions to your south, PortMiami cruise terminals to your north. Watch a 1,000-foot ship slide underneath you.',
  },
  {
    name: 'Pérez Art Museum Miami',
    neighborhood: 'Downtown',
    latitude: 25.7858, longitude: -80.1867,
    category: 'museum', recommended_stay_minutes: 8,
    hook: 'Herzog & de Meuron raised the whole building on stilts and hung living gardens — designed to survive hurricanes AND display art.',
  },
  {
    name: 'Brickell skyline drive-by',
    neighborhood: 'Brickell',
    latitude: 25.7625, longitude: -80.1918,
    category: 'viewpoint', recommended_stay_minutes: 3,
    hook: 'Miami financial district — Latin American banks nicknamed this "The Manhattan of the South" in the 90s. Every tower under 10 years old.',
  },
  {
    name: 'Hobie Beach (Rickenbacker Causeway)',
    neighborhood: 'Key Biscayne',
    latitude: 25.7412, longitude: -80.1702,
    category: 'viewpoint', recommended_stay_minutes: 10,
    hook: 'Free kite-surfer beach with the best Miami-skyline-from-the-water view in the city. Used in every Miami music video.',
  },
  {
    name: 'Vizcaya Museum & Gardens',
    neighborhood: 'Coconut Grove',
    latitude: 25.7443, longitude: -80.2109,
    category: 'landmark', recommended_stay_minutes: 15,
    hook: '1916 Italian Renaissance estate that International Harvester VP James Deering built to feel 400 years old from day one — limestone carved to look weathered.',
  },
];

const miamiWalkingStops: CuratedStop[] = [
  {
    name: 'South Pointe Park Pier',
    neighborhood: 'South Beach',
    latitude: 25.7684, longitude: -80.1340,
    category: 'park', recommended_stay_minutes: 10,
    hook: 'Start: boardwalk pier where cruise ships slide past at eye-level. Free, no gate, dolphin-spotting common at dawn.',
  },
  {
    name: 'Clevelander / Colony / Leslie Hotels',
    neighborhood: 'Ocean Drive',
    latitude: 25.7812, longitude: -80.1326,
    category: 'landmark', recommended_stay_minutes: 12,
    hook: 'The three Ocean Drive icons: neon Colony sign is the single most-photographed piece of Art Deco in America.',
  },
  {
    name: 'Casa Casuarina (Versace Mansion)',
    neighborhood: 'Ocean Drive',
    latitude: 25.7816, longitude: -80.1318,
    category: 'landmark', recommended_stay_minutes: 8,
    hook: 'The Versace steps. If you stand on 11th and Ocean, the mansion is directly across — photos only; the hotel restricts access.',
  },
  {
    name: 'News Café',
    neighborhood: 'Ocean Drive',
    latitude: 25.7796, longitude: -80.1308,
    category: 'restaurant', recommended_stay_minutes: 15, is_optional: true,
    hook: 'The 24-hour café where Versace bought his last magazines the morning he died. Still open.',
  },
  {
    name: 'Lummus Park lifeguard stands',
    neighborhood: 'South Beach',
    latitude: 25.7825, longitude: -80.1315,
    category: 'photo-op', recommended_stay_minutes: 15,
    hook: 'The candy-striped lifeguard huts — each designed by a different Miami architect after Hurricane Andrew.',
  },
  {
    name: 'Art Deco Welcome Center',
    neighborhood: 'South Beach',
    latitude: 25.7803, longitude: -80.1307,
    category: 'museum', recommended_stay_minutes: 20,
    hook: 'Home of Barbara Capitman, who physically lay down in front of bulldozers in the 1970s to save these buildings. Free gallery.',
  },
  {
    name: 'Lincoln Road Mall',
    neighborhood: 'South Beach',
    latitude: 25.7907, longitude: -80.1394,
    category: 'neighborhood', recommended_stay_minutes: 25,
    hook: 'Morris Lapidus\' 1960 pedestrian mall — Lapidus also designed the Fontainebleau. Water features, sculptures, open-air galleries.',
  },
  {
    name: "Joe's Stone Crab takeaway window",
    neighborhood: 'South of Fifth',
    latitude: 25.7685, longitude: -80.1376,
    category: 'restaurant', recommended_stay_minutes: 20, is_optional: true,
    hook: 'The only place in Miami where locals and A-listers share a line. Stone-crab claws from Oct-May; year-round takeaway.',
  },
  {
    name: 'Wynwood Walls',
    neighborhood: 'Wynwood',
    latitude: 25.8009, longitude: -80.1990,
    category: 'landmark', recommended_stay_minutes: 45,
    hook: 'Tony Goldman turned a warehouse district into an outdoor mural museum in 2009. Paid entry, worth it — rotating artists twice a year.',
  },
  {
    name: 'NW 2nd Ave mural strip',
    neighborhood: 'Wynwood',
    latitude: 25.8015, longitude: -80.1994,
    category: 'neighborhood', recommended_stay_minutes: 20,
    hook: 'Free outdoor murals — same vibe as Wynwood Walls, no ticket. Most Instagrammable block in Florida.',
  },
  {
    name: 'Panther Coffee flagship',
    neighborhood: 'Wynwood',
    latitude: 25.8017, longitude: -80.1991,
    category: 'restaurant', recommended_stay_minutes: 15,
    hook: 'Miami\'s third-wave coffee HQ. Roasted on-site. The cafecito still costs a dollar — house rule.',
  },
  {
    name: 'Wynwood Marketplace',
    neighborhood: 'Wynwood',
    latitude: 25.8006, longitude: -80.1987,
    category: 'neighborhood', recommended_stay_minutes: 20,
    hook: 'Finish: outdoor food + art market. Cuban sandwiches, live DJs on weekends — a soft landing after a 4-hour walk.',
  },
];

interface PilotTourDef {
  key: string;
  tourTitleHint: string;
  transportMode: 'car' | 'walk';
  durationMinutes: number;
  narrativeTheme: string;
  stops: CuratedStop[];
}

const miamiTours: PilotTourDef[] = [
  {
    key: 'miami-driving',
    tourTitleHint: 'Causeway to Coconut Grove',
    transportMode: 'car',
    durationMinutes: 120,
    narrativeTheme: 'Miami\'s hero drive at golden hour — three causeways, three neighborhoods, the city from water-level to Vizcaya\'s limestone gates.',
    stops: miamiDrivingStops,
  },
  {
    key: 'miami-walking',
    tourTitleHint: 'South Beach Deco + Wynwood',
    transportMode: 'walk',
    durationMinutes: 240,
    narrativeTheme: 'South Beach\'s Art Deco strip walked at human scale, then a short rideshare to Wynwood\'s mural capital — Miami\'s two most photographed neighborhoods back-to-back.',
    stops: miamiWalkingStops,
  },
];

// ─── DB helpers ────────────────────────────────────────────────────────────

function ensureSystemUser(): void {
  const db = getDb();
  db.prepare(`
    INSERT OR IGNORE INTO users (id, firebase_uid, email, display_name, preferred_language)
    VALUES (?, ?, ?, ?, ?)
  `).run(FEATURED_OWNER, FEATURED_OWNER, 'featured@waipoint.app', 'wAIpoint Featured', 'en');
}

function hashContent(text: string, language: string, voice: string): string {
  return createHash('sha256').update(`${text}\x00${language}\x00${voice}`).digest('hex');
}

interface PersistedTour {
  tourId: string;
  stopIds: string[];
  segmentCount: number;
  totalNarrationChars: number;
}

function persistTour(
  tour: PilotTourDef,
  content: Awaited<ReturnType<typeof generateFeaturedTourContent>>['content'],
  photoUrls: Array<string | null>,
): PersistedTour {
  const db = getDb();
  const tourId = `featured-${tour.key}`;
  const language = 'en';
  const voice = 'kokoro-af-bella';

  const totalStayMinutes = content.stops.reduce((s, x) => s + x.recommended_stay_minutes, 0);

  const persist = db.transaction(() => {
    // Upsert tour — re-seeds overwrite cleanly.
    db.prepare('DELETE FROM narration_segments WHERE tour_id = ?').run(tourId);
    db.prepare('DELETE FROM tour_stops WHERE tour_id = ?').run(tourId);
    db.prepare('DELETE FROM tours WHERE id = ?').run(tourId);

    const shareId = tourId.slice(-10);
    db.prepare(`
      INSERT INTO tours (
        id, user_id, title, description, location_query,
        center_lat, center_lng, duration_minutes, themes, language,
        status, transport_mode, total_distance_km, total_duration_minutes,
        story_arc_summary, share_id, is_public, is_featured, metro_area,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'ready', ?, NULL, ?, ?, ?, 1, 1, ?, datetime('now'), datetime('now'))
    `).run(
      tourId, FEATURED_OWNER, content.title, content.description, `${METRO_MIAMI}, FL`,
      content.stops[0].latitude, content.stops[0].longitude,
      tour.durationMinutes, JSON.stringify(['history', 'scenic', 'culture']), language,
      tour.transportMode === 'car' ? 'car' : 'walk',
      totalStayMinutes, content.story_arc_summary, shareId, METRO_MIAMI,
    );

    const insertStop = db.prepare(`
      INSERT INTO tour_stops (
        id, tour_id, sequence_order, name, description, category,
        latitude, longitude, recommended_stay_minutes, is_optional,
        approach_narration, at_stop_narration, departure_narration, photo_url
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    const stopIds: string[] = [];
    for (let i = 0; i < content.stops.length; i++) {
      const s = content.stops[i];
      const stopId = `featured-${tour.key}-stop-${i}`;
      stopIds.push(stopId);
      insertStop.run(
        stopId, tourId, i, s.name, s.description, s.category,
        s.latitude, s.longitude, s.recommended_stay_minutes,
        s.is_optional ? 1 : 0,
        s.approach_narration, s.at_stop_narration, s.departure_narration,
        photoUrls[i] ?? null,
      );
    }

    const insertSeg = db.prepare(`
      INSERT INTO narration_segments (
        id, tour_id, from_stop_id, to_stop_id, segment_type,
        sequence_order, narration_text, content_hash,
        estimated_duration_seconds, trigger_lat, trigger_lng,
        trigger_radius_meters, language
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 50, ?)
    `);

    let order = 0;
    let totalChars = 0;
    const makeSegment = (
      type: string,
      fromStopId: string | null,
      toStopId: string | null,
      text: string,
      lat: number,
      lng: number,
    ): void => {
      const wpm = 2.5;
      const words = text.split(/\s+/).length;
      const duration = Math.ceil(words / wpm);
      const segId = newId();
      const hash = hashContent(text, language, voice);
      insertSeg.run(
        segId, tourId, fromStopId, toStopId, type,
        order++, text, hash, duration, lat, lng, language,
      );
      totalChars += text.length;
    };

    makeSegment('intro', null, stopIds[0], content.intro_narration, content.stops[0].latitude, content.stops[0].longitude);
    for (let i = 0; i < content.stops.length; i++) {
      const s = content.stops[i];
      const sid = stopIds[i];
      makeSegment('approach', i > 0 ? stopIds[i - 1] : null, sid, s.approach_narration, s.latitude, s.longitude);
      makeSegment('at_stop', null, sid, s.at_stop_narration, s.latitude, s.longitude);
      makeSegment('departure', sid, i < content.stops.length - 1 ? stopIds[i + 1] : null, s.departure_narration, s.latitude, s.longitude);

      if (i < content.stops.length - 1 && content.between_stop_narrations[i]) {
        const midLat = (s.latitude + content.stops[i + 1].latitude) / 2;
        const midLng = (s.longitude + content.stops[i + 1].longitude) / 2;
        makeSegment('between_stops', sid, stopIds[i + 1], content.between_stop_narrations[i], midLat, midLng);
      }
    }
    const lastStop = content.stops[content.stops.length - 1];
    makeSegment('outro', stopIds[stopIds.length - 1], null, content.outro_narration, lastStop.latitude, lastStop.longitude);

    return { tourId, stopIds, segmentCount: order, totalNarrationChars: totalChars };
  });

  return persist();
}

async function fetchPhotos(stops: CuratedStop[]): Promise<Array<string | null>> {
  if (process.env.SKIP_PHOTOS === '1') return stops.map(() => null);
  const results: Array<string | null> = [];
  for (const s of stops) {
    try {
      const hit = await resolvePlacePhotoByName(s.name, s.latitude, s.longitude, 1200);
      results.push(hit?.url ?? null);
    } catch (err) {
      console.warn(`  [photo] ${s.name} failed:`, err instanceof Error ? err.message : err);
      results.push(null);
    }
  }
  return results;
}

interface CostSummary {
  key: string;
  title: string;
  stopCount: number;
  segmentCount: number;
  narrationChars: number;
  geminiCalls: number;
  geminiPromptTokens: number;
  geminiCandidatesTokens: number;
  geminiTotalTokens: number;
  photosFetched: number;
  ttsCharsSynthesized: number;
  ttsSegmentsGenerated: number;
  ttsAudioSeconds: number;
  sampleAudioUrls: string[];
}

async function generateAudio(tourId: string): Promise<{ segments: number; chars: number; seconds: number; samples: string[] }> {
  if (process.env.SKIP_TTS === '1') {
    return { segments: 0, chars: 0, seconds: 0, samples: [] };
  }
  const db = getDb();
  type Row = { id: string; narration_text: string; content_hash: string; language: string; segment_type: string; sequence_order: number };
  const rows = db.prepare(`
    SELECT id, narration_text, content_hash, language, segment_type, sequence_order
    FROM narration_segments WHERE tour_id = ? ORDER BY sequence_order
  `).all(tourId) as Row[];

  const totalChars = rows.reduce((s, r) => s + r.narration_text.length, 0);

  // Kokoro batch supports up to ~50 segments in 5 min timeout; split if larger.
  const CHUNK = 15;
  const samples: string[] = [];
  let totalSeconds = 0;

  for (let i = 0; i < rows.length; i += CHUNK) {
    const batch = rows.slice(i, i + CHUNK).map((r) => ({
      id: r.id,
      narration_text: r.narration_text,
      content_hash: r.content_hash,
      language: r.language,
    }));
    const res = await synthesizeWithKokoro(batch, 'af_bella', 0.95);
    totalSeconds += res.total_duration_seconds;
    // Pick 1-2 samples from each batch — prefer intro, at_stop types.
    for (const s of res.segments) {
      if (samples.length < 5 && !samples.includes(s.audio_url)) {
        samples.push(s.audio_url);
      }
    }
  }

  return { segments: rows.length, chars: totalChars, seconds: Math.round(totalSeconds), samples };
}

async function runPilot(): Promise<void> {
  runMigrations();
  ensureSystemUser();

  const dryRun = process.env.DRY_RUN === '1';
  const summaries: CostSummary[] = [];

  for (const tour of miamiTours) {
    console.log(`\n━━━ ${tour.key}: "${tour.tourTitleHint}" (${tour.stops.length} stops) ━━━`);

    const t0 = Date.now();
    const req: FeaturedTourRequest = {
      metroName: METRO_MIAMI,
      tourTitleHint: tour.tourTitleHint,
      transportMode: tour.transportMode,
      durationMinutes: tour.durationMinutes,
      narrativeTheme: tour.narrativeTheme,
      stops: tour.stops,
    };
    const result = await generateFeaturedTourContent(req);
    const t1 = Date.now();
    console.log(`  Gemini: ${result.callCount} calls, ${result.usage.totalTokens} tokens, ${t1 - t0}ms`);

    if (dryRun) {
      summaries.push({
        key: tour.key, title: result.content.title,
        stopCount: tour.stops.length,
        segmentCount: 0, narrationChars: 0,
        geminiCalls: result.callCount,
        geminiPromptTokens: result.usage.promptTokens,
        geminiCandidatesTokens: result.usage.candidatesTokens,
        geminiTotalTokens: result.usage.totalTokens,
        photosFetched: 0,
        ttsCharsSynthesized: 0, ttsSegmentsGenerated: 0,
        ttsAudioSeconds: 0, sampleAudioUrls: [],
      });
      continue;
    }

    const photos = await fetchPhotos(tour.stops);
    const photosFetched = photos.filter((p) => p !== null).length;
    console.log(`  Photos: ${photosFetched}/${tour.stops.length}`);

    const persisted = persistTour(tour, result.content, photos);
    console.log(`  DB: wrote ${persisted.segmentCount} segments under tour ${persisted.tourId}`);

    const audio = await generateAudio(persisted.tourId);
    console.log(`  Audio: ${audio.segments} segments, ${audio.chars} chars, ~${audio.seconds}s`);

    summaries.push({
      key: tour.key, title: result.content.title,
      stopCount: tour.stops.length,
      segmentCount: persisted.segmentCount,
      narrationChars: persisted.totalNarrationChars,
      geminiCalls: result.callCount,
      geminiPromptTokens: result.usage.promptTokens,
      geminiCandidatesTokens: result.usage.candidatesTokens,
      geminiTotalTokens: result.usage.totalTokens,
      photosFetched,
      ttsCharsSynthesized: audio.chars,
      ttsSegmentsGenerated: audio.segments,
      ttsAudioSeconds: audio.seconds,
      sampleAudioUrls: audio.samples,
    });
  }

  // ── Report ──
  console.log('\n\n============ MIAMI PILOT COST SUMMARY ============');
  for (const s of summaries) {
    console.log(`\nTour: ${s.title} (${s.key})`);
    console.log(`  Stops: ${s.stopCount}   Segments: ${s.segmentCount}   Chars: ${s.narrationChars}`);
    console.log(`  Gemini: ${s.geminiCalls} calls | in ${s.geminiPromptTokens} | out ${s.geminiCandidatesTokens} | total ${s.geminiTotalTokens}`);
    console.log(`  Photos: ${s.photosFetched}   TTS: ${s.ttsSegmentsGenerated} seg / ${s.ttsCharsSynthesized} chars / ~${s.ttsAudioSeconds}s`);
    console.log('  Samples:');
    for (const u of s.sampleAudioUrls) console.log(`    ${u}`);
  }

  const totals = summaries.reduce((acc, s) => ({
    geminiTokens: acc.geminiTokens + s.geminiTotalTokens,
    geminiPromptTokens: acc.geminiPromptTokens + s.geminiPromptTokens,
    geminiCandidatesTokens: acc.geminiCandidatesTokens + s.geminiCandidatesTokens,
    ttsChars: acc.ttsChars + s.ttsCharsSynthesized,
    photos: acc.photos + s.photosFetched,
  }), { geminiTokens: 0, geminiPromptTokens: 0, geminiCandidatesTokens: 0, ttsChars: 0, photos: 0 });

  // Gemini 2.5 Flash pricing (Apr 2025): $0.30 / 1M input, $2.50 / 1M output.
  const costGemini = (totals.geminiPromptTokens / 1e6) * 0.30 + (totals.geminiCandidatesTokens / 1e6) * 2.50;
  // Kokoro on Cloud Run GPU: approximate at ~$0.00024/sec audio produced (L4).
  // Very rough; we will true this up with actual gcloud billing export.
  const audioSeconds = summaries.reduce((s, x) => s + x.ttsAudioSeconds, 0);
  const costKokoro = audioSeconds * 0.00024;
  // Places Photos: $7 per 1000 textsearch + $7 per 1000 details + $7 per 1000 photo lookups.
  const costPlaces = (totals.photos * 3 * 0.007);

  console.log(`\n── Per-metro totals ──`);
  console.log(`  Gemini tokens: ${totals.geminiTokens} (in ${totals.geminiPromptTokens} / out ${totals.geminiCandidatesTokens})  →  ~$${costGemini.toFixed(3)}`);
  console.log(`  Kokoro TTS seconds: ${audioSeconds}  →  ~$${costKokoro.toFixed(3)}`);
  console.log(`  Places photo fetches: ${totals.photos} (×3 API calls each)  →  ~$${costPlaces.toFixed(3)}`);
  console.log(`  TOTAL EST: ~$${(costGemini + costKokoro + costPlaces).toFixed(3)} per Miami pair`);
  console.log(`  Extrapolated to 50 metros: ~$${((costGemini + costKokoro + costPlaces) * 50).toFixed(2)}`);
  console.log('==================================================\n');
}

runPilot()
  .then(() => closeDb())
  .catch((err) => {
    console.error('Pilot failed:', err);
    closeDb();
    process.exit(1);
  });
