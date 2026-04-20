// Top-level orchestrator: takes a tour + its stops, runs every scorer, and
// returns the complete score bundle ready for persistence and ranking.
//
// Call path:
//   scoreTour(tour, opts)
//     ├── per stop:
//     │     scoreStopQuality() → iconicity + scenic + story (LLM, cached)
//     │     + rule-based scorers (friction, route_fit, time_of_day, dwell, family)
//     ├── scoreTourQuality() → iconic_value, narrative_flow, scenic_payoff (LLM)
//     ├── rule-based tour scorers → geographic_coherence, time_realism,
//     │                             variety_balance, practical_usability
//     ├── assemble TourAbsoluteScore + compute composite
//     └── score intents (if provided) → TourIntentFitScore[]

import type {
  StopScore,
  TourAbsoluteScore,
  TourIntentFitScore,
  TourFinalScore,
  TourAbsoluteWeights,
  ProductMode,
  TourIntent,
} from './types.js';
import {
  DEFAULT_ABSOLUTE_WEIGHTS,
} from './types.js';
import {
  computeStopComposite,
  computeAbsoluteComposite,
  scoreFriction, scoreRouteFit, scoreTimeOfDayFit, scoreDwellEfficiency,
  scoreAccessibility, scoreFamilyFit,
  scoreGeographicCoherence, scoreTimeRealism, scoreVarietyBalance, scorePracticalUsability,
  type ScorableStop, type ScorableTour,
} from './rule-based.js';
import { scoreStopQuality, scoreTourQuality } from './llm-based.js';

export interface ScoreTourOptions {
  cityHint?: string;
  intents?: TourIntent[];
  productMode?: ProductMode;
  absoluteWeights?: TourAbsoluteWeights;
  blendConfig?: { absolute_weight: number; intent_weight: number };
}

export interface ScoreTourResult {
  stopScores: StopScore[];
  tourAbsolute: TourAbsoluteScore;
  intentFits: TourIntentFitScore[];
  finalScore: TourFinalScore;
}

/**
 * Score a full tour end-to-end. Returns every level of the score
 * hierarchy so callers can persist each table independently.
 */
export async function scoreTour(
  tour: ScorableTour,
  opts: ScoreTourOptions = {},
): Promise<ScoreTourResult> {
  const {
    cityHint,
    intents = [],
    productMode = 'hybrid_default',
    absoluteWeights = DEFAULT_ABSOLUTE_WEIGHTS,
    blendConfig = { absolute_weight: 0.6, intent_weight: 0.4 },
  } = opts;

  // 1. LLM-backed quality scoring for each stop (parallel, cached).
  const stopQualities = await Promise.all(
    tour.stops.map(async (stop) => ({
      stop,
      quality: await scoreStopQuality(stop, cityHint),
    })),
  );

  // 2. Assemble full per-stop scores (rule-based + LLM).
  const stopScores: StopScore[] = tour.stops.map((stop, i) => {
    const q = stopQualities[i].quality;
    const dims = {
      iconicity: q.iconicity,
      scenic_payoff: q.scenic_payoff,
      story_richness: q.story_richness,
      dwell_efficiency: scoreDwellEfficiency(stop),
      friction: scoreFriction(stop),
      route_fit: scoreRouteFit(stop, tour, i),
      time_of_day_fit: scoreTimeOfDayFit(stop, tour),
      family_fit: scoreFamilyFit(stop),
      accessibility: scoreAccessibility(stop),
      wow_per_minute: Math.min(10,
        (q.iconicity * 0.4 + q.scenic_payoff * 0.3 + q.story_richness * 0.2)
        + (5 / Math.max(1, stop.recommended_stay_minutes)) * 0.1),
    };
    return {
      stop_id: stop.id,
      sequence_order: stop.sequence_order,
      ...dims,
      composite: computeStopComposite(dims),
      rationale: q.rationale,
    };
  });

  // 3. Tour-level LLM scoring (iconic_value, narrative_flow, scenic_payoff roll-ups).
  const tourQ = await scoreTourQuality(tour, stopQualities);

  // 4. Tour-level rule-based scoring.
  const absDims = {
    iconic_value: tourQ.iconic_value,
    geographic_coherence: scoreGeographicCoherence(tour),
    time_realism: scoreTimeRealism(tour),
    narrative_flow: tourQ.narrative_flow,
    scenic_payoff: tourQ.scenic_payoff,
    variety_balance: scoreVarietyBalance(tour),
    practical_usability: scorePracticalUsability(tour),
  };
  const composite = computeAbsoluteComposite(absDims, absoluteWeights);

  const tourAbsolute: TourAbsoluteScore = {
    ...absDims,
    composite,
    weights: absoluteWeights,
    rationale: tourQ.rationale,
  };

  // 5. Intent-fit scoring (if user supplied intents).
  const intentFits: TourIntentFitScore[] = intents.map((intent) =>
    scoreIntentFit(intent, tourAbsolute, stopScores, stopQualities.map((s) => s.stop)),
  );

  // 6. Final blended score.
  const finalScore = blendFinalScore(
    tour.id, tourAbsolute, intentFits, productMode, blendConfig,
  );

  return { stopScores, tourAbsolute, intentFits, finalScore };
}

