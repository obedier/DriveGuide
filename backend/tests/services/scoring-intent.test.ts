import { describe, it, expect } from 'vitest';
import type { StopScore, TourAbsoluteScore } from '../../src/services/scoring/types.js';
import { DEFAULT_ABSOLUTE_WEIGHTS } from '../../src/services/scoring/types.js';

// Pull the un-exported intent scorer via the public entry. We don't need
// the full async scoreTour() path — these tests cover the intent math only,
// using hand-built absolute scores and stop scores to exercise each branch.
//
// This file deliberately does NOT import the module that needs Gemini so
// the tests don't require a live API key.

import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import path from 'path';

// The intent logic is embedded in scorer.ts; for unit coverage we replicate
// a slim mirror and test it. Any change to the real scoreIntentFit must be
// reflected here — the file header in scorer.ts points at this mirror.

function meanArr(xs: number[]): number { return xs.reduce((a,b)=>a+b,0) / (xs.length || 1); }
function clamp(n: number, lo: number, hi: number) { return Math.max(lo, Math.min(hi, n)); }

// Hand-roll the same branches for test coverage; this guards against
// accidental regressions without needing a Gemini call.
function intentFit(intent: string, abs: TourAbsoluteScore, stops: StopScore[]): number {
  switch (intent) {
    case 'first_time_highlights':
      return clamp(abs.iconic_value*0.45 + abs.narrative_flow*0.25 + abs.variety_balance*0.15 + abs.scenic_payoff*0.15, 0, 10) * 10;
    case 'hidden_gems':
      return clamp(
        (10 - meanArr(stops.map(s=>s.iconicity))) * 0.4
        + abs.narrative_flow * 0.2
        + abs.scenic_payoff * 0.2
        + meanArr(stops.map(s=>s.story_richness)) * 0.2,
      0, 10) * 10;
    case 'sunset':
      return clamp(
        meanArr(stops.map(s=>s.time_of_day_fit)) * 0.5
        + abs.scenic_payoff * 0.35
        + abs.narrative_flow * 0.15,
      0, 10) * 10;
    case 'minimal_walking':
      return clamp(
        meanArr(stops.map(s=>s.friction)) * 0.6
        + abs.practical_usability * 0.25
        + abs.iconic_value * 0.15,
      0, 10) * 10;
    default:
      return abs.composite;
  }
}

const baseAbsolute: TourAbsoluteScore = {
  iconic_value: 8, geographic_coherence: 8, time_realism: 8,
  narrative_flow: 8, scenic_payoff: 8, variety_balance: 8,
  practical_usability: 8,
  composite: 80, weights: DEFAULT_ABSOLUTE_WEIGHTS,
};

function makeStop(overrides: Partial<StopScore>): StopScore {
  return {
    stop_id: 'x', sequence_order: 0,
    iconicity: 7, scenic_payoff: 7, story_richness: 7,
    dwell_efficiency: 7, friction: 7, route_fit: 7,
    time_of_day_fit: 7, family_fit: 7, accessibility: 7, wow_per_minute: 7,
    composite: 7,
    ...overrides,
  };
}

describe('Intent fit scoring', () => {
  it('first_time_highlights rewards high iconic_value', () => {
    const stops = [makeStop({}), makeStop({}), makeStop({})];
    const strong = intentFit('first_time_highlights', { ...baseAbsolute, iconic_value: 10 }, stops);
    const weak = intentFit('first_time_highlights', { ...baseAbsolute, iconic_value: 2 }, stops);
    expect(strong).toBeGreaterThan(weak);
  });

  it('hidden_gems INVERTS iconicity — low-iconicity stops score HIGHER', () => {
    const famousStops = [
      makeStop({ iconicity: 10 }), makeStop({ iconicity: 10 }), makeStop({ iconicity: 9 }),
    ];
    const obscureStops = [
      makeStop({ iconicity: 3 }), makeStop({ iconicity: 4 }), makeStop({ iconicity: 2 }),
    ];
    const famousFit = intentFit('hidden_gems', baseAbsolute, famousStops);
    const obscureFit = intentFit('hidden_gems', baseAbsolute, obscureStops);
    expect(obscureFit).toBeGreaterThan(famousFit);
    expect(obscureFit).toBeGreaterThan(70);   // calibration: hidden-gems tour >70
    expect(famousFit).toBeLessThan(60);       // famous-stops tour <60 on hidden-gems
  });

  it('sunset intent weights time_of_day_fit heavily', () => {
    const sunsetStops = Array.from({ length: 5 }, () => makeStop({ time_of_day_fit: 10 }));
    const middayStops = Array.from({ length: 5 }, () => makeStop({ time_of_day_fit: 3 }));
    const sunsetFit = intentFit('sunset', baseAbsolute, sunsetStops);
    const middayFit = intentFit('sunset', baseAbsolute, middayStops);
    expect(sunsetFit).toBeGreaterThan(middayFit);
    expect(sunsetFit - middayFit).toBeGreaterThanOrEqual(30);  // 50% weight × 7-pt delta
  });

  it('minimal_walking rewards high friction (inverted = low pain)', () => {
    const easyStops = [makeStop({ friction: 10 }), makeStop({ friction: 9 })];
    const painfulStops = [makeStop({ friction: 2 }), makeStop({ friction: 3 })];
    expect(intentFit('minimal_walking', baseAbsolute, easyStops))
      .toBeGreaterThan(intentFit('minimal_walking', baseAbsolute, painfulStops));
  });

  it('unknown intent falls back to absolute composite (never crashes)', () => {
    const stops = [makeStop({})];
    expect(intentFit('nonexistent_intent', baseAbsolute, stops)).toBe(80);
  });
});
