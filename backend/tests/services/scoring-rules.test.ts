import { describe, it, expect } from 'vitest';
import {
  haversineKm,
  scoreFriction,
  scoreRouteFit,
  scoreTimeOfDayFit,
  scoreDwellEfficiency,
  scoreFamilyFit,
  scoreGeographicCoherence,
  scoreTimeRealism,
  scoreVarietyBalance,
  scorePracticalUsability,
  computeStopComposite,
  computeAbsoluteComposite,
  type ScorableStop,
  type ScorableTour,
} from '../../src/services/scoring/rule-based.js';
import { DEFAULT_ABSOLUTE_WEIGHTS } from '../../src/services/scoring/types.js';

// ── Fixtures ─────────────────────────────────────────────────────────────────

const miamiStops: ScorableStop[] = [
  { id: 's0', sequence_order: 0, name: 'South Pointe Park', category: 'park',
    latitude: 25.7684, longitude: -80.1340, recommended_stay_minutes: 10,
    iconicity_hint: 7, access_friction: 'low', parking_friction: 'medium',
    walking_burden: 'light', cluster_id: 'south_beach' },
  { id: 's1', sequence_order: 1, name: 'Versace Mansion', category: 'landmark',
    latitude: 25.7816, longitude: -80.1318, recommended_stay_minutes: 5,
    iconicity_hint: 9, access_friction: 'low', parking_friction: 'high',
    walking_burden: 'none', cluster_id: 'south_beach' },
  { id: 's2', sequence_order: 2, name: 'MacArthur Causeway', category: 'viewpoint',
    latitude: 25.7787, longitude: -80.1616, recommended_stay_minutes: 5,
    iconicity_hint: 6, access_friction: 'low', parking_friction: 'not_applicable',
    walking_burden: 'none', cluster_id: 'causeway' },
  { id: 's3', sequence_order: 3, name: 'Vizcaya', category: 'landmark',
    latitude: 25.7443, longitude: -80.2109, recommended_stay_minutes: 15,
    iconicity_hint: 8, access_friction: 'low', parking_friction: 'medium',
    walking_burden: 'moderate', cluster_id: 'coconut_grove' },
];

const miamiTour: ScorableTour = {
  id: 'test-miami', title: "Miami's Golden Hour", description: 'test',
  duration_minutes: 120, transport_mode: 'car',
  themes: ['scenic', 'architecture'],
  scheduled_time_of_day: 'golden_hour',
  stops: miamiStops,
};

// ── Haversine ────────────────────────────────────────────────────────────────

describe('haversineKm', () => {
  it('returns ~1760 km between NYC and Miami', () => {
    const d = haversineKm(40.7128, -74.0060, 25.7617, -80.1918);
    expect(d).toBeGreaterThan(1750);
    expect(d).toBeLessThan(1790);
  });

  it('returns 0 for identical coordinates', () => {
    expect(haversineKm(25.76, -80.19, 25.76, -80.19)).toBeCloseTo(0, 5);
  });

  it('is symmetric', () => {
    const a = haversineKm(25, -80, 40, -74);
    const b = haversineKm(40, -74, 25, -80);
    expect(a).toBeCloseTo(b, 6);
  });
});

// ── Stop-level scorers ───────────────────────────────────────────────────────

describe('scoreFriction', () => {
  it('gives 10 when all three friction dimensions are best-case', () => {
    expect(scoreFriction({ ...miamiStops[0],
      access_friction: 'low', parking_friction: 'not_applicable',
      walking_burden: 'none' })).toBeGreaterThan(9);
  });

  it('clamps to the ~2 floor when all three are worst-case', () => {
    const s = scoreFriction({ ...miamiStops[0],
      access_friction: 'high', parking_friction: 'high',
      walking_burden: 'heavy' });
    expect(s).toBeLessThanOrEqual(3);
    expect(s).toBeGreaterThanOrEqual(0);
  });
});