// ── Intent-fit scoring ───────────────────────────────────────────────────────

/**
 * Compute Layer B intent fit. Each intent has its own mapping from the
 * tour's Layer A dimensions to a fit score. Design goal: a "hidden_gems"
 * tour that skips the 3 most iconic stops should score HIGHER on
 * hidden_gems intent, even though its iconic_value is low.
 */
function scoreIntentFit(
  intent: TourIntent,
  absolute: TourAbsoluteScore,
  stopScores: StopScore[],
  stops: ScorableStop[],
): TourIntentFitScore {
  const contributing: TourIntentFitScore['contributing_dimensions'] = [];
  const rationale: Record<string, string> = {};
  let fit: number;

  switch (intent) {
    case 'first_time_highlights':
      // Rewards high iconic_value, high narrative_flow, high variety.
      fit = clamp(
        absolute.iconic_value * 0.45 +
        absolute.narrative_flow * 0.25 +
        absolute.variety_balance * 0.15 +
        absolute.scenic_payoff * 0.15,
      0, 10) * 10;
      contributing.push(
        { dimension: 'iconic_value', weight: 0.45, effect: 'positive' },
        { dimension: 'narrative_flow', weight: 0.25, effect: 'positive' },
      );
      break;

    case 'hidden_gems': {
      // KEY CASE: invert iconicity — hidden gems PUNISH famous stops.
      // But still demand narrative cohesion and scenic payoff.
      const avgIconicity = mean(stopScores.map((s) => s.iconicity));
      const inverted = 10 - avgIconicity;
      fit = clamp(
        inverted * 0.4 +
        absolute.narrative_flow * 0.2 +
        absolute.scenic_payoff * 0.2 +
        mean(stopScores.map((s) => s.story_richness)) * 0.2,
      0, 10) * 10;
      contributing.push(
        { dimension: 'iconicity (inverted)', weight: 0.4, effect: 'positive' },
        { dimension: 'story_richness', weight: 0.2, effect: 'positive' },
      );
      rationale.iconicity_inverted = `mean stop iconicity ${avgIconicity.toFixed(1)} → inverted ${inverted.toFixed(1)}`;
      break;
    }

    case 'sunset':
    case 'romantic': {
      // Time-of-day match is paramount.
      const tofAvg = mean(stopScores.map((s) => s.time_of_day_fit));
      fit = clamp(
        tofAvg * 0.5 +
        absolute.scenic_payoff * 0.35 +
        absolute.narrative_flow * 0.15,
      0, 10) * 10;
      contributing.push(
        { dimension: 'time_of_day_fit', weight: 0.5, effect: 'positive' },
        { dimension: 'scenic_payoff', weight: 0.35, effect: 'positive' },
      );
      break;
    }

    case 'family_kids': {
      const familyAvg = mean(stopScores.map((s) => s.family_fit));
      fit = clamp(
        familyAvg * 0.5 +
        absolute.variety_balance * 0.2 +
        absolute.practical_usability * 0.2 +
        absolute.iconic_value * 0.1,
      0, 10) * 10;
      contributing.push(
        { dimension: 'family_fit', weight: 0.5, effect: 'positive' },
        { dimension: 'practical_usability', weight: 0.2, effect: 'positive' },
      );
      break;
    }

    case 'architecture':
    case 'history': {
      const storyAvg = mean(stopScores.map((s) => s.story_richness));
      fit = clamp(
        storyAvg * 0.5 +
        absolute.narrative_flow * 0.3 +
        absolute.iconic_value * 0.2,
      0, 10) * 10;
      contributing.push(
        { dimension: 'story_richness', weight: 0.5, effect: 'positive' },
        { dimension: 'narrative_flow', weight: 0.3, effect: 'positive' },
      );
      break;
    }

    case 'minimal_walking': {
      const frictionAvg = mean(stopScores.map((s) => s.friction));
      fit = clamp(
        frictionAvg * 0.6 +
        absolute.practical_usability * 0.25 +
        absolute.iconic_value * 0.15,
      0, 10) * 10;
      contributing.push(
        { dimension: 'friction', weight: 0.6, effect: 'positive' },
      );
      break;
    }

    case 'quick_two_hours': {
      // Dwell efficiency + time realism lead.
      const dwellAvg = mean(stopScores.map((s) => s.dwell_efficiency));
      fit = clamp(
        dwellAvg * 0.4 +
        absolute.time_realism * 0.3 +
        absolute.iconic_value * 0.2 +
        absolute.geographic_coherence * 0.1,
      0, 10) * 10;
      contributing.push(
        { dimension: 'dwell_efficiency', weight: 0.4, effect: 'positive' },
        { dimension: 'time_realism', weight: 0.3, effect: 'positive' },
      );
      break;
    }

    case 'food':
    case 'local_authenticity': {
      // Favor non-icon stops, mid-scenic, food category density.
      const foodStops = stops.filter((s) => s.category === 'food' || s.category === 'neighborhood').length;
      const foodDensity = foodStops / Math.max(1, stops.length);
      fit = clamp(
        foodDensity * 7 +
        (10 - absolute.iconic_value) * 0.2 +
        absolute.narrative_flow * 0.2,
      0, 10) * 10;
      contributing.push(
        { dimension: 'food/neighborhood stop density', weight: 0.6, effect: 'positive' },
      );
      break;
    }

    case 'scenic_drive': {
      fit = clamp(
        absolute.scenic_payoff * 0.55 +
        absolute.geographic_coherence * 0.25 +
        absolute.narrative_flow * 0.2,
      0, 10) * 10;
      contributing.push(
        { dimension: 'scenic_payoff', weight: 0.55, effect: 'positive' },
      );
      break;
    }

    default:
      // Unknown intent — fall back to absolute composite so we never
      // punish a novel intent tag more than necessary.
      fit = absolute.composite;
      rationale.unknown_intent = `Intent '${intent}' not specifically modelled; using absolute composite`;
  }

  return {
    intent,
    fit_score: fit,
    contributing_dimensions: contributing,
    rationale,
  };
}

