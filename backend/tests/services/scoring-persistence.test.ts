import { describe, it, expect, beforeEach } from 'vitest';
import Database from 'better-sqlite3';
import {
  persistScoreBundle,
  loadLatestScoreBundle,
  loadLatestAbsoluteComposite,
  buildFinalScoreFromBundle,
} from '../../src/services/scoring/persistence.js';
import { getDb } from '../../src/lib/db.js';
import { DEFAULT_ABSOLUTE_WEIGHTS } from '../../src/services/scoring/types.js';

// The persistence module reaches into getDb() for the shared connection.
// For these tests we rely on the same in-memory DB the suite sets up.
// If getDb() points at the real file in test env, the append-only writes
// here are still safe — they land on an isolated tour-id namespace.

function setup(): void {
  const db = getDb();
  // Minimal schema so FKs can resolve.
  db.exec(`
    CREATE TABLE IF NOT EXISTS tours (
      id TEXT PRIMARY KEY, title TEXT, description TEXT, user_id TEXT,
      duration_minutes INTEGER, language TEXT, status TEXT,
      transport_mode TEXT, themes TEXT, is_public INTEGER, is_featured INTEGER
    );
    CREATE TABLE IF NOT EXISTS tour_stops (
      id TEXT PRIMARY KEY, tour_id TEXT, sequence_order INTEGER,
      name TEXT, latitude REAL, longitude REAL
    );
  `);
  // Apply the scoring migration if not already.
  const fs = require('fs');
  const path = require('path');
  const migrationPath = path.join(__dirname, '..', '..', 'migrations', '008_tour_scores.sql');
  const sql = fs.readFileSync(migrationPath, 'utf8');
  db.exec(sql);
}

function seedTour(id: string, stopCount: number): void {
  const db = getDb();
  // Use only the columns we're certain exist across the real + minimal
  // test schema; let DEFAULTs fill the rest.
  db.prepare(`INSERT OR REPLACE INTO tours
              (id, title, description, location_query, duration_minutes, language, status, transport_mode, themes)
              VALUES (?, 'T', 'd', 'Miami', 60, 'en', 'ready', 'car', '[]')`).run(id);
  for (let i = 0; i < stopCount; i++) {
    db.prepare(`INSERT OR REPLACE INTO tour_stops (id, tour_id, sequence_order, name, latitude, longitude)
                VALUES (?, ?, ?, ?, ?, ?)`)
      .run(`${id}-s${i}`, id, i, `Stop ${i}`, 25.76, -80.19);
  }
}

function mockBundle(tourId: string, absComposite = 85, stopCount = 3): Parameters<typeof persistScoreBundle>[0] {
  return {
    tourId,
    stopScores: Array.from({ length: stopCount }, (_, i) => ({
      stop_id: `${tourId}-s${i}`, sequence_order: i,
      iconicity: 8, scenic_payoff: 8, story_richness: 8,
      dwell_efficiency: 8, friction: 8, route_fit: 8,
      time_of_day_fit: 8, family_fit: 8, accessibility: 8, wow_per_minute: 8,
      composite: 8,
      rationale: { iconicity: 'landmark' },
    })),
    tourAbsolute: {
      iconic_value: 9, geographic_coherence: 8, time_realism: 9,
      narrative_flow: 8, scenic_payoff: 9, variety_balance: 7,
      practical_usability: 9,
      composite: absComposite,
      weights: DEFAULT_ABSOLUTE_WEIGHTS,
      rationale: { narrative_flow: 'coherent arc' },
    },
    intentFits: [
      {
        intent: 'first_time_highlights', fit_score: 88,
        contributing_dimensions: [{ dimension: 'iconic_value', weight: 0.45, effect: 'positive' }],
      },
    ],
  };
}