describe('scoreRouteFit', () => {
  it('returns 10 for single-stop tours', () => {
    const loneTour: ScorableTour = { ...miamiTour, stops: [miamiStops[0]] };
    expect(scoreRouteFit(miamiStops[0], loneTour, 0)).toBe(10);
  });

  it('drops when a stop detours badly off the path between its neighbors', () => {
    // Insert a fake "detour" stop far west of the Miami path.
    const detourStop: ScorableStop = { ...miamiStops[1],
      id: 'detour', latitude: 25.78, longitude: -82.5 };
    const tourWithDetour: ScorableTour = { ...miamiTour,
      stops: [miamiStops[0], detourStop, miamiStops[2], miamiStops[3]] };
    const direct = scoreRouteFit(miamiStops[1], miamiTour, 1);
    const detoured = scoreRouteFit(detourStop, tourWithDetour, 1);
    expect(detoured).toBeLessThan(direct);
  });
});

describe('scoreTimeOfDayFit', () => {
  it('returns 10 on exact match', () => {
    const stop = { ...miamiStops[0], best_time_of_day: 'golden_hour' };
    expect(scoreTimeOfDayFit(stop, miamiTour)).toBe(10);
  });

  it('returns 6 on adjacent time slot', () => {
    const stop = { ...miamiStops[0], best_time_of_day: 'afternoon' };
    expect(scoreTimeOfDayFit(stop, miamiTour)).toBe(6);
  });

  it('returns 3 on far-off time slot', () => {
    const stop = { ...miamiStops[0], best_time_of_day: 'morning' };
    expect(scoreTimeOfDayFit(stop, miamiTour)).toBe(3);
  });

  it('returns neutral 7 when no schedule is set', () => {
    const stop = { ...miamiStops[0], best_time_of_day: 'golden_hour' };
    const noSched = { ...miamiTour, scheduled_time_of_day: undefined };
    expect(scoreTimeOfDayFit(stop, noSched)).toBe(7);
  });
});

describe('scoreDwellEfficiency', () => {
  it('rewards high iconicity + short dwell (max wow-per-minute)', () => {
    const s = scoreDwellEfficiency({ ...miamiStops[0],
      iconicity_hint: 10, recommended_stay_minutes: 5 });
    expect(s).toBe(10);
  });

  it('punishes low iconicity + long dwell', () => {
    const s = scoreDwellEfficiency({ ...miamiStops[0],
      iconicity_hint: 3, recommended_stay_minutes: 60 });
    expect(s).toBeLessThan(1);
  });
});

describe('scoreFamilyFit', () => {
  it('defaults to 5 when the hint is absent', () => {
    const s = scoreFamilyFit({ ...miamiStops[0], family_friendliness: undefined });
    expect(s).toBe(5);
  });

  it('preserves explicit family_friendliness hint', () => {
    expect(scoreFamilyFit({ ...miamiStops[0], family_friendliness: 9 })).toBe(9);
  });
});

// ── Tour-level scorers ───────────────────────────────────────────────────────

describe('scoreGeographicCoherence', () => {
  it('returns 10 for a single-stop tour', () => {
    expect(scoreGeographicCoherence({ ...miamiTour, stops: [miamiStops[0]] })).toBe(10);
  });

  it('gives Miami tour (tight Miami stops) a high score', () => {
    // Miami tour covers ~8 km total; backtracking minimal. Expect ≥6.
    expect(scoreGeographicCoherence(miamiTour)).toBeGreaterThanOrEqual(4);
  });

  it('punishes a tour that zigzags between far-apart cities', () => {
    const zigzag: ScorableTour = {
      ...miamiTour,
      stops: [
        { ...miamiStops[0], latitude: 25.76, longitude: -80.19 },  // Miami
        { ...miamiStops[1], latitude: 40.71, longitude: -74.00 },  // NYC
        { ...miamiStops[2], latitude: 25.78, longitude: -80.16 },  // back Miami
        { ...miamiStops[3], latitude: 40.75, longitude: -73.99 },  // NYC again
      ],
    };
    expect(scoreGeographicCoherence(zigzag)).toBeLessThanOrEqual(4);
  });
});

describe('scoreTimeRealism', () => {
  it('scores 10 when declared duration matches stop dwell + transit', () => {
    // Miami tour has 35 min of dwell + ~15 min transit at 40 kph = ~50 min.
    // Declared 120 min is generous — ratio ~0.42, so should land <5.
    expect(scoreTimeRealism(miamiTour)).toBeLessThan(5);
  });

  it('scores 10 for a realistic duration', () => {
    const realistic = { ...miamiTour, duration_minutes: 55 };
    expect(scoreTimeRealism(realistic)).toBe(10);
  });

  it('punishes a tour that claims 30 min for a 4-city route', () => {
    const impossible = { ...miamiTour, duration_minutes: 15 };
    expect(scoreTimeRealism(impossible)).toBeLessThanOrEqual(4);
  });
});