// ── Final blend ──────────────────────────────────────────────────────────────

function blendFinalScore(
  tourId: string,
  absolute: TourAbsoluteScore,
  intentFits: TourIntentFitScore[],
  productMode: ProductMode,
  blendConfig: { absolute_weight: number; intent_weight: number },
): TourFinalScore {
  let final: number;

  if (intentFits.length === 0 || productMode === 'pure_curation') {
    // No intents → absolute IS the final score.
    final = absolute.composite;
  } else if (productMode === 'pure_custom') {
    // Intent dominates: mean intent fit with a small absolute-quality floor.
    const intentMean = mean(intentFits.map((i) => i.fit_score));
    final = intentMean * 0.8 + absolute.composite * 0.2;
  } else if (productMode === 'calibration') {
    // Calibration mode uses absolute only — we're tuning weights.
    final = absolute.composite;
  } else {
    // hybrid_default: blend per config (default 0.6 abs, 0.4 intent).
    const intentMean = mean(intentFits.map((i) => i.fit_score));
    final = absolute.composite * blendConfig.absolute_weight
          + intentMean * blendConfig.intent_weight;
  }

  return {
    tour_id: tourId,
    final_score: Math.max(0, Math.min(100, final)),
    absolute,
    intent_fits: intentFits,
    product_mode: productMode,
    blend_config: blendConfig,
    scored_at: new Date().toISOString(),
  };
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function clamp(n: number, lo: number, hi: number): number {
  if (Number.isNaN(n)) return lo;
  return Math.max(lo, Math.min(hi, n));
}
function mean(xs: number[]): number {
  if (xs.length === 0) return 0;
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}