describe('scoring persistence', () => {
  beforeEach(() => {
    setup();
    // Wipe score tables between tests so we start clean.
    const db = getDb();
    db.exec(`DELETE FROM stop_scores; DELETE FROM tour_absolute_scores; DELETE FROM tour_intent_fit_scores;`);
  });

  it('persists and reloads a full bundle', () => {
    seedTour('t1', 3);
    persistScoreBundle(mockBundle('t1', 87));

    const loaded = loadLatestScoreBundle('t1');
    expect(loaded).not.toBeNull();
    expect(loaded!.tourAbsolute.composite).toBe(87);
    expect(loaded!.stopScores).toHaveLength(3);
    expect(loaded!.intentFits).toHaveLength(1);
    expect(loaded!.intentFits[0].intent).toBe('first_time_highlights');
  });

  it('returns null for a tour that was never scored', () => {
    expect(loadLatestScoreBundle('never-scored')).toBeNull();
  });

  it('latest-read returns the most recent absolute score when re-scored', () => {
    seedTour('t2', 2);
    persistScoreBundle(mockBundle('t2', 70, 2));
    const db = getDb();
    db.prepare(`UPDATE tour_absolute_scores SET scored_at = datetime('now', '-60 seconds') WHERE tour_id = ?`).run('t2');
    persistScoreBundle(mockBundle('t2', 92, 2));

    const composite = loadLatestAbsoluteComposite('t2');
    expect(composite).toBe(92);
  });

  it('latest-read dedupes stop scores — one row per stop', () => {
    seedTour('t3', 2);
    // Write two rounds back-to-back with explicit increasing scored_at so
    // the Map-based dedup in loadLatestScoreBundle has something
    // deterministic to prefer. datetime('now') is second-precision in
    // SQLite — can't rely on it for two inserts in the same tick.
    const db = getDb();
    const first = mockBundle('t3', 80, 2);
    const second = mockBundle('t3', 82, 2);
    persistScoreBundle(first);
    // Manually bump every row we just inserted backwards by 1 minute so
    // the second round's rows (now()) are strictly newer.
    db.prepare(`UPDATE stop_scores SET scored_at = datetime('now', '-60 seconds') WHERE tour_id = ?`).run('t3');
    db.prepare(`UPDATE tour_absolute_scores SET scored_at = datetime('now', '-60 seconds') WHERE tour_id = ?`).run('t3');
    db.prepare(`UPDATE tour_intent_fit_scores SET scored_at = datetime('now', '-60 seconds') WHERE tour_id = ?`).run('t3');
    persistScoreBundle(second);

    const loaded = loadLatestScoreBundle('t3');
    expect(loaded!.stopScores).toHaveLength(2);
    const ids = loaded!.stopScores.map((s) => s.stop_id);
    expect(new Set(ids).size).toBe(ids.length);
    expect(loaded!.tourAbsolute.composite).toBe(82);
  });

  it('buildFinalScoreFromBundle blends absolute and intent per hybrid_default', () => {
    const bundle = {
      stopScores: [],
      tourAbsolute: mockBundle('x').tourAbsolute,   // composite 85
      intentFits: [{ intent: 'hidden_gems', fit_score: 95 }],
    };
    const final = buildFinalScoreFromBundle('x', bundle, 'hybrid_default');
    // 0.6 * 85 + 0.4 * 95 = 51 + 38 = 89
    expect(final.final_score).toBeCloseTo(89, 1);
  });

  it('pure_custom blend weighs intent 80/20 against absolute', () => {
    const bundle = {
      stopScores: [],
      tourAbsolute: { ...mockBundle('y').tourAbsolute, composite: 60 },
      intentFits: [{ intent: 'hidden_gems', fit_score: 95 }],
    };
    const final = buildFinalScoreFromBundle('y', bundle, 'pure_custom');
    // 0.8 * 95 + 0.2 * 60 = 76 + 12 = 88
    expect(final.final_score).toBeCloseTo(88, 1);
  });

  it('pure_curation and calibration modes use absolute only', () => {
    const bundle = {
      stopScores: [],
      tourAbsolute: { ...mockBundle('z').tourAbsolute, composite: 85 },
      intentFits: [{ intent: 'hidden_gems', fit_score: 20 }],
    };
    expect(buildFinalScoreFromBundle('z', bundle, 'pure_curation').final_score).toBe(85);
    expect(buildFinalScoreFromBundle('z', bundle, 'calibration').final_score).toBe(85);
  });
});