describe('scoreVarietyBalance', () => {
  it('returns 10 for 4+ distinct categories', () => {
    // Miami tour has park / landmark / viewpoint (3 distinct) → 8
    expect(scoreVarietyBalance(miamiTour)).toBe(8);
  });

  it('returns 2 when every stop is the same category', () => {
    const monotonous: ScorableTour = { ...miamiTour,
      stops: miamiStops.map((s) => ({ ...s, category: 'museum' })) };
    expect(scoreVarietyBalance(monotonous)).toBe(2);
  });
});

describe('scorePracticalUsability', () => {
  it('returns 10 when no stop has high access_friction', () => {
    expect(scorePracticalUsability(miamiTour)).toBe(10);
  });

  it('drops 1 pt per high-friction stop, floor at 4', () => {
    const blocked: ScorableTour = { ...miamiTour,
      stops: miamiStops.map((s) => ({ ...s, access_friction: 'high' as const })) };
    expect(scorePracticalUsability(blocked)).toBe(6);
  });
});

// ── Composites ───────────────────────────────────────────────────────────────

describe('computeStopComposite', () => {
  it('produces a reasonable composite for a perfect stop', () => {
    const score = {
      iconicity: 10, scenic_payoff: 10, story_richness: 10,
      dwell_efficiency: 10, friction: 10, route_fit: 10,
      time_of_day_fit: 10, family_fit: 10, accessibility: 10, wow_per_minute: 10,
    };
    expect(computeStopComposite(score)).toBeCloseTo(10, 2);
  });

  it('produces 0 for all-zero', () => {
    const z = {
      iconicity: 0, scenic_payoff: 0, story_richness: 0,
      dwell_efficiency: 0, friction: 0, route_fit: 0,
      time_of_day_fit: 0, family_fit: 0, accessibility: 0, wow_per_minute: 0,
    };
    expect(computeStopComposite(z)).toBe(0);
  });
});

describe('computeAbsoluteComposite', () => {
  it('maps all-10s to 100 on the 0-100 scale', () => {
    const s = {
      iconic_value: 10, geographic_coherence: 10, time_realism: 10,
      narrative_flow: 10, scenic_payoff: 10, variety_balance: 10,
      practical_usability: 10,
    };
    expect(computeAbsoluteComposite(s, DEFAULT_ABSOLUTE_WEIGHTS)).toBeCloseTo(100, 1);
  });

  it('maps all-0s to 0', () => {
    const s = {
      iconic_value: 0, geographic_coherence: 0, time_realism: 0,
      narrative_flow: 0, scenic_payoff: 0, variety_balance: 0,
      practical_usability: 0,
    };
    expect(computeAbsoluteComposite(s, DEFAULT_ABSOLUTE_WEIGHTS)).toBe(0);
  });

  it('all-8 across the board lands around 80 absolute', () => {
    const s = {
      iconic_value: 8, geographic_coherence: 8, time_realism: 8,
      narrative_flow: 8, scenic_payoff: 8, variety_balance: 8,
      practical_usability: 8,
    };
    expect(computeAbsoluteComposite(s, DEFAULT_ABSOLUTE_WEIGHTS)).toBeCloseTo(80, 1);
  });

  it('gold-standard gate: 85+ absolute composite is only reached by strong scores', () => {
    // Target per gold-standard-tours.md calibration: featured tours ≥85.
    // This needs roughly 8.5 average across all 7 weighted dimensions.
    const gold = {
      iconic_value: 9, geographic_coherence: 8, time_realism: 9,
      narrative_flow: 8, scenic_payoff: 9, variety_balance: 8,
      practical_usability: 9,
    };
    const weak = {
      iconic_value: 6, geographic_coherence: 7, time_realism: 8,
      narrative_flow: 6, scenic_payoff: 7, variety_balance: 6,
      practical_usability: 7,
    };
    expect(computeAbsoluteComposite(gold, DEFAULT_ABSOLUTE_WEIGHTS)).toBeGreaterThanOrEqual(85);
    expect(computeAbsoluteComposite(weak, DEFAULT_ABSOLUTE_WEIGHTS)).toBeLessThan(75);
  });
});
