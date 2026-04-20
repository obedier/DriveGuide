// Writes and reads scoring records against the tables added in
// migrations/008_tour_scores.sql. Append-only — every re-score writes
// new rows; latest-read helpers use ORDER BY scored_at DESC LIMIT 1.
//
// Shape mirrors tour-scoring-spec.md §6. Consumers of the API get the
// "latest" view composed from these three tables plus the weights.

import { getDb } from '../../lib/db.js';
import { newId } from '../../lib/id.js';
import type {
  StopScore,
  TourAbsoluteScore,
  TourIntentFitScore,
  TourFinalScore,
} from './types.js';

// ── Write path ───────────────────────────────────────────────────────────────

/**
 * Persist a full score bundle. Called by the generator after it scores a
 * newly-built tour. One transaction so all three levels commit together.
 */
export function persistScoreBundle(params: {
  tourId: string;
  stopScores: StopScore[];
  tourAbsolute: TourAbsoluteScore;
  intentFits: TourIntentFitScore[];
}): void {
  const db = getDb();
  const { tourId, stopScores, tourAbsolute, intentFits } = params;

  const insertStop = db.prepare(`
    INSERT INTO stop_scores (
      id, tour_id, stop_id, sequence_order,
      iconicity, scenic_payoff, story_richness, dwell_efficiency,
      friction, route_fit, time_of_day_fit, family_fit, accessibility,
      wow_per_minute, composite, rationale_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const insertAbsolute = db.prepare(`
    INSERT INTO tour_absolute_scores (
      id, tour_id, iconic_value, geographic_coherence, time_realism,
      narrative_flow, scenic_payoff, variety_balance, practical_usability,
      composite, weights_json, rationale_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const insertIntent = db.prepare(`
    INSERT INTO tour_intent_fit_scores (
      id, tour_id, intent, fit_score,
      contributing_dimensions_json, rationale_json
    ) VALUES (?, ?, ?, ?, ?, ?)
  `);

  db.transaction(() => {
    for (const s of stopScores) {
      insertStop.run(
        newId(), tourId, s.stop_id, s.sequence_order,
        s.iconicity, s.scenic_payoff, s.story_richness, s.dwell_efficiency,
        s.friction, s.route_fit, s.time_of_day_fit, s.family_fit, s.accessibility,
        s.wow_per_minute, s.composite,
        s.rationale ? JSON.stringify(s.rationale) : null,
      );
    }
    insertAbsolute.run(
      newId(), tourId,
      tourAbsolute.iconic_value, tourAbsolute.geographic_coherence,
      tourAbsolute.time_realism, tourAbsolute.narrative_flow,
      tourAbsolute.scenic_payoff, tourAbsolute.variety_balance,
      tourAbsolute.practical_usability,
      tourAbsolute.composite,
      JSON.stringify(tourAbsolute.weights),
      tourAbsolute.rationale ? JSON.stringify(tourAbsolute.rationale) : null,
    );
    for (const i of intentFits) {
      insertIntent.run(
        newId(), tourId, i.intent, i.fit_score,
        i.contributing_dimensions ? JSON.stringify(i.contributing_dimensions) : null,
        i.rationale ? JSON.stringify(i.rationale) : null,
      );
    }
  })();
}

// ── Read path ────────────────────────────────────────────────────────────────

/**
 * Return the latest persisted score bundle for a tour, or null if never
 * scored. The API route and the iOS client use this to render the score
 * chip and explanation.
 */
export function loadLatestScoreBundle(tourId: string): {
  stopScores: StopScore[];
  tourAbsolute: TourAbsoluteScore;
  intentFits: TourIntentFitScore[];
} | null {
  const db = getDb();

  // Latest absolute score row — acts as the anchor "scored_at" for this
  // bundle. We read stop + intent scores at or before that timestamp.
  const absRow = db.prepare(`
    SELECT * FROM tour_absolute_scores
    WHERE tour_id = ?
    ORDER BY scored_at DESC
    LIMIT 1
  `).get(tourId) as AbsoluteRow | undefined;
  if (!absRow) return null;

  // Latest row per stop_id. We read every row DESC and keep the first we
  // see per stop — GROUP BY's row-selection semantics are fuzzy across
  // SQLite versions, so we do the dedup explicitly.
  const latestPerStop = new Map<string, StopRow>();
  for (const r of db.prepare(`
    SELECT * FROM stop_scores
    WHERE tour_id = ?
    ORDER BY scored_at DESC
  `).all(tourId) as StopRow[]) {
    if (!latestPerStop.has(r.stop_id)) latestPerStop.set(r.stop_id, r);
  }

  const stopScores: StopScore[] = Array.from(latestPerStop.values())
    .sort((a, b) => a.sequence_order - b.sequence_order)
    .map(stopRowToScore);

  const intentRows = db.prepare(`
    SELECT * FROM tour_intent_fit_scores
    WHERE tour_id = ?
    ORDER BY scored_at DESC
  `).all(tourId) as IntentRow[];
  // Latest per intent.
  const latestPerIntent = new Map<string, IntentRow>();
  for (const r of intentRows) {
    if (!latestPerIntent.has(r.intent)) latestPerIntent.set(r.intent, r);
  }
  const intentFits: TourIntentFitScore[] = Array.from(latestPerIntent.values()).map(intentRowToScore);

  return {
    stopScores,
    tourAbsolute: absoluteRowToScore(absRow),
    intentFits,
  };
}

/**
 * Convenience for the featured-tour seed gate: returns just the latest
 * absolute composite (0-100). Null if never scored.
 */
export function loadLatestAbsoluteComposite(tourId: string): number | null {
  const db = getDb();
  const row = db.prepare(`
    SELECT composite FROM tour_absolute_scores
    WHERE tour_id = ?
    ORDER BY scored_at DESC
    LIMIT 1
  `).get(tourId) as { composite: number } | undefined;
  return row?.composite ?? null;
}

// ── Row types ────────────────────────────────────────────────────────────────

interface StopRow {
  id: string; tour_id: string; stop_id: string; sequence_order: number;
  iconicity: number; scenic_payoff: number; story_richness: number;
  dwell_efficiency: number; friction: number; route_fit: number;
  time_of_day_fit: number; family_fit: number; accessibility: number;
  wow_per_minute: number; composite: number;
  rationale_json: string | null; scored_at: string;
}

interface AbsoluteRow {
  id: string; tour_id: string;
  iconic_value: number; geographic_coherence: number; time_realism: number;
  narrative_flow: number; scenic_payoff: number; variety_balance: number;
  practical_usability: number; composite: number;
  weights_json: string; rationale_json: string | null; scored_at: string;
}

interface IntentRow {
  id: string; tour_id: string; intent: string; fit_score: number;
  contributing_dimensions_json: string | null;
  rationale_json: string | null; scored_at: string;
}

function stopRowToScore(r: StopRow): StopScore {
  return {
    stop_id: r.stop_id, sequence_order: r.sequence_order,
    iconicity: r.iconicity, scenic_payoff: r.scenic_payoff,
    story_richness: r.story_richness, dwell_efficiency: r.dwell_efficiency,
    friction: r.friction, route_fit: r.route_fit,
    time_of_day_fit: r.time_of_day_fit, family_fit: r.family_fit,
    accessibility: r.accessibility, wow_per_minute: r.wow_per_minute,
    composite: r.composite,
    rationale: r.rationale_json ? JSON.parse(r.rationale_json) : undefined,
  };
}

function absoluteRowToScore(r: AbsoluteRow): TourAbsoluteScore {
  return {
    iconic_value: r.iconic_value, geographic_coherence: r.geographic_coherence,
    time_realism: r.time_realism, narrative_flow: r.narrative_flow,
    scenic_payoff: r.scenic_payoff, variety_balance: r.variety_balance,
    practical_usability: r.practical_usability,
    composite: r.composite,
    weights: JSON.parse(r.weights_json),
    rationale: r.rationale_json ? JSON.parse(r.rationale_json) : undefined,
  };
}

function intentRowToScore(r: IntentRow): TourIntentFitScore {
  return {
    intent: r.intent, fit_score: r.fit_score,
    contributing_dimensions: r.contributing_dimensions_json
      ? JSON.parse(r.contributing_dimensions_json) : undefined,
    rationale: r.rationale_json ? JSON.parse(r.rationale_json) : undefined,
  };
}

// ── Final score blend helper (for API consumers) ─────────────────────────────

export function buildFinalScoreFromBundle(
  tourId: string,
  bundle: NonNullable<ReturnType<typeof loadLatestScoreBundle>>,
  productMode: TourFinalScore['product_mode'] = 'hybrid_default',
  blendConfig: TourFinalScore['blend_config'] = { absolute_weight: 0.6, intent_weight: 0.4 },
): TourFinalScore {
  const intentMean = bundle.intentFits.length === 0
    ? 0
    : bundle.intentFits.reduce((s, i) => s + i.fit_score, 0) / bundle.intentFits.length;

  let final: number;
  if (bundle.intentFits.length === 0 || productMode === 'pure_curation' || productMode === 'calibration') {
    final = bundle.tourAbsolute.composite;
  } else if (productMode === 'pure_custom') {
    final = intentMean * 0.8 + bundle.tourAbsolute.composite * 0.2;
  } else {
    final = bundle.tourAbsolute.composite * blendConfig.absolute_weight
          + intentMean * blendConfig.intent_weight;
  }

  return {
    tour_id: tourId,
    final_score: Math.max(0, Math.min(100, final)),
    absolute: bundle.tourAbsolute,
    intent_fits: bundle.intentFits,
    product_mode: productMode,
    blend_config: blendConfig,
    scored_at: new Date().toISOString(),
  };
}
